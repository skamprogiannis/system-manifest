# Native Codex workflow

Ordinary `codex` uses native settings and delegates only when explicitly requested.
`codex-auto -- "task"` opts into bounded delegation with the same native model,
effort, speed, sandbox and approval settings. There is no routing service, model
catalog, classifier or background model-choice audit. Native Codex auto-review
handles eligible approval requests within the existing permission scope.

## Starting policy

| Assignment | Model | Effort |
| --- | --- | --- |
| Narrow, clear implementation or focused lookup with straightforward verification | gpt-6-luna | high |
| Routine implementation with an established approach | gpt-6.1-sol | medium |
| Ambiguous implementation, difficult debugging, substantial review | gpt-6.1-sol | high |
| Consequential architecture and demanding planning | gpt-6.1-sol | xhigh |
| Hardest problems requiring broader analysis | gpt-6-astra | xhigh |

These are provisional starting choices, not benchmark-proven optima. Main coding
and the independent-agent fallback remain Sol/medium; main Plan mode uses xhigh.
The lead selects explicit native model/effort for independent assignments. Manual
choices win. Role TOMLs remain unpinned because their settings override spawn
choices. Full-history forks inherit parent settings; supply no model or effort
override with `fork_turns="all"`. Instructions never change an active selection.

Use at least Sol for Nix activation/module wiring and Nix/store/USB contracts.
Choose stronger settings upfront for clearly difficult work. If Luna's scope
expands, context is missing or a focused repair fails, return evidence to the lead
for a Sol assignment. Astra/xhigh still requires normal validation and review.

Keep small or sequential work in the main session. For substantial independent
work, use at most two task agents plus one focused reviewer; these are ceilings,
not targets. Use compact briefs, disjoint files and separate worktrees for
concurrent writers. Architect checkpoints remain: consequential architecture,
two genuinely failed approaches, and a substantial final diff. Reuse reviewers
for follow-up instead of restarting the same review.

## Commands and local hooks

```bash
codex-auto -- "task"
codex-auto resume --last
codex-auto -- --model gpt-6-astra -c 'model_reasoning_effort="xhigh"' "task"
codex-auto status
codex-auto status --json
```

Status is offline and writes no state. It describes workflow ownership and the
launcher's environment, not the active selection, installed hook health or
account usage. Use native Codex controls for those settings and `/hooks` to inspect
loaded hooks. Use `codex-auto -- --help` for native help. The first `--` escapes
wrapper commands, so `codex-auto -- status` starts a task literally named status.

Only two local hooks remain. `SessionStart` enables the assisted workflow in
context. `PreToolUse` counts up to four spawn calls per turn and denies nested
delegation. It does not rewrite model/effort or grant approvals. The guard stores
at most four hashed call IDs under `~/.local/state/codex-auto`, keyed by session
and turn. Replayed hooks do not consume another slot. Missing identifiers or
unreadable state deny delegation while work can continue in the main session.
No prompts, source, tool output or transcripts are stored by these hooks.

Assisted interactive launches use `--no-daemon` to isolate their hook environment
from ordinary daemon sessions. Noninteractive commands and remote connections
pass through to native Codex without enabling local delegation. The existing
account-routing timeout recovery remains: an assisted launch can try ordinary
Codex once when the daemon environment is verifiably unassisted. Explicit
`--no-daemon` keeps bounded assisted retries. Other errors are not retried.

Disable the launcher and remove its owned hooks with
`system_manifest.codex.auto.enable = false` and rebuild. Hook migration preserves
unrelated user handlers. Native role files remain private regular files because
the native loader refuses final-component symlinks.

## Learning from ordinary work

Use the required integration review and acceptance checks to identify material
misses, repeated repairs and escalations. Adjust recurring assignment choices
from that evidence. Avoid continuous transcript inspection, monitoring agents,
extra judge calls and duplicate work solely for measurement.

If a specific choice remains uncertain, run an explicitly requested, bounded
matched comparison on representative completed tasks with identical starting
snapshots and acceptance checks. Compare accepted-result usage including repair
and review; keep speed fixed and run sequentially to limit RAM. Natural outcomes
can reveal problems but cannot prove counterfactual savings.

The [2026-10-07 benchmark](benchmarks/2026-10-07.md) compared Luna/high and
Sol/medium on five bounded tasks, once each. Sol was accepted on all five; Luna
on the two Go tasks. Timeouts were partly infrastructure-confounded. It did not
compare Sol reasoning levels or test Astra, and shared review costs were not
allocated to candidates. It supports narrow assignment choices, not a universal
quality or subscription-usage claim.

## Retired Clef experiment

The selected-choice trial ran October 13–14 and produced 20 insufficient-context
judgments, with no applied model changes or demonstrated savings. Clef routing,
provider commands, catalogs, trial counters and the explicit evaluation skill
were retired on October 16. Old `clef` commands and wrapper routing flags now
return a retirement message. Historical records under
`~/.local/state/codex-clef` and private credentials under
`~/.config/cloudflare/clef.toml` are left untouched; the new workflow reads neither.
The implementation remains in Git history. Activation removes only owned legacy
hooks. Restart clients after rebuilding so new instructions and hooks are loaded.

## Startup and package maintenance

The shared CLI pin includes the upstream bootstrap-authentication fix released in
0.161.0. Package checks exercise `account/read` without credentials and managed
daemon packaging; authenticated workspace discovery still requires a deployed
check. Configuration changes require the Codex checks and desktop dry-build.

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

### Projectless chat files

Home Manager sets `desktop.projectlessWorkspaceRoot` to `~/documents/Codex`.
This is the desktop app's **Settings → General → Projectless chat folder**
preference; the upstream default uses `~/Documents/Codex` independently of XDG
user directories. Existing chats retain their workspace paths, so changing the
default alone does not relocate old chats.

### Voice on NixOS

Home Manager enables `/voice` through `features.realtime_conversation` and sets
`realtime.voice = "vale"` in the writable Codex configuration. Vale and the
alternative Sol are supported by the [pinned CLI's voice configuration](https://github.com/openai/codex/blob/rust-v0.164.0/codex-rs/core/config.schema.json).
This chooses the speaking voice; the main coding model remains independently
configurable. Audio device preferences continue to follow the local setup.

The upstream Linux voice helper embeds ALSA and expects `/usr/share/alsa` plus
conventional distribution plugin paths. Its parent filters ALSA environment
variables, so exporting them in a terminal does not repair native voice startup.
The Nix package adapts the physical helper entrypoint with an ALSA configuration
that uses native PipeWire plugins and avoids NixOS's multilib `libs` fields, which
the embedded ALSA cannot read. System and personal ALSA configuration hooks remain.
This adaptation is included when the native daemon copies the Nix CLI package;
align that package after deployment using the idle-session procedure above.

Package checks enumerate devices through the copied helper without opening audio
streams. A live `/voice` conversation still requires desktop acceptance. Check
the PipeWire defaults and output volume if devices open but audio is inaudible.

## Native references

- [Subagents and model selection](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Hook contracts](https://learn.chatgpt.com/docs/hooks)
- [Model guidance](https://learn.chatgpt.com/docs/models)
