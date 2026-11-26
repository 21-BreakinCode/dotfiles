// What this panel writes to Jira, always from an explicit click: comments. And the
// prompt box for handing an issue or comment to an agent.
export const changeMethods = {
  // Drafts are kept per issue, comment and agent, so an abandoned prompt survives navigation.
  compose(kind, parent, context, cx, options = {}) {
    if (this.mutating) return;
    this.composer = { kind, parent, context, ...options };
    this.target = options.target ?? null;
    this.draftKey = `jira-draft:${this.spaceKey}:${this.issue.id}:${kind}:${parent ?? "general"}:${options.target ?? ""}`;
    const draft = localStorage.getItem(this.draftKey);
    const text = draft ?? "Analyze this issue and suggest how to approach it.";
    this.editor.set_value(text);
    this.editor.set_selected_range({ start: text.length, end: text.length });
    this.editor.focus();
    cx.notify();
  },

  closeComposer(cx) {
    if (this.mutating) return;
    this.composer = null;
    this.draftKey = null;
    cx.notify();
  },

  // The draft is only cleared once Jira has accepted it.
  postComment(cx) {
    if (this.mutating) return;
    const draft = this.commentKey;
    const body = this.newComment.value();
    const key = this.spaceKey;
    const issue = this.issue;
    this.mutating = true;
    this.error = null;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        await this.api({ action: "comment", issue: issue.identifier, body });
        if (key !== this.spaceKey || issue.id !== this.issue?.id) return;
        this.newComment.set_value("");
        localStorage.removeItem(draft);
        this.notice = "Saved to Jira.";
        this.openIssue(issue.identifier, cx);
      } catch (e) {
        if (key === this.spaceKey)
          this.error = `${e.message}. Refresh before retrying if the request may have succeeded.`;
      } finally {
        this.mutating = false;
        cx.notify();
      }
    });
  },
};
