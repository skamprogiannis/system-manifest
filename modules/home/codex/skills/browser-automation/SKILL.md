---
name: browser-automation
description: Control a Chrome browser for testing, scraping, form filling, and web interaction using PinchTab. Use when the user needs to navigate websites, test web UIs, extract page content, fill forms, click elements, or automate any browser-based workflow. Preferred over Playwright for token efficiency.
---

# Browser Automation (PinchTab)

Control Chrome for testing, data extraction, and web interaction. PinchTab uses accessibility-tree element references, which stay far cheaper than screenshot-heavy workflows.

## Quick Reference

### Server Management

```bash
# Start the full PinchTab server in the background and return pid/url/token JSON
pinchtab server --background

# Start the server with a visible browser for debugging
pinchtab server --headed

# Use a non-default server URL for subsequent commands
pinchtab --server http://127.0.0.1:9870 nav https://example.com
```

### Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `pinchtab nav <url> --print-tab-id --snap` | Navigate and capture a tab ID plus interactive snapshot | `tab=$(pinchtab nav https://example.com --print-tab-id)` |
| `pinchtab snap --tab <id>` | Get interactive page structure | `pinchtab snap --tab "$tab"` |
| `pinchtab text --tab <id>` | Extract page text | `pinchtab text --tab "$tab"` |
| `pinchtab click <ref> --tab <id> --snap` | Click element by ref and refresh refs | `pinchtab click e5 --tab "$tab" --snap` |
| `pinchtab fill <ref> <text> --tab <id>` | Fill input directly | `pinchtab fill e3 "hello" --tab "$tab"` |
| `pinchtab press <ref> <key> --tab <id>` | Focus a ref and press a key | `pinchtab press e7 Enter --tab "$tab"` |

### Workflow Pattern

1. **Start server**: `pinchtab server --background`
2. **Navigate**: `tab=$(pinchtab nav https://target-site.com --print-tab-id)`
3. **Snapshot**: `pinchtab snap --tab "$tab"` to see interactive refs
4. **Act**: `pinchtab click e5 --tab "$tab"` / `pinchtab fill e3 "data" --tab "$tab"`
5. **Verify**: `pinchtab text --tab "$tab"` or use `--snap` after actions

### Multi-Instance Workflows

```bash
# List tabs and instances managed by the server
pinchtab tab --json
pinchtab instances

# Navigate independent tabs and pass --tab explicitly afterwards
alice=$(pinchtab nav https://example.com --new-tab --print-tab-id)
bob=$(pinchtab nav https://example.org --new-tab --print-tab-id)
pinchtab text --tab "$alice"
pinchtab text --tab "$bob"
```

### Persistent Sessions (Profiles)

Profiles persist cookies, localStorage, and history across restarts. Log in once, stay logged in:

```bash
# First run - log in manually with a headed server
pinchtab server --headed
tab=$(pinchtab nav https://github.com/login --print-tab-id)
# ... interact to log in ...

# Later runs - session is preserved by the configured profile directory
pinchtab server --background
pinchtab nav https://github.com --snap
```

### Security — IDPI (Indirect Prompt Injection Defense)

When browsing untrusted pages, enable IDPI in `~/.config/pinchtab/config.json`:

```json
{
  "security": {
    "idpi": {
      "enabled": true,
      "allowedDomains": ["github.com", "*.github.com"],
      "scanContent": true,
      "wrapContent": true
    }
  }
}
```

- `allowedDomains`: Whitelist trusted domains
- `scanContent`: Detect injection phrases in page text
- `wrapContent`: Wrap output in `<untrusted_web_content>` delimiters
- `strictMode`: Block (HTTP 403) instead of warn

### Token Efficiency Comparison

| Tool | Tokens/Page | Startup | Binary Size |
|------|------------|---------|-------------|
| PinchTab | ~800 | <100ms | 12MB |
| Playwright CLI | ~1,000 | ~1s | ~250MB |
| Playwright MCP | 4,500-15,000 | ~1.2s | ~250MB |

### Tips

- Always keep and reuse the tab ID returned by `pinchtab nav --print-tab-id`
- `pinchtab snap` is interactive and compact by default; use `--full` only when needed
- Use `pinchtab text` for content extraction — it's the most token-efficient way to read a page
- Element refs (e5, e12) are stable across snapshots of the same page state
- Use `pinchtab server --headed` during development to see what's happening
- For forms: `fill` sets the value, then `press <submit-ref> Enter` to submit
