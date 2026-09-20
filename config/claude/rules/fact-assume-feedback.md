# fact-assume-feedback.md

## When to Apply

This is mandatory, with no exceptions, for these higher-stakes items: architecture decisions, impact assessment, and PR-blocking code review.

**ALWAYS** provide a one sentence sum up of each aspect to cut too many content which could distract user reading quality.

**When NOT to apply:** Pure implementation (writing code, running commands, creating files), quick explanations, "how does X work" questions, and short comparisons. Only apply when the response contains analysis, explanation, or judgment on one of the higher-stakes items above.

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
