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

## Advisory choice-audit trial

`codex-auto` defaults to native model selection with advisory choice audits. A new
`native-choice-audit-v1` trial permits **20 automatic attempts total**, shared
across main sessions and independent named agents. It preserves the completed
`native-routing-v1` counter and records; old "keep" results are not endorsements.
General local limits remain 500 calls per UTC day and no per-session cap. These
are local policy, not Cloudflare quota. Explicit evaluations remain available
after the trial ends; there is no automatic promotion to apply mode.

The selected model/effort is sent as allowlisted enum metadata, together with
role, scope, booleans and size buckets. The judgment distinguishes **appropriate**,
**cheaper choice likely sufficient**, **stronger choice warranted**, and
**insufficient context**. Alternative judgments identify one of the four supported
catalog pairs. Uncertainty is not agreement. Even a confident judgment from coarse
signals is advice, not a capability guarantee or proof of usage savings.

Main-session checks use the existing `UserPromptSubmit` hook's active model.
The documented native hook does not expose effort; it remains **unknown** unless
an explicit effort field is supplied. No configuration default, transcript, or
saved prior turn is used to guess it. Unknown effort permits a **model-only**
judgment, never an effort endorsement or same-model effort recommendation. Unknown models
are skipped without a provider request.

Main sampling runs on the first nonempty prompt, a changed known selection, or
a substantial new task. Substantial means an actionable prompt with substantial
task signals or a long size bucket; this heuristic cannot reconstruct conversation
history. A five-minute per-session cooldown applies, including model changes.
A selection suppressed during cooldown can be checked on a later eligible turn.
Repeated turn IDs and recent substantial-task fingerprints are suppressed under
the local session lock. Fingerprints are local hashes; raw prompts are not saved
or uploaded. History windows are bounded to 32 entries. Resuming a session does
not reset its sampling state.

Independent agent checks observe explicit selected pairs without rewriting them;
inherited/forked/inlined context is still skipped. Replayed assignments are deduped.
Missing/stale catalogs consume no sample. Failed provider attempts and locally
budget-blocked attempts consume one sample to avoid retry storms. After 20 attempts
sampling stops quietly. Main checks run in shadow mode; explicit advanced apply
mode retains its existing guarded routing behavior.

Every returned judgment is logged, including below-display-threshold opinions.
Only judgments meeting the 70% probability and 10-point margin guard are surfaced
as concise hook advice. The guard controls display, never model settings.
Logs include selected pair, scope, model-only/pair assessment, alternative, probability,
sampling reason and whether advice was displayed. An agent's requested pair does
not prove it started or executed that model.

Automatic skill/workflow, escalation and completion provider requests remain
disabled. Local turn resets, delegation guards and failure counters remain.
Raw prompts, source, output, paths, credentials and transcripts never enter an
automatic request. Native Codex auto-review and the sandbox are unchanged.

Native hook fields: [official Codex hooks documentation](https://learn.chatgpt.com/docs/hooks#common-input-fields).

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
attempts, main/agent scope counts, separate judgment categories, the latest decision
ID, preserved historical routing counts, and general usage. Unknown
outcomes remain unknown; repeated outcome updates use the latest record.
The outcome command accepts new choice-audit judgments, including those below
the display guard, and historical selected/abstained routing decisions. Outcomes are reviewed annotations, not automatic
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
