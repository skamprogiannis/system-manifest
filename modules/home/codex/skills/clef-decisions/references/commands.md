# Explicit commands

Inspect local configuration without an inference request:

```bash
codex-clef status
codex-clef catalog
```

After the user authorizes uploading the selected, locally reviewed JSON evidence:

```bash
codex-clef evaluate --contract review --input /tmp/review.json --acknowledge-upload
codex-clef evaluate --contract verify --input /tmp/evidence.json --acknowledge-upload
codex-clef evaluate --contract screen --input /tmp/content.json --acknowledge-upload
codex-clef evaluate --contract escalation --input /tmp/attempts.json --acknowledge-upload
codex-clef evaluate --contract rank --input /tmp/candidates.json --acknowledge-upload
```

Rank input is an object with a `goal` and a `candidates` array of 2 to 32 strings
(up to 1,000 characters each). Returned `c0`, `c1`, etc. refer to those indices.
Other contracts accept a compact JSON value containing only the evidence required.
Text payloads are capped at 24,000 UTF-8 bytes, including the question contract.

After explicit permission to upload the selected image:

```bash
codex-clef vision --image /tmp/screen.png --acknowledge-upload
```

This sends re-encoded pixels without original metadata. Visible personal data can
still be present in pixels. Redact locally before using it. There is no automatic
screenshot capture. The result is loading, login, error, success, or unknown.

A routing record can receive reviewed outcome metadata, without a prompt:

```bash
codex-clef outcome --decision-id ID_FROM_LOG --test-outcome passed --human-agreement agree
```

Use `failed`, `not_run` or `unknown` instead of claiming an unrun test passed. Add
`--escalated` or `--duration-ms 120000` when known. This labels an observation;
it does not establish counterfactual savings against a different model.
