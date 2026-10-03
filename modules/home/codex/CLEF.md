# Clef-assisted Codex

## Scope

The Nix module installs a direct Cloudflare Clef client, native Codex hooks, an
opt-in launcher and bounded custom agents. It replaces the retired Jev MCP and
TypeSafe-specific integration. The default full Clef model is hosted; this does
not run a model on the local GPU or send Codex inference through Cloudflare.
Codex continues to own authentication, tools, permissions and session execution.

The initial main model is selected at launch. Native hooks can select model and
reasoning effort for a named subagent, but do not silently switch the main model
on later TUI messages. A continuous app-server client, generic inference proxy,
local serving and fine-tuning are outside this implementation.

## Setup

After building and activating the configuration through the normal reviewed
NixOS workflow, create the runtime credential file:

```bash
install -d -m 700 "${XDG_CONFIG_HOME:-$HOME/.config}/cloudflare"
umask 077
nvim "${XDG_CONFIG_HOME:-$HOME/.config}/cloudflare/clef.toml"
```

Use this structure with a Workers AI-scoped Cloudflare API token and account ID:

```toml
account_id = "YOUR_32_HEX_CHARACTER_ACCOUNT_ID"
api_token = "YOUR_SCOPED_API_TOKEN"
```

Keep the file owner-only (`chmod 600`), outside repositories and the Nix store.
Do not paste the values into prompts, shell arguments, documentation or logs.
Standalone CLI evaluation also accepts `CLOUDFLARE_ACCOUNT_ID` and
`CLOUDFLARE_API_TOKEN`; the launcher removes these from Codex's child environment,
so native hooks need the runtime credential file. Never give the token broader
Cloudflare administration permissions just for inference.

```bash
codex --version
codex-clef status
codex-clef catalog
codex-auto --mode shadow -- "Trace the wallpaper-to-greeter configuration"
```

`status` is offline. It reports configured-but-not-live-verified credentials,
catalog state, mode, log paths and recorded events. `catalog` obtains the model
picker through an isolated Codex app-server process using the existing Codex
login. It does not request model inference. Missing login or catalog support
causes conservative routing fallback. Read and trust the managed commands through
Codex's `/hooks` interface before relying on hooks. The module does not forge hook
trust or bypass approval settings.

Use `codex-auto -- "task"` to apply valid model/effort choices. Assisted local
interactive launches use native `--no-daemon` execution so hook activation belongs
to that invocation. Plain `codex` keeps hooks inert, regardless of launch order.
`--mode shadow` leaves main/subagent model settings untouched while recording
recommendations; approval behavior is independently controlled
by the installed Nix policy, not the launch-mode flag.

## Routing and roles

The actual catalog supplies supported effort identifiers. Clef chooses a complete
permitted pair, so efforts are dynamic rather than fixed per role. The initial
model allowlist contains GPT-6.1 Sol, GPT-6 Luna and GPT-6 Astra; descriptions are
starting preferences, not measured benchmarks. Unavailable or hidden models are
not candidates. New model IDs require a reviewed allowlist change; newly supported
efforts for allowed models are discovered automatically.

Bare `codex-auto` preserves the normal configured model and effort. Bare resume
commands preserve the resumed session's settings while enabling Clef hooks:

```bash
codex-auto resume
codex-auto resume --last
codex-auto resume SESSION_ID
```

Main routing requires a nonempty task prompt or an explicitly authorized brief.
Resume selectors and option values are not task context. A resume with a new
prompt can route from that prompt; it does not upload the saved conversation.
Catalog discovery may still prime subagent routing on a bare launch. Remote and
noninteractive native commands pass through without local Clef activation or routing.

Explicit `--model`, `--profile`, and model/effort `-c` or `--config` overrides,
including compact `--config=key=value` forms, bypass main routing.
Native agent-spawn arguments with an explicit model or effort, unknown roles, or
forked/inlined context are not rewritten. Native V2 roles route only with explicit
`fork_turns = "none"`; omitted V2 fork settings inherit all history and abstain.
Supported named roles are explorer,
researcher, worker, architect, plan-reviewer and security-reviewer. All except
worker are read-only, and none pins model/effort. The existing plan reviewer
remains interactive; architect supplies a bounded noninteractive critique.

Clef-assisted sessions permit at most four native spawns per user
turn and reject nested spawns observed by their hooks. Unknown/custom tool paths
are not a universal enforcement boundary; these hooks complement, rather than
replace, Codex's sandbox and the user's review. The main agent is instructed to
consult architect for consequential plans, two genuinely failed approaches, or a
substantial final diff. Advice is not a scheduler that forces a review every turn.

Automatic routing sends only locally derived booleans and size buckets. It does
not send raw prompts, task text, code, command output, paths or transcripts. This
privacy tradeoff can cause conservative abstention. For a richer decision, the
user may explicitly authorize a compact reviewed JSON brief:

```bash
codex-auto --brief-file /tmp/reviewed-task.json --acknowledge-upload -- "task"
```

The provided brief goes to Cloudflare. Passing this flag is not authorization to
upload other content. Required tests and protected actions remain unchanged.

## Native approval policy

Default `approvalMode = "shadow"` records recommendations and never approves or
denies for the user. The normal fallback remains `on-request` with reviewer `user`.
Malformed input, missing context/credentials, timeouts, quota exhaustion and
unrecognized actions abstain. This does not invoke Sol or Astra merely to call
Clef. Nor does it replace Codex's built-in auto-review model through a config alias.

