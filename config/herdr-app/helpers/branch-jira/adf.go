package main

import (
	"fmt"
	"strings"
)

// adfToMarkdown renders Jira's Atlassian Document Format as Markdown for the panel.
// Unknown nodes keep their text.
func adfToMarkdown(doc any) string {
	var b strings.Builder
	blocks(&b, array(object(doc)["content"]), "")
	return strings.TrimSpace(b.String())
}

// blocks writes block nodes, each line starting with prefix (a quote or list indent).
func blocks(b *strings.Builder, nodes []any, prefix string) {
	for _, raw := range nodes {
		n := object(raw)
		attrs := object(n["attrs"])
		kids := array(n["content"])
		switch text(n["type"]) {
		case "paragraph":
			b.WriteString(prefix + strings.ReplaceAll(inline(kids), "\n", "\n"+prefix) + "\n\n")
		case "heading":
			level, _ := attrs["level"].(float64)
			b.WriteString(prefix + strings.Repeat("#", max(1, int(level))) + " " + inline(kids) + "\n\n")
		case "bulletList", "orderedList":
			for i, item := range kids {
				marker := "- "
				if text(n["type"]) == "orderedList" {
					marker = fmt.Sprintf("%d. ", i+1)
				}
				var inner strings.Builder
				blocks(&inner, array(object(item)["content"]), "")
				lines := strings.Split(strings.TrimSpace(inner.String()), "\n")
				b.WriteString(prefix + marker + lines[0] + "\n")
				for _, line := range lines[1:] {
					if line != "" {
						b.WriteString(prefix + "   " + line + "\n")
					}
				}
			}
			b.WriteString("\n")
		case "codeBlock":
			code := inline(kids)
			b.WriteString(prefix + "```" + text(attrs["language"]) + "\n" + prefix + strings.ReplaceAll(code, "\n", "\n"+prefix) + "\n" + prefix + "```\n\n")
		case "blockquote":
			blocks(b, kids, prefix+"> ")
		case "rule":
			b.WriteString(prefix + "---\n\n")
		case "mediaSingle", "mediaGroup", "media":
			b.WriteString(prefix + "[attachment]\n\n")
		case "blockCard", "embedCard":
			b.WriteString(prefix + "<" + text(attrs["url"]) + ">\n\n")
		case "table":
			for _, row := range kids {
				cells := []string{}
				for _, cell := range array(object(row)["content"]) {
					var inner strings.Builder
					blocks(&inner, array(object(cell)["content"]), "")
					cells = append(cells, strings.ReplaceAll(strings.TrimSpace(inner.String()), "\n", " "))
				}
				b.WriteString(prefix + "| " + strings.Join(cells, " | ") + " |\n")
			}
			b.WriteString("\n")
		default:
			// panel, expand, layouts and anything new: their children, or their inline text.
			if len(kids) > 0 && !inlineTypes[text(object(kids[0])["type"])] {
				blocks(b, kids, prefix)
			} else if s := inline(kids); s != "" {
				b.WriteString(prefix + s + "\n\n")
			}
		}
	}
}

var inlineTypes = map[string]bool{"text": true, "hardBreak": true, "mention": true, "emoji": true, "inlineCard": true, "status": true, "date": true}

func inline(nodes []any) string {
	var b strings.Builder
	for _, raw := range nodes {
		n := object(raw)
		attrs := object(n["attrs"])
		switch text(n["type"]) {
		case "text":
			s := text(n["text"])
			for _, m := range array(n["marks"]) {
				mark := object(m)
				switch text(mark["type"]) {
				case "strong":
					s = "**" + s + "**"
				case "em":
					s = "_" + s + "_"
				case "strike":
					s = "~~" + s + "~~"
				case "code":
					s = "`" + s + "`"
				case "link":
					s = "[" + s + "](" + text(object(mark["attrs"])["href"]) + ")"
				}
			}
			b.WriteString(s)
		case "hardBreak":
			b.WriteString("\n")
		case "mention":
			name := text(attrs["text"])
			if !strings.HasPrefix(name, "@") {
				name = "@" + name
			}
			b.WriteString(name)
		case "emoji":
			if s := text(attrs["text"]); s != "" {
				b.WriteString(s)
			} else {
				b.WriteString(text(attrs["shortName"]))
			}
		case "inlineCard":
			b.WriteString("<" + text(attrs["url"]) + ">")
		case "status":
			b.WriteString("[" + text(attrs["text"]) + "]")
		case "date":
			b.WriteString(text(attrs["timestamp"]))
		default:
			b.WriteString(inline(array(n["content"])))
		}
	}
	return b.String()
}

// markdownToADF turns a typed comment into ADF: fenced code blocks, and paragraphs
// split on blank lines with single newlines kept as line breaks.
// shortcut: other Markdown (bold, lists, links) is sent as literal text; add marks if people miss them.
func markdownToADF(body string) Obj {
	content := []any{}
	var para []string
	flush := func() {
		if len(para) == 0 {
			return
		}
		runs := []any{}
		for i, line := range para {
			if i > 0 {
				runs = append(runs, Obj{"type": "hardBreak"})
			}
			runs = append(runs, Obj{"type": "text", "text": line})
		}
		content = append(content, Obj{"type": "paragraph", "content": runs})
		para = nil
	}
	lines := strings.Split(strings.ReplaceAll(body, "\r\n", "\n"), "\n")
	for i := 0; i < len(lines); i++ {
		line := lines[i]
		if fence := strings.TrimSpace(line); strings.HasPrefix(fence, "```") {
			flush()
			code := []string{}
			for i++; i < len(lines) && strings.TrimSpace(lines[i]) != "```"; i++ {
				code = append(code, lines[i])
			}
			block := Obj{"type": "codeBlock", "content": []any{}}
			if lang := strings.TrimSpace(strings.TrimPrefix(fence, "```")); lang != "" {
				block["attrs"] = Obj{"language": lang}
			}
			if joined := strings.Join(code, "\n"); joined != "" {
				block["content"] = []any{Obj{"type": "text", "text": joined}}
			}
			content = append(content, block)
			continue
		}
		if strings.TrimSpace(line) == "" {
			flush()
			continue
		}
		para = append(para, line)
	}
	flush()
	return Obj{"type": "doc", "version": 1, "content": content}
}
