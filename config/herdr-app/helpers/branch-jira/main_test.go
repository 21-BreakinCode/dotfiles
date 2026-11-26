package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var testCreds = creds{"https://example.atlassian.net", "me@example.com", "test-token"}

type sent struct {
	method, path string
	body         Obj
}

func mock(t *testing.T, f func(r sent) (int, any)) *[]sent {
	oldT, oldR := transport, readCreds
	t.Cleanup(func() { transport, readCreds = oldT, oldR })
	readCreds = func() (creds, error) { return testCreds, nil }
	log := &[]sent{}
	transport = func(_ context.Context, c creds, method, path string, payload []byte) (int, []byte, error) {
		if c != testCreds {
			t.Fatalf("unexpected creds")
		}
		r := sent{method: method, path: path}
		if payload != nil {
			if err := json.Unmarshal(payload, &r.body); err != nil {
				t.Fatal(err)
			}
		}
		*log = append(*log, r)
		status, body := f(r)
		b, _ := json.Marshal(body)
		return status, b, nil
	}
	return log
}

func raw(key, summary string) Obj {
	return Obj{"id": "100", "key": key, "fields": Obj{
		"summary": summary, "created": "2026-01-02T03:04:05.000+0800", "updated": "2026-01-02T03:04:05.000+0800",
		"status":   Obj{"id": "3", "name": "In Progress", "statusCategory": Obj{"key": "indeterminate"}},
		"priority": Obj{"name": "High"}, "assignee": Obj{"accountId": "a1", "displayName": "Ann"},
		"project": Obj{"key": "CR", "name": "Creative"}, "labels": []any{"bug"}, "issuetype": Obj{"name": "Story"},
		"description": Obj{"type": "doc", "content": []any{Obj{"type": "paragraph", "content": []any{Obj{"type": "text", "text": "Why"}}}}},
		"parent":      Obj{"key": "CR-1", "fields": Obj{"summary": "Epic"}},
		"subtasks":    []any{Obj{"id": "101", "key": "CR-8", "fields": Obj{"summary": "Part", "status": Obj{"name": "Done", "statusCategory": Obj{"key": "done"}}}}},
	}}
}

func TestJQLCombinesScopeStateProjectAndSearch(t *testing.T) {
	cases := map[string]Request{
		`assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`:                         {Scope: "mine"},
		`sprint in openSprints() AND statusCategory = "In Progress" AND project = CR ORDER BY updated DESC`: {Scope: "sprint", State: "started", Project: "CR"},
		`key = CR-12 ORDER BY updated DESC`:                                                                 {State: "all", Search: "cr-12"},
		`statusCategory != Done AND text ~ "fix login" ORDER BY updated DESC`:                               {Search: ` fix "login"* `},
		`created is not EMPTY ORDER BY updated DESC`:                                                        {Scope: "all", State: "all"},
	}
	for want, r := range cases {
		if got, err := jql(r); err != nil || got != want {
			t.Errorf("%+v: got %q %v", r, got, err)
		}
	}
	for _, r := range []Request{{Scope: "bogus"}, {State: "bogus"}, {Project: "CR OR 1=1"}} {
		if _, err := jql(r); err == nil {
			t.Errorf("%+v: expected an error", r)
		}
	}
}

func TestListMapsIssuesAndPages(t *testing.T) {
	log := mock(t, func(r sent) (int, any) {
		return 200, Obj{"issues": []any{raw("CR-7", "Fix")}, "nextPageToken": "tok", "isLast": false}
	})
	out, err := handle(context.Background(), Request{Action: "list", Scope: "mine", Cursor: "prev"})
	if err != nil {
		t.Fatal(err)
	}
	if r := (*log)[0]; r.method != "POST" || r.path != "/rest/api/3/search/jql" || r.body["nextPageToken"] != "prev" || r.body["maxResults"] != float64(50) {
		t.Fatalf("request %+v", r)
	}
	items := array(object(out)["items"])
	item := object(items[0])
	if object(out)["cursor"] != "tok" || item["identifier"] != "CR-7" || item["url"] != "https://example.atlassian.net/browse/CR-7" ||
		item["updatedAt"] != "2026-01-01T19:04:05Z" || object(item["state"])["type"] != "started" || object(item["assignee"])["displayName"] != "Ann" {
		t.Fatalf("item %v", item)
	}
}