The native 0.160.0 permission contract does not expose a trustworthy execution
directory and complete requested permissions. Its `cwd` can be the session
directory even when a command uses another `workdir`, and a network grant can
carry the same Bash command as a shell escalation. Command descriptions do not
establish authorization. Therefore ordinary native requests always remain with
the normal user approval flow, regardless of the classifier's confidence.

A narrow pinned-Git grammar is retained only for advisory triage under configured
session roots. Even `git diff --no-ext-diff --no-textconv` can execute configured
clean filters, so this grammar does not certify a metadata-only operation. Only
fixed categories and the fact that execution context is unverified go to Clef.

`approvalMode = "enforce"` enforces only exact commands in the immutable installed
`denied_commands` list; it never applies classifier allow or deny suggestions.
The default list is empty. `codex-clef status` reports
`automatic_approval_supported: false`. There is no automatic promotion from
shadow examples, probability thresholds or confidence. Agent tasks must not
modify the installed policy or expand permissions.

## Workflow and completion support

Prompt-time decisions prioritize installed skills and checks without waiving
required checks. Local counters detect repeated failure signals and request
context gathering or an architect consultation instead of blind retries.

Codex 0.160.0's Bash PostToolUse response is output text without an exit status.
Failure-like text is therefore recorded only as an advisory signal, never proof
of a failed hypothesis or a passed test. Structured exit codes from tools that
actually supply them are counted separately. No full tool output is uploaded.

Completion is advisory by default. An opt-in `completionMode = "enforce"` permits
at most one verification/review continuation per turn, never an endless stop loop.
Honest disclosures of unrun checks are not blocked. Completion metadata cannot
establish code correctness, and missing hook records do not prove that a test
never ran. Use an independent review and actual test evidence where warranted.

The `clef-decisions` skill documents explicit `review`, `verify`, `screen`, `rank`,
`escalation`, and `vision` commands. Source/evidence/image uploads require the
`--acknowledge-upload` flag backed by specific user consent. Vision accepts one
image, re-encodes pixels without metadata, and never captures a screen itself.
Injection screening remains advice, not a security boundary.

## Logs and evaluation

```bash
codex-clef status
log="${XDG_STATE_HOME:-$HOME/.local/state}/codex-clef/decisions.jsonl"
test ! -f "$log" || tail -n 10 "$log"
```

No log is fabricated during installation or status inspection. First real decision
activity creates private state. The old Jev log, when it exists, is left at
`${XDG_STATE_HOME:-$HOME/.local/state}/codex-jev/shadow.jsonl`; no log may exist if
that explicit-only pilot was never invoked. Bare `$XDG_STATE_HOME/...` is not the
fallback expression when the variable is unset.

Records include a generated decision ID, policy/provider versions, decision and
selected model/effort, winning probability, separate provider confidence, latency,
token counts, fallback reason and whether the integration applied the setting.
`applied` means the setting/decision was assigned, not that later execution or tests
succeeded. Prompts, source, shell arguments, paths and response text are excluded.
Records are private JSONL and appends/counters are locked across processes. The
10 MiB log cap causes safe fallback rather than silently deleting evidence.

```bash
codex-clef outcome --decision-id DECISION_ID --test-outcome passed --human-agreement agree
```

Other labels are failed/not_run/unknown and disagree/unknown. Optional escalated
and duration metadata support evaluating total task effort. Do not infer quality,
calibration or cost savings from unlabeled routing suggestions. Compare outcomes
with the normal baseline and use held-out reviewed tasks before expanding policy.
There is no automatic promotion, learning or calibration from a magic sample count.

Calls are capped at 40 per session/agent and 500 per UTC day; failed requests also
consume the request budget. Text input is capped at 24,000 bytes and images at
4 MiB/16 megapixels. Hook runtime has a six-second application deadline inside
Codex's eight-second hook timeout. Endpoint hostname is fixed, TLS is verified,
redirects are rejected, and transport errors do not expose response bodies or keys.

## Validation and maintenance

```bash
nix build .#checks.x86_64-linux.codex-clef
nix build .#checks.x86_64-linux.codex-skills
nix build .#checks.x86_64-linux.bannerlord-codex
nix build .#checks.x86_64-linux.script-smoke
nixos-rebuild dry-build --flake .#desktop
```

The check uses offline provider fixtures, upstream 0.160.0 hook output schemas,
concurrent state tests, migration tests, real packaged daemon start/copy/stop,
and installed launcher isolation in both modes and daemon startup orders.
It does not certify live Clef routing quality or account-specific model access.
Perform a bounded, non-destructive live smoke test after configuring the runtime
key and trusting hooks. A package upgrade needs refreshed hook contract fixtures
when the native contract changes.

The config migration removes only retired Jev/TypeSafe entries and preserves
unrelated MCP servers, user hook handlers, credentials and historical logs. The
hook merger replaces only its own Nix-store command handlers and is idempotent.
`codex-auto` is never installed as a transparent replacement for `codex`. Assisted
interactive launches stay outside the shared daemon, including shadow mode and
routing fallback; plain `codex` does not inherit their hook activation. No new
system daemon, background monitoring, custom inference proxy or local GPU workload
is installed.

## Primary contracts

- [Codex release](https://github.com/openai/codex/releases/tag/rust-v0.160.0)
- [Permission hook source](https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/hooks/src/events/permission_request.rs)
- [Codex app-server](https://developers.openai.com/codex/app-server/)
- [Cloudflare Clef API](https://developers.cloudflare.com/workers-ai/models/clef/)
- [Clef model card](https://huggingface.co/Cloudflare/clef)
