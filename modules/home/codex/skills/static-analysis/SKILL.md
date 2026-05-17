---
name: static-analysis
description: "Run security-focused static analysis workflows from one compact entry point. Use when the user wants a scanner-backed security audit, a CodeQL or Semgrep scan, or help interpreting SARIF findings."
argument-hint: "[target path or SARIF file]"
user-invocable: true
---

# Static Analysis

Use this as the single visible entry point for scanner-backed static analysis.

This skill intentionally keeps `/skills` compact while bundling the upstream Trail of Bits references for:

- `references/codeql/` — deep CodeQL dataflow and taint analysis
- `references/semgrep/` — fast Semgrep security scans
- `references/sarif-parsing/` — reading, filtering, deduplicating, and converting SARIF results
- `references/README.md` — upstream plugin overview

## Choose the right path

- Use **Semgrep** first for the fastest useful security pass, especially when the user wants an initial audit or a quick scan.
- Use **CodeQL** for deeper interprocedural and taint-flow analysis, especially when Semgrep is too shallow or the user explicitly asks for CodeQL.
- Use **SARIF parsing** when the user already has scan output and wants interpretation, aggregation, deduplication, or reporting instead of a fresh scan.

## Tooling expectations

Prefer the locally installed tooling that backs this skill:

- `semgrep`
- `codeql`
- `jq`
- `python3`
- `sarif`

Before running a scan, verify that the required tool is available on `PATH` and say clearly if something is missing.

## Guardrails

- Never silently send telemetry. Every Semgrep run must include `--metrics=off`.
- Do not rerun scanners when the user only asked to interpret existing SARIF output.
- Put generated output in a clearly named directory, or a user-specified output directory, so the results are easy to inspect and clean up.
- Prefer high-signal summaries with file paths, severities, and concrete next steps.
- Start with the smallest effective scan path first, then escalate to deeper analysis if the user wants more coverage.

## How to use the bundled references

When the task becomes detailed, follow the upstream operating guidance in:

- `references/codeql/SKILL.md`
- `references/semgrep/SKILL.md`
- `references/sarif-parsing/SKILL.md`

Treat those files as the detailed runbooks behind this compact entry point.

## Example prompts

- "Use static-analysis to run a Semgrep security scan on this repo."
- "Use static-analysis to run CodeQL on the backend."
- "Use static-analysis to parse this SARIF report and summarize the real issues."
- "Use static-analysis to do a scanner-backed security audit, starting with the fastest useful pass."
