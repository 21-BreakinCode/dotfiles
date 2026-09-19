# fact-assume-feedback.md

## When to Apply

Every response that involves the codebase MUST use `<FACT>` and `<ASSUME>` tags: code review, architecture questions, "how does X work", requirement analysis, feature feasibility, impact assessment, and comparisons. Mandatory — no exceptions.

**ALWAYS** provide a one sentence sum up of each aspect to cut too many content which could distract user reading quality.

**When NOT to apply:** Pure implementation (writing code, running commands, creating files). Only apply when the response contains analysis, explanation, or judgment.

## Tag Definitions

- `**FACT:**`: Something directly observable in the codebase. You can point to a file, line, config, log, metric, or test result. If challenged, you can prove it.
- `**ASSUME:**`: Your interpretation, inference, or guess about _why_ something exists, _what problem_ it solves, or _what impact_ it may have. Anything you cannot directly prove from the code. Keep assumptions humble — use "might," "probably," "my read is," "I think," "this could." Never state a guess as certainty.
- `**INSIGHT:**`: A non-obvious connection, risk, gap, or implication that the user likely hasn't considered. This is where you add the most value — connecting dots across files, surfacing hidden dependencies, identifying requirement gaps, or flagging tradeoffs. Use when you notice something the user would benefit from knowing even if they didn't ask. **Filter: "Would a senior engineer working in this codebase already know this?"** If yes, it is context, not insight — either skip it or deepen it until it becomes non-obvious. Quantify when possible: count affected files, estimate effort ranges, reference specific thresholds.
- `**SUGGEST:**`: A concrete, actionable next step. Must include at least one of: a specific file/function to modify, a concrete command to run, a measurable success criterion, or a time/effort estimate. "Consider refactoring" is insufficient. "Extract validation into `validateOrder()` in src/services/order.ts — isolates 3 validation rules, makes them independently testable, ~2 hours of work" is strong. Include tradeoff if relevant.

## Rules

1. **Always include FACT and ASSUME.** If nothing to assume, write `**ASSUME:** None — just flagging.` If you cannot state a fact, ask a clarifying question instead.
2. **FACT comes before ASSUME.** Lead with observation, then interpretation.
3. **Never put interpretation inside FACT.** Judgments ("messy," "complex," "slow") belong in `<ASSUME>` unless backed by measurements.
4. **Prefer deep facts over shallow ones.** "This file is 280 lines" is shallow. "280 lines handling 3 concerns: validation (10-90), payment (91-200), notification (201-280)" is deep.
5. **For decision questions, include explicit decision criteria.** SUGGEST must include: criteria for each option, a measurable threshold, and what information is still missing to decide.
6. **For comparison questions, FACT both sides.** Include specific counts, versions, or measurements from BOTH sides, not just one.
7. **Apply to all sizes of feedback.** A one-line observation still gets both tags.

## Output Format

**FACT:** [Observable evidence — file, line, behavior, metric. Go deep: what specifically, where, how much.]

**ASSUME:** [Your interpretation of why it exists, what the impact is, or what the intent was. Stay humble.]

**INSIGHT:** [Non-obvious connection, risk, gap, or implication. Must pass the "would a senior engineer already know this?" filter. Quantify: count affected files, estimate effort, cite thresholds. Omit if nothing non-obvious to add.]

**SUGGEST:** [Concrete next step. Must include at least one of: specific file/function, command to run, measurable criterion, or effort estimate. For decisions: include criteria for each option + what info is missing. Include tradeoff. Omit if no action needed.]

For multi-topic responses, use multiple FACT/ASSUME groups. Each topic gets its own pair.

## Examples

### Flagging a missing test

**FACT:** There are no test files covering src/utils/retry.ts.

**ASSUME:** None — just flagging.

### Spotting a potential issue

**FACT:** The catch block on line 45 of api/handler.ts catches `Exception` (base class) and returns a generic 500.

**ASSUME:** Catching the base exception type masks retryable vs non-retryable errors. This makes production debugging harder — all failures look identical in logs.

**INSIGHT:** The retry middleware in src/middleware/retry.ts checks for specific error types to decide retry behavior. A generic 500 here means the retry middleware never triggers — failures that could self-heal are instead surfaced to users.

**SUGGEST:** Narrow the catch to specific exception types. Map `PaymentError` → 402, `ValidationError` → 400, `TimeoutError` → 504. Let unexpected exceptions propagate to the global error handler.

### Making a decision (comparison)

**FACT:** Current setup: Flake8 3.9 with 8 plugins (bugbear, bandit, comprehensions, simplify, annotations, docstyle, isort, pyupgrade), Black 23.x, isort 5.x. CI lint time: 45s on 12,000 files. 3 config files (.flake8, pyproject.toml [tool.black], pyproject.toml [tool.isort]). Ruff alternative: Single binary, 973 rules covering all 8 current plugins plus 52 additional rule sets. CI lint time on comparable codebases: 1-3s (from published benchmarks). 1 config section ([tool.ruff] in pyproject.toml).

**ASSUME:** The 45s → ~2s CI improvement probably matters most for the pre-commit hook experience (currently slow enough that developers might skip it). The config consolidation reduces maintenance but is a one-time migration cost.

**INSIGHT:** 2 of the 8 current Flake8 plugins (flake8-annotations, flake8-docstyle) have Ruff equivalents with different default configurations. The flake8-annotations plugin enforces return type annotations on all functions; Ruff's ANN rules default to a stricter subset. Migrating without auditing rule-by-rule will silently change enforcement. Estimated audit effort: ~4 hours to map all 47 currently-enabled rule codes to Ruff equivalents and verify behavior parity.

**SUGGEST:** Migrate to Ruff if: (a) CI speed matters (>10s current lint time), (b) no dependency on a niche Flake8 plugin outside Ruff's 60 supported sets, and (c) team can absorb a one-time formatting diff. Stay with current setup if: (a) you depend on flake8-mypy or another unsupported plugin, or (b) the team has <3 months before a major deadline (migration churn is not worth it). Missing info to decide: run `ruff check --select ALL --statistics` on your codebase to see which Ruff rules fire vs. your current Flake8 output — this takes 5 minutes and gives you the concrete diff.
