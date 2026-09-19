# Shell Environment Notes

- `cd` is aliased to zoxide (`z`). In Bash tool calls, use absolute paths instead of `cd` to avoid zoxide errors.
- `tree` is available for viewing folder structures.

## Plugin Configuration (env vars in ~/.zshrc)

### session-learner

Plugin source: `~/.claude/plugins/local/session-learner/`

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_SESSION_LEARNER_GIT_MODE` | `full` | `full` = inject git diff summary on session start; `sha-only` = just warn about commit count |
| `CLAUDE_SESSION_LEARNER_COMPACT_THRESHOLD` | `50` | Tool calls before suggesting `/compact` |
| `CLAUDE_SESSION_LEARNER_MAX_AGE_DAYS` | `7` | Days to keep session files in `~/.claude/sessions/` |

Optional dependency: `jq` (`brew install jq`) — needed for transcript parsing in SessionEnd hook. Without it, session summaries are minimal.