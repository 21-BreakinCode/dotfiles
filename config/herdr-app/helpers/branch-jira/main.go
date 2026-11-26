// herdr-jira is a JSON bridge between the Herdr mod and Jira Cloud's REST API v3.
// Credentials come only from JIRA_BASE_URL, JIRA_EMAIL and JIRA_API_TOKEN.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

// ── Request shape and swappable I/O ────────────────────────────────────────

type Obj = map[string]any
type Request struct {
	Action      string   `json:"action"`
	Identifier  string   `json:"identifier"`
	Identifiers []string `json:"identifiers"`
	Issue       string   `json:"issue"`
	Scope       string   `json:"scope"`
	State       string   `json:"state"`
	Project     string   `json:"project"`
	Search      string   `json:"search"`
	Cursor      string   `json:"cursor"`
	Body        string   `json:"body"`
}

type creds struct{ base, email, token string }

var missingCreds = errors.New("JIRA_BASE_URL, JIRA_EMAIL and JIRA_API_TOKEN are not all set. Export them in your shell environment, then refresh.")
var rejectedCreds = errors.New("Jira rejected JIRA_EMAIL / JIRA_API_TOKEN. Export a valid API token, then refresh.")
var keyPattern = regexp.MustCompile(`^([A-Za-z][A-Za-z0-9]*)-([1-9][0-9]*)$`)
var idPattern = regexp.MustCompile(`^[0-9]+$`)
var projectPattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]*$`)

// Swapped in tests.
var transport = httpDo
var readCreds = loadCreds

// ── Transport and credential lookup ─────────────────────────────────────────

// Never follow a redirect: the credentials go to JIRA_BASE_URL and nowhere else.
var client = &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

func httpDo(ctx context.Context, c creds, method, path string, payload []byte) (int, []byte, error) {
	var body io.Reader
	if payload != nil {
		body = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, body)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Accept", "application/json")
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.SetBasicAuth(c.email, c.token)
	res, err := client.Do(req)
	if err != nil {
		return 0, nil, fmt.Errorf("Jira is unreachable: %w", err)
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(res.Body, 8<<20))
	return res.StatusCode, raw, err
}

// GUI-launched apps often lack the shell's exports, so ask a login shell too.
func loadCreds() (creds, error) {
	vals := []string{os.Getenv("JIRA_BASE_URL"), os.Getenv("JIRA_EMAIL"), os.Getenv("JIRA_API_TOKEN")}
	if vals[0] == "" || vals[1] == "" || vals[2] == "" {
		shell := os.Getenv("SHELL")
		if shell == "" {
			shell = "/bin/sh"
		}
		// Startup files may print a greeting or wait for input: take the last three lines, within a limit.
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		out, err := exec.CommandContext(ctx, shell, "-lic", `printf '\n%s\n%s\n%s' "$JIRA_BASE_URL" "$JIRA_EMAIL" "$JIRA_API_TOKEN"`).Output()
		if lines := strings.Split(string(out), "\n"); err == nil && len(lines) >= 3 {
			vals = lines[len(lines)-3:]
		}
	}
	c := creds{strings.TrimRight(strings.TrimSpace(vals[0]), "/"), strings.TrimSpace(vals[1]), strings.TrimSpace(vals[2])}
	if c.base == "" || c.email == "" || c.token == "" {
		return creds{}, missingCreds
	}
	if u, err := url.Parse(c.base); err != nil || u.Scheme != "https" || u.Host == "" {
		return creds{}, errors.New("JIRA_BASE_URL must be an https:// URL such as https://example.atlassian.net")
	}
	return c, nil
}

// call sends one request and decodes the JSON answer into out (when not nil).
func call(ctx context.Context, c creds, method, path string, body any, out any) (int, error) {
	var payload []byte
	if body != nil {
		payload, _ = json.Marshal(body)
	}
	status, raw, err := transport(ctx, c, method, path, payload)
	if err != nil {
		return status, err
	}
	if status == 401 || status == 403 {
		return status, rejectedCreds
	}
	if status >= 400 {
		var e struct {
			ErrorMessages []string          `json:"errorMessages"`
			Errors        map[string]string `json:"errors"`
		}
		_ = json.Unmarshal(raw, &e)
		msgs := e.ErrorMessages
		for _, m := range e.Errors {
			msgs = append(msgs, m)
		}
		if len(msgs) > 0 {
			return status, fmt.Errorf("Jira: %s", strings.Join(msgs, "; "))
		}
		return status, fmt.Errorf("Jira request failed (HTTP %d)", status)
	}
	if out != nil && json.Unmarshal(raw, out) != nil {
		return status, fmt.Errorf("Jira returned an unreadable response (HTTP %d)", status)
	}
	return status, nil
}

// ── Small JSON helpers ──────────────────────────────────────────────────

func object(v any) Obj { m, _ := v.(map[string]any); return m }
func array(v any) []any {
	a, _ := v.([]any)
	if a == nil {
		return []any{}
	}
	return a
}
func text(v any) string { s, _ := v.(string); return s }

// Jira's "2026-01-02T03:04:05.000+0800" to RFC 3339, which every Date parser reads.
func isoTime(v any) string {
	if t, err := time.Parse("2006-01-02T15:04:05.000-0700", text(v)); err == nil {
		return t.UTC().Format(time.RFC3339)
	}
	return text(v)
}

// ── Jira issues in the panel's shape ──────────────────────────────────────

// Status categories map to the workflow types the panel groups and orders by.
var categoryType = map[string]string{"new": "unstarted", "indeterminate": "started", "done": "completed"}
var categoryColor = map[string]string{"new": "#8f9ba8", "indeterminate": "#2f80ed", "done": "#2da44e"}

func statusOf(v any) Obj {
	s := object(v)
	if s == nil {
		return nil
	}
	cat := text(object(s["statusCategory"])["key"])
	return Obj{"id": s["id"], "name": s["name"], "type": categoryType[cat], "color": categoryColor[cat]}
}

func user(v any) Obj {
	u := object(v)
	if u == nil {
		return nil
	}
	return Obj{"id": u["accountId"], "name": u["displayName"], "displayName": u["displayName"]}
}

const cardFields = "summary,status,priority,assignee,issuetype,project,labels,created,updated"
const detailFields = cardFields + ",description,parent,subtasks"

func card(c creds, raw any) Obj {
	issue := object(raw)
	f := object(issue["fields"])
	key := text(issue["key"])
	labels := []any{}
	for _, l := range array(f["labels"]) {
		labels = append(labels, Obj{"id": l, "name": l})
	}
	project := object(f["project"])
	return Obj{
		"id":            issue["id"],
		"identifier":    key,
		"title":         f["summary"],
		"url":           c.base + "/browse/" + key,
		"priorityLabel": object(f["priority"])["name"],
		"createdAt":     isoTime(f["created"]),
		"updatedAt":     isoTime(f["updated"]),
		"state":         statusOf(f["status"]),
		"assignee":      user(f["assignee"]),
		"type":          Obj{"name": object(f["issuetype"])["name"]},
		"project":       Obj{"key": project["key"], "name": project["name"]},
		"labels":        labels,
	}
}

// ── Reads: viewer, list, detail ──────────────────────────────────────────

func viewer(ctx context.Context, c creds) (any, error) {
	var me Obj
	if _, err := call(ctx, c, "GET", "/rest/api/3/myself", nil, &me); err != nil {
		return nil, err
	}
	v := user(me)
	v["email"] = me["emailAddress"]
	return Obj{"viewer": v}, nil
}

var stateClauses = map[string]string{
	"active":  `statusCategory != Done`,
	"todo":    `statusCategory = "To Do"`,
	"started": `statusCategory = "In Progress"`,
	"done":    `statusCategory = Done`,
	"all":     "",
}

// Lucene's special characters can make a text search fail; they mean nothing to a person here.
var textNoise = regexp.MustCompile(`[+\-&|!(){}\[\]^~*?\\:"/#]+`)

func jql(r Request) (string, error) {
	clauses := []string{}
	switch r.Scope {
	case "mine":
		clauses = append(clauses, "assignee = currentUser()")
	case "sprint":
		clauses = append(clauses, "sprint in openSprints()")
	case "", "all":
	default:
		return "", errors.New("invalid scope")
	}
	state := r.State
	if state == "" {
		state = "active"
	}
	clause, ok := stateClauses[state]
	if !ok {
		return "", errors.New("invalid state")
	}
	if clause != "" {
		clauses = append(clauses, clause)
	}
	if r.Project != "" {
		if !projectPattern.MatchString(r.Project) {
			return "", errors.New("invalid project key")
		}
		clauses = append(clauses, "project = "+r.Project)
	}
	if q := strings.TrimSpace(r.Search); q != "" {
		if keyPattern.MatchString(q) {
			clauses = append(clauses, "key = "+strings.ToUpper(q))
		} else if words := strings.Join(strings.Fields(textNoise.ReplaceAllString(q, " ")), " "); words != "" {
			clauses = append(clauses, fmt.Sprintf("text ~ %q", words))
		}
	}
	// A JQL search needs at least one restriction.
	if len(clauses) == 0 {
		clauses = append(clauses, "created is not EMPTY")
	}
	return strings.Join(clauses, " AND ") + " ORDER BY updated DESC", nil
}

func list(ctx context.Context, c creds, r Request) (any, error) {
	query, err := jql(r)
	if err != nil {
		return nil, err
	}
	body := Obj{"jql": query, "maxResults": 50, "fields": strings.Split(cardFields, ",")}
	if r.Cursor != "" {
		body["nextPageToken"] = r.Cursor
	}
	var res struct {
		Issues        []any  `json:"issues"`
		NextPageToken string `json:"nextPageToken"`
		IsLast        bool   `json:"isLast"`
	}
	status, err := call(ctx, c, "POST", "/rest/api/3/search/jql", body, &res)
	// A key that names no issue (or no project) is an error to JQL, and no match to a person.
	if status == 400 && keyPattern.MatchString(strings.TrimSpace(r.Search)) {
		return Obj{"items": []any{}, "cursor": ""}, nil
	}
	if err != nil {
		return nil, err
	}
	items := []any{}
	for _, issue := range res.Issues {
		items = append(items, card(c, issue))
	}
	next := res.NextPageToken
	if res.IsLast {
		next = ""
	}
	return Obj{"items": items, "cursor": next}, nil
}

// An issue by key (CR-123) or numeric id, with every comment; nil when Jira has none.
func fetchIssue(ctx context.Context, c creds, ref string) (Obj, error) {
	if !keyPattern.MatchString(ref) && !idPattern.MatchString(ref) {
		return nil, nil
	}
	var raw Obj
	status, err := call(ctx, c, "GET", "/rest/api/3/issue/"+url.PathEscape(ref)+"?fields="+detailFields, nil, &raw)
	if status == 404 {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	issue := card(c, raw)
	f := object(raw["fields"])
	key := text(issue["identifier"])
	issue["description"] = adfToMarkdown(f["description"])
	if p := object(f["parent"]); p != nil {
		pk := text(p["key"])
		issue["parent"] = Obj{"identifier": pk, "title": object(p["fields"])["summary"], "url": c.base + "/browse/" + pk}
	}
	children := []any{}
	for _, s := range array(f["subtasks"]) {
		sub := object(s)
		sk := text(sub["key"])
		children = append(children, Obj{"id": sub["id"], "identifier": sk, "title": object(sub["fields"])["summary"], "url": c.base + "/browse/" + sk, "state": statusOf(object(sub["fields"])["status"])})
	}
	issue["children"] = children
	comments := []any{}
	for start := 0; ; {
		var page struct {
			Comments []any `json:"comments"`
			Total    int   `json:"total"`
		}
		if _, err := call(ctx, c, "GET", fmt.Sprintf("/rest/api/3/issue/%s/comment?startAt=%d&maxResults=100&orderBy=created", url.PathEscape(key), start), nil, &page); err != nil {
			return nil, err
		}
		for _, raw := range page.Comments {
			cm := object(raw)
			id := text(cm["id"])
			comments = append(comments, Obj{"id": id, "body": adfToMarkdown(cm["body"]), "url": c.base + "/browse/" + key + "?focusedCommentId=" + id, "createdAt": isoTime(cm["created"]), "updatedAt": isoTime(cm["updated"]), "user": user(cm["author"])})
		}
		start += len(page.Comments)
		if len(page.Comments) == 0 || start >= page.Total {
			break
		}
	}
	issue["comments"] = comments
	return issue, nil
}

// ── Dispatch: one JSON request in, one JSON result out ────────────────────

func handle(ctx context.Context, r Request) (any, error) {
	c, err := readCreds()
	if err != nil {
		return nil, err
	}
	switch r.Action {
	case "viewer":
		return viewer(ctx, c)
	case "list":
		return list(ctx, c, r)
	case "detail":
		if r.Identifier == "" {
			return nil, errors.New("identifier required")
		}
		issue, err := fetchIssue(ctx, c, r.Identifier)
		if err != nil {
			return nil, err
		}
		if issue == nil {
			return nil, fmt.Errorf("%s was not found in Jira", r.Identifier)
		}
		return issue, nil
	case "resolve":
		// Candidates from a branch name: unknown keys are dropped, not errors.
		found := []any{}
		for _, id := range r.Identifiers {
			if !keyPattern.MatchString(id) {
				continue
			}
			issue, err := fetchIssue(ctx, c, id)
			if err != nil {
				return nil, err
			}
			if issue != nil {
				found = append(found, issue)
			}
		}
		return Obj{"items": found}, nil
	case "comment":
		if strings.TrimSpace(r.Body) == "" || !keyPattern.MatchString(r.Issue) && !idPattern.MatchString(r.Issue) {
			return nil, errors.New("issue key and body required")
		}
		var res Obj
		if _, err := call(ctx, c, "POST", "/rest/api/3/issue/"+url.PathEscape(r.Issue)+"/comment", Obj{"body": markdownToADF(r.Body)}, &res); err != nil {
			return nil, err
		}
		return Obj{"id": res["id"]}, nil
	default:
		return nil, errors.New("unknown action")
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: herdr-jira '<JSON request>'")
		os.Exit(1)
	}
	var r Request
	if err := json.Unmarshal([]byte(os.Args[1]), &r); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 26*time.Second)
	defer cancel()
	result, err := handle(ctx, r)
	if err != nil {
		_ = json.NewEncoder(os.Stdout).Encode(Obj{"error": err.Error()})
		os.Exit(1)
	}
	_ = json.NewEncoder(os.Stdout).Encode(result)
}
