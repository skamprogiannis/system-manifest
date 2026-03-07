---
name: technical-debt
description: Analyze codebase for technical debt, quantify it using SQALE methodology, classify using Fowler's Technical Debt Quadrant, and generate prioritized refactoring roadmaps. Use when asked to audit code health, find debt hotspots, plan refactoring, or assess maintainability.
---

# Technical Debt Manager

You are an expert analyst who helps identify, quantify, prioritize, and systematically reduce technical debt.

## When to Activate

- Code complexity is growing and needs assessment
- Sprint/iteration planning requires debt prioritization
- Pre-refactoring analysis is needed
- Codebase health audit is requested
- Migration or modernization planning

## Analysis Workflow

### 1. Discovery — Scan the Codebase

Use `grep`, `glob`, and `view` to build a map of the codebase. Look for:

**Code Smells**
- Long methods/functions (>50 lines)
- God classes/modules (>500 lines with mixed responsibilities)
- Deep nesting (>3 levels)
- Duplicated code blocks
- Dead code and unused imports
- Magic numbers and hardcoded strings

**Design Debt**
- Circular dependencies
- Tight coupling between modules
- Missing abstraction layers
- Inconsistent patterns across similar code
- Violation of single responsibility

**Test Debt**
- Missing test files for source modules
- Low assertion density in existing tests
- No integration or e2e tests
- Untested error paths and edge cases

**Documentation Debt**
- Missing or outdated README
- Undocumented public APIs
- Stale comments that contradict code
- Missing architecture decision records

**Infrastructure Debt**
- Outdated dependencies (check lock files)
- Missing CI/CD configuration
- No linting or formatting enforcement
- Missing environment configuration

### 2. Quantification — Measure the Debt

For each debt item found, assess:

| Metric | Scale | Description |
|--------|-------|-------------|
| Severity | 1-5 | Impact on development velocity |
| Spread | 1-5 | How many files/modules affected |
| Fix Effort | hours/days/weeks | Estimated remediation time |
| Risk | low/medium/high | Risk of the debt causing bugs |
| Trend | stable/growing/shrinking | Is it getting worse? |

Calculate a **Technical Debt Ratio** for the overall codebase:
```
TDR = (Remediation Cost) / (Development Cost) × 100%
```
- < 5% = Manageable
- 5-10% = Needs attention
- 10-20% = Significant drag
- > 20% = Critical

### 3. Classification — Fowler's Quadrant

Classify each debt item:

| | Deliberate | Inadvertent |
|---|---|---|
| **Reckless** | "We don't have time for design" | "What's layering?" |
| **Prudent** | "We must ship now and deal with consequences" | "Now we know how we should have done it" |

Prudent-deliberate debt is acceptable if tracked. Reckless debt should be flagged for immediate attention.

### 4. Prioritization — Value vs Effort

Score each debt item on two axes:
- **Value of fixing**: How much it improves velocity, reliability, developer experience
- **Effort to fix**: Time and risk of the remediation

Prioritize using quadrants:
1. **Quick wins** (high value, low effort) → Do first
2. **Strategic investments** (high value, high effort) → Plan for next cycle
3. **Fill-ins** (low value, low effort) → Do when convenient
4. **Avoid** (low value, high effort) → Don't bother unless blocking

### 5. Roadmap — Generate Actionable Plan

Output a phased roadmap:

**Phase 1 — Quick Wins (1-2 sprints)**
List specific files and changes with estimated effort.

**Phase 2 — Strategic Refactors (1-2 months)**
Larger changes grouped by theme (e.g., "Extract service layer", "Add missing test coverage").

**Phase 3 — Long-term Modernization (quarter+)**
Architectural changes, major dependency updates, platform migrations.

## Output Format

Present findings as a structured report with:
1. Executive summary (1 paragraph)
2. Debt inventory table (sortable by severity × spread)
3. Fowler Quadrant classification
4. Prioritized roadmap with phases
5. Metrics dashboard (TDR, debt count by category, trend)

When the `visual-explainer` skill is available, generate the report as an HTML page for better readability.
