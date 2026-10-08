# Native Codex model selection and Clef support

Ordinary `codex` uses native settings. `codex-auto -- "task"` enables bounded
delegation and a Clef shadow trial. No scheduler, proxy or additional agent framework
is involved. Native Codex auto-review handles eligible approval requests within
the existing sandbox and permission scope; Clef never decides approvals.

## Starting policy

| Assignment | Model | Effort |
| --- | --- | --- |
| Main coding | gpt-6.1-sol | medium |
| Main Plan mode | gpt-6.1-sol | xhigh |
| Bounded worker, focused explorer/researcher | gpt-6-luna | high |
| Broad implementation, ambiguous investigation | gpt-6.1-sol | medium |
| Architect, plan and security review | gpt-6.1-sol | high |
| Hardest architecture or unresolved failures | gpt-6-astra | low initially |

The lead supplies explicit native model/effort for independent assignments. The
native `[agents]` fallback is Sol/medium. Custom role TOMLs remain unpinned because
role-level model settings take precedence over spawn overrides and would prevent
escalation. Full-history forks inherit parent settings; provide no model override
with `fork_turns="all"`. Preserve needed context instead of forcing independence.
Manual model, effort and speed settings win. Plan mode retains extra-high effort.

Start Nix activation/module wiring and Nix/store/USB contract work on Sol/medium
even when the edit is small: the initial matched trial exposed missed native
contracts on Luna.

Luna returns to the lead after expanded scope, important missing context, or one
failed focused repair. Compare usage per accepted result including repair and
required review. Keep small/sequential tasks in the main session; delegation
ceilings are not targets. Use compact briefs, owned files, acceptance checks and
separate worktrees for concurrent workers. Existing architect checkpoints remain.

## Shadow trial

The default launch does not request main-thread routing. Hooks observe only
independent named agent assignments; inherited/forked/inlined context is skipped.
Explicit native selections are observed without being rewritten. Four useful
pairs from the table (Luna/high, Sol/medium, Sol/high, Astra/low) are intersected
with the authenticated native model catalog, plus a keep option.

The `native-routing-v1` trial permits 20 eligible automatic routing attempts across
sessions. Failed provider attempts count to prevent repeated retries. Missing or
stale catalogs do not consume samples. After the trial completes, hooks stop
sampling quietly and status reports completion. This is a bounded experiment,
not a lifetime Clef allowance: explicit evaluations remain available under the
general local daily limit of 500 calls; there is no per-session cap. These limits
are local policy, not Cloudflare quota. There is no automatic promotion to apply.

Logs record the winning suggested pair even below the apply guard, probability,
margin, keep/guard reason, and requested native pair and selection source.
Requested pairs do not prove an agent started or executed that model. Partial
or unrecognized native choices are marked unknown rather than guessed.
Automatic calls upload fixed categories, booleans and size buckets only. Raw
prompts, source, output, paths, credentials and transcripts never enter them.
Local metadata logs also omit raw content.

Automatic Clef skill/workflow, escalation and completion requests are disabled.
Local turn resets, delegation limits and advisory failure counters remain.
Output text cannot establish test success: pinned Codex 0.161.0 Bash hooks do not
expose an exit status. Required tests and independent review remain mandatory.

## Commands and outcomes

```bash
codex-auto -- "task"
codex-auto status
codex-auto status --json
codex-auto clef catalog
codex-auto --mode apply -- "task"
codex-auto clef outcome --decision-id <32-character-id> --test-outcome passed --human-agreement agree
```

Status is offline and makes no inference or state writes. It reports trial
attempts separately from evaluated assignments and general usage. Unknown
outcomes remain unknown; repeated outcome updates use the latest record.
The outcome command accepts selected and abstained routing decisions, including
shadow advice below the guard. Outcomes are reviewed annotations, not automatic
proof. Review the logged ID and actual check evidence before recording one.

Explicit apply mode retains the 70% probability and 10-point lead guard. It
preserves explicit settings and skips inherited context. Main routing in apply
requires a task prompt or separately approved uploaded brief; bare/resumed
sessions retain native settings. Automatic routing never expands permissions.