func TestAMissingKeySearchIsNoMatch(t *testing.T) {
	mock(t, func(r sent) (int, any) {
		return 400, Obj{"errorMessages": []any{"The issue key 'ZZ-1' for field 'key' is invalid."}}
	})
	out, err := handle(context.Background(), Request{Action: "list", Search: "ZZ-1"})
	if err != nil || len(array(object(out)["items"])) != 0 {
		t.Fatalf("got %v %v", out, err)
	}
	if _, err := handle(context.Background(), Request{Action: "list", Search: "text"}); err == nil || !strings.Contains(err.Error(), "is invalid") {
		t.Fatalf("expected Jira's message, got %v", err)
	}
}

func TestResolveDropsUnknownKeysAndPaginatesComments(t *testing.T) {
	log := mock(t, func(r sent) (int, any) {
		switch {
		case strings.HasPrefix(r.path, "/rest/api/3/issue/CR-7/comment?startAt=0&"):
			return 200, Obj{"total": 2, "comments": []any{Obj{"id": "c1", "author": Obj{"displayName": "Bob"}, "body": Obj{"type": "doc", "content": []any{}}}}}
		case strings.HasPrefix(r.path, "/rest/api/3/issue/CR-7/comment?startAt=1&"):
			return 200, Obj{"total": 2, "comments": []any{Obj{"id": "c2", "author": Obj{"displayName": "Cam"}}}}
		case strings.HasPrefix(r.path, "/rest/api/3/issue/CR-7?"):
			return 200, raw("CR-7", "Fix")
		}
		return 404, Obj{"errorMessages": []any{"Issue does not exist or you do not have permission to see it."}}
	})
	out, err := handle(context.Background(), Request{Action: "resolve", Identifiers: []string{"CR-7", "FIX-123", "not-an-id", "../x"}})
	if err != nil {
		t.Fatal(err)
	}
	items := array(object(out)["items"])
	if len(items) != 1 || len(*log) != 4 {
		t.Fatalf("items %v, %d requests", items, len(*log))
	}
	issue := object(items[0])
	comments := array(issue["comments"])
	if len(comments) != 2 || object(comments[0])["url"] != "https://example.atlassian.net/browse/CR-7?focusedCommentId=c1" ||
		issue["description"] != "Why" || object(issue["parent"])["identifier"] != "CR-1" || len(array(issue["children"])) != 1 ||
		object(object(array(issue["children"])[0])["state"])["type"] != "completed" {
		t.Fatalf("issue %v", issue)
	}
	if _, err := handle(context.Background(), Request{Action: "detail", Identifier: "FIX-123"}); err == nil || !strings.Contains(err.Error(), "not found") {
		t.Fatalf("expected not found, got %v", err)
	}
}

func TestCommentSendsADFAndCredentialErrorsSayWhatToDo(t *testing.T) {
	log := mock(t, func(r sent) (int, any) { return 201, Obj{"id": "c9"} })
	out, err := handle(context.Background(), Request{Action: "comment", Issue: "CR-7", Body: "hi"})
	if err != nil || object(out)["id"] != "c9" {
		t.Fatalf("%v %v", out, err)
	}
	if r := (*log)[0]; r.method != "POST" || r.path != "/rest/api/3/issue/CR-7/comment" || object(r.body["body"])["type"] != "doc" {
		t.Fatalf("request %+v", r)
	}
	for _, bad := range []Request{{Action: "comment", Issue: "CR-7", Body: " "}, {Action: "comment", Issue: "../myself", Body: "x"}, {Action: "update", Issue: "CR-7"}} {
		if _, err := handle(context.Background(), bad); err == nil {
			t.Errorf("%+v: expected an error", bad)
		}
	}
	readCreds = func() (creds, error) { return creds{}, missingCreds }
	if _, err := handle(context.Background(), Request{Action: "viewer"}); err == nil || !strings.Contains(err.Error(), "JIRA_API_TOKEN") {
		t.Fatalf("expected missing creds, got %v", err)
	}
	readCreds = func() (creds, error) { return testCreds, nil }
	transport = func(context.Context, creds, string, string, []byte) (int, []byte, error) {
		return 401, []byte(`{}`), nil
	}
	if _, err := handle(context.Background(), Request{Action: "viewer"}); err == nil || !strings.Contains(err.Error(), "rejected") {
		t.Fatalf("expected rejected, got %v", err)
	}
}

