---
name: technical-debt
description: Audit code health with repository-native evidence and produce a focused, prioritized refactoring roadmap. Use for technical-debt audits, code-health checks, maintainability risks, or refactoring plans.
---

# Technical-debt audit

Audit evidence, not guesses. Use the repository's existing checks, recent
history, architecture documents, and fast repository-native inspection such as
`rg` and `git`. Do not assume tools, issue trackers, coverage data, or an
external SQALE model exist.

## Workflow

1. Establish scope: whole repository, a subsystem, or a change. Read the
   applicable `AGENTS.md`, README, architecture notes, and test/CI entrypoints.
2. Gather evidence proportionate to scope. Look for duplicated ownership,
   unclear module boundaries, dead or unsupported paths, fragile interfaces,
   untested failure modes, stale dependencies, slow or unreliable checks, and
   documentation that contradicts behavior. Run safe existing checks when they
   materially support a finding.
3. Record each finding with a concrete location, observed evidence, consequence,
   and a falsifiable remediation. Absence of a metric is a limitation, not a
   finding.
4. Rank findings by impact, confidence, and relative effort (`S`, `M`, or `L`).
   State uncertainty explicitly. Do not invent hours, debt ratios, or trends
   without repository data that supports them.
5. Separate immediate health/risk work from optional architectural proposals.
   A proposal should name its expected payoff, migration boundary, and the
   condition that would make it worth doing.

## Output

Start with the highest-value conclusion. Then provide a compact inventory:

| Priority | Finding | Evidence | Impact | Confidence | Effort | Next action |
| --- | --- | --- | --- | --- | --- | --- |

Follow it with:

- **Now:** safe, high-confidence fixes or measurements.
- **Next:** bounded investments that need planning.
- **Defer:** low-value or weakly evidenced ideas, with the trigger for revisiting.
- **Limits:** important evidence that was unavailable.

Do not recommend a broad rewrite merely because code is unfamiliar or old. When
several components are involved, use a small diagram or table only if it makes
ownership or dependencies easier to understand.
