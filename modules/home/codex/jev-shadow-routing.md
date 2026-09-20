
## Explicit shadow routing pilot

This installed MCP is **explicit-only**: use it only when the user asks for
Jev or the Jev pilot. It must not silently alter normal
Codex behavior. The active Codex model remains `gpt-5.6-terra` with its
configured reasoning effort.

For a shadow-routing recommendation, send Jev only a compact, sanitized state:
task category, stakes, available context, tool requirements, and a short
summary with credentials, personal data, raw prompts, and proprietary content
removed. Ask for a proposed model tier and effort plus confidence. Treat the
answer as advice: do not automatically switch models, approve an action, or
expand authorization.

After a recommendation, record only metadata with `jev-shadow-route`:

```bash
jev-shadow-route \
  --task-kind research \
  --proposed-tier reasoning \
  --effort high \
  --probability 0.82 \
  --latency-ms 180 \
  --usage-tokens 120
```

The helper appends JSON Lines to `~/.local/state/codex-jev/shadow.jsonl`. It
intentionally rejects prompt, response, credential, and free-text fields. Use
one hundred reviewed recommendations before considering any routing promotion.

The wrapper obtains `TYPESAFE_API_KEY` from an already-set environment variable
or the first line of `~/.config/typesafe/api-key`. Keep that file local to this
machine: do not commit it, put it in Nix configuration, or expose it in logs.