func TestLoadCredsIgnoresAShellGreetingAndNeedsHTTPS(t *testing.T) {
	shell := filepath.Join(t.TempDir(), "shell.sh")
	script := "#!/bin/sh\nJIRA_BASE_URL=https://x.atlassian.net/ JIRA_EMAIL=me@x JIRA_API_TOKEN=secret\necho Welcome back\neval \"$2\"\n"
	if err := os.WriteFile(shell, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("JIRA_BASE_URL", "")
	t.Setenv("JIRA_EMAIL", "")
	t.Setenv("JIRA_API_TOKEN", "")
	t.Setenv("SHELL", shell)
	if c, err := loadCreds(); err != nil || c != (creds{"https://x.atlassian.net", "me@x", "secret"}) {
		t.Fatalf("got %v", err)
	}
	t.Setenv("JIRA_BASE_URL", "http://x.atlassian.net")
	t.Setenv("JIRA_EMAIL", "me@x")
	t.Setenv("JIRA_API_TOKEN", "secret")
	if _, err := loadCreds(); err == nil || !strings.Contains(err.Error(), "https") {
		t.Fatalf("expected https error, got %v", err)
	}
}

func TestADFToMarkdown(t *testing.T) {
	p := func(kids ...any) Obj { return Obj{"type": "paragraph", "content": kids} }
	tx := func(s string, marks ...any) Obj { return Obj{"type": "text", "text": s, "marks": marks} }
	doc := Obj{"type": "doc", "content": []any{
		Obj{"type": "heading", "attrs": Obj{"level": 2.0}, "content": []any{tx("Goal")}},
		p(tx("see "), tx("docs", Obj{"type": "link", "attrs": Obj{"href": "https://d"}}), tx(" "), tx("now", Obj{"type": "strong"}),
			Obj{"type": "hardBreak"}, Obj{"type": "mention", "attrs": Obj{"text": "@Ann"}}, tx(" "), tx("x()", Obj{"type": "code"})),
		Obj{"type": "bulletList", "content": []any{Obj{"type": "listItem", "content": []any{p(tx("one"))}}, Obj{"type": "listItem", "content": []any{p(tx("two"))}}}},
		Obj{"type": "orderedList", "content": []any{Obj{"type": "listItem", "content": []any{p(tx("first"))}}}},
		Obj{"type": "codeBlock", "attrs": Obj{"language": "go"}, "content": []any{tx("a := 1")}},
		Obj{"type": "panel", "content": []any{p(tx("inside a panel"))}},
		Obj{"type": "somethingNew", "content": []any{tx("kept")}},
	}}
	want := "## Goal\n\nsee [docs](https://d) **now**\n@Ann `x()`\n\n- one\n- two\n\n1. first\n\n```go\na := 1\n```\n\ninside a panel\n\nkept"
	if got := adfToMarkdown(doc); got != want {
		t.Fatalf("got\n%s\nwant\n%s", got, want)
	}
	if adfToMarkdown(nil) != "" {
		t.Fatal("nil description")
	}
}

func TestMarkdownToADF(t *testing.T) {
	got, _ := json.Marshal(markdownToADF("Hello\nthere\n\n```sh\nmake test\n```\nbye"))
	want := `{"content":[{"content":[{"text":"Hello","type":"text"},{"type":"hardBreak"},{"text":"there","type":"text"}],"type":"paragraph"},{"attrs":{"language":"sh"},"content":[{"text":"make test","type":"text"}],"type":"codeBlock"},{"content":[{"text":"bye","type":"text"}],"type":"paragraph"}],"type":"doc","version":1}`
	if string(got) != want {
		t.Fatalf("got %s", got)
	}
}