Explicit typed operations remain available as `codex-auto clef evaluate` and
`codex-auto clef vision`. Follow the installed `clef-decisions` skill, including
separate upload consent for content or images. Untrusted material stays data.

## Credentials and startup

Store a scoped Cloudflare Workers AI token in the private local file
`~/.config/cloudflare/clef.toml` (mode 0600):

```toml
account_id = "YOUR_CLOUDFLARE_ACCOUNT_ID"
api_token = "YOUR_SCOPED_WORKERS_AI_TOKEN"
```

Credentials stay outside Nix and repositories. Environment credentials are also
supported for explicit operations; launchers remove them from the native process.
Status checks local format only, not live authentication or account-wide quota.
Provider failures fall back to normal native behavior and warn once per category
per session. Catalog refresh uses native app-server model/list, without inference.
Review hooks with `/hooks`; installed custom agent files are regular private files
because native loading uses O_NOFOLLOW.

Assisted interactive launches isolate their hooks from ordinary daemon sessions.
The existing bounded account-routing startup timeout fallback is preserved: it
tries ordinary Codex once with Clef disabled when daemon state can be verified.
Explicit `--no-daemon` retains assisted retries; unrelated failures are not retried.

The shared CLI pin includes the [upstream bootstrap-authentication fix](https://github.com/openai/codex/pull/49432)
released in 0.161.0. It preserves configuration discovery when account ownership
changes while revoking the previous account's content access. The package smoke
check exercises `account/read` without credentials and verifies daemon packaging;
authenticated workspace discovery still requires a check on the deployed desktop.

Local state is under `~/.local/state/codex-clef`. Historical Clef/Jev logs are
preserved. Disable integration with `system_manifest.codex.clef.enable = false`
and rebuild; unrelated hooks and runtime records remain. Configuration changes
require the repository's Codex checks and desktop dry-build before activation.

### Daemon compatibility and version alignment

The native "Background server has incompatible feature settings" dialog reports
a difference between the CLI's effective settings and the shared daemon's. It is
a separate check from the `account/read` workspace-routing timeout. Inspect both
versions without changing the running server:

```bash
codex --version
codex app-server daemon version
```

The daemon uses a separate managed package that can update independently of the
Nix CLI. For example, [0.161.0 enables `api_key_model_discovery` by default](https://github.com/openai/codex/pull/49807),
while 0.160.0 disables it. An older CLI connected to a newer daemon can therefore
show the dialog even without a local feature override.

After deploying a changed Nix CLI pin, let active and queued Codex work finish
and close other clients before aligning the daemon:

```bash
codex app-server daemon update --from-cli
codex app-server daemon version
```

The [native command](https://github.com/openai/codex/blob/rust-v0.161.0/codex-rs/app-server-daemon/src/prepare_install.rs)
asks before copying the installed CLI package and pins that copy against
scheduled production updates. A running daemon restarts after confirmation;
the command does not refuse merely because work is active. Repeat this step
after later Nix CLI upgrades. Plain `daemon update` returns to production
updates, while `daemon restart` keeps the currently selected package.

Package alignment preserves saved daemon feature overrides. If compatible
versions still show the dialog, review local feature settings and the displayed
restart settings before accepting a restart with other clients idle. "Run without
daemon this time" leaves the shared daemon unchanged and can help distinguish
compatibility from an account-routing failure.

## Evidence and cost

The [2026-10-07 matched benchmark](benchmarks/2026-10-07.md) records accepted
results, repairs, native usage, material failures and the five Clef classifications.

The matched five-case Luna/Sol benchmark is an initial calibration, not a universal
capability guarantee. Run cases in isolated historical snapshots with identical
briefs and independent acceptance checks, one repair pass and ten minutes per run.
Record failures/timeouts and native usage, including cached input and output.
Estimated Standard credits are a comparison proxy, not an exact ratio of included
subscription allowance. Observe natural future trial assignments; do not create
paid production work merely to fill the 20 samples.

Native fields and precedence: [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).
Model guidance: [Codex models](https://learn.chatgpt.com/docs/models).
Credit estimates: [Codex pricing](https://learn.chatgpt.com/docs/pricing#token-rates).
