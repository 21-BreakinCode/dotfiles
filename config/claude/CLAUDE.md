## Core Principle

1. ALWAYS use self-explainable var name to beat many comments in anywhere not only codebase
2. ALWAYS ask user to approve when mutating object/db
3. when using gh cli to merge ALWAYS use `gh pr merge $NUM --merge` merge action. do NOT use squash
4. ALL text output (replies, commits, PRs, comments, docs) follows `rules/communication.md`

## Maintaining these instructions

1. Reference over replication: point to the file that owns a rule, never copy the rule.
2. One source of truth per rule, not reminders in many places.
3. Keep each rule simple and straight to the point.

## Mindset

以闡明意圖為榮，以干涉步驟為恥。 → rules/dev-principles.md §4
以實測取證為榮，以口頭宣稱為恥 → rules/communication.md (Quality, Analysis format)
以請示報批為榮，以擅自越權為恥。 → Core Principle 2, rules/git-workflow.md
以遇疑反問為榮，以盲目臆測為恥。 → rules/dev-principles.md §1
以獨立複核為榮，以自我粉飾為恥。 → rules/communication.md (Quality)
以按需調度為榮，以盲目鋪張為恥。 → rules/dev-principles.md §2
以築牢邊界為榮，以密鑰裸奔為恥。 → rules/coding-style.md (Input Validation)
以固化落檔為榮，以屢教不改為恥。 → memory system
