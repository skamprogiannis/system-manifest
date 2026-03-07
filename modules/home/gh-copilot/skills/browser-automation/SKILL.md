---
name: browser-automation
description: Control a Chrome browser for testing, scraping, form filling, and web interaction using PinchTab. Use when the user needs to navigate websites, test web UIs, extract page content, fill forms, click elements, or automate any browser-based workflow. Preferred over Playwright for token efficiency.
---

# Browser Automation (PinchTab)

Control Chrome programmatically for testing, data extraction, and web interaction. PinchTab uses ~800 tokens/page (5-13x cheaper than screenshot-based approaches) via accessibility-tree-based element references.

## Quick Reference

### Server Management

```bash
# Start PinchTab server (default port 9867)
pinchtab

# Start headless (no visible window)
pinchtab --headless

# Start with specific port
pinchtab --port 9870
```

### Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `pinchtab nav <url>` | Navigate to URL | `pinchtab nav https://example.com` |
| `pinchtab snap` | Get page structure (accessibility tree) | `pinchtab snap -i -c` |
| `pinchtab snap -i` | Interactive elements only | `pinchtab snap -i` |
| `pinchtab text` | Extract page text (~800 tokens) | `pinchtab text` |
| `pinchtab click <ref>` | Click element by ref | `pinchtab click e5` |
| `pinchtab fill <ref> <text>` | Fill input field | `pinchtab fill e3 "hello"` |
| `pinchtab press <ref> <key>` | Press key on element | `pinchtab press e7 Enter` |

### Workflow Pattern

1. **Start server**: `pinchtab` (in a background shell)
2. **Navigate**: `pinchtab nav https://target-site.com`
3. **Snapshot**: `pinchtab snap -i` to see interactive elements with refs (e5, e12, etc.)
4. **Act**: `pinchtab click e5` / `pinchtab fill e3 "data"` / `pinchtab press e7 Enter`
5. **Verify**: `pinchtab text` to extract page content and confirm results

### Multi-Instance Workflows

```bash
# Create isolated instances with separate profiles
pinchtab instances create --profile=alice --port=9868
pinchtab instances create --profile=bob --port=9869

# Each instance has its own cookies, storage, and session
curl http://localhost:9868/text?tabId=X  # Alice
curl http://localhost:9869/text?tabId=Y  # Bob
```

### HTTP API (Advanced)

```bash
# Create instance, get tabId
TAB=$(curl -s -X POST http://localhost:9867/instances \
  -d '{"profile":"work"}' | jq -r '.id')

# Navigate
curl -X POST "http://localhost:9867/instances/$TAB/navigate" \
  -d '{"url":"https://example.com"}'

# Get snapshot (interactive elements only)
curl "http://localhost:9867/instances/$TAB/snapshot?filter=interactive"

# Perform action
curl -X POST "http://localhost:9867/instances/$TAB/action" \
  -d '{"kind":"click","ref":"e5"}'

# Extract text
curl "http://localhost:9867/instances/$TAB/text"
```

### Persistent Sessions (Profiles)

Profiles persist cookies, localStorage, and history across restarts. Log in once, stay logged in:

```bash
# First run — log in manually
pinchtab --headed --profile=github
pinchtab nav https://github.com/login
# ... interact to log in ...

# Later runs — session is preserved
pinchtab --profile=github
pinchtab nav https://github.com  # Already logged in
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

- Always use `pinchtab snap -i` (interactive only) instead of full `snap` to minimize token usage
- Use `pinchtab text` for content extraction — it's the most token-efficient way to read a page
- Element refs (e5, e12) are stable across snapshots of the same page state
- Use `--headed` during development to see what's happening, `--headless` in automation
- For forms: `fill` sets the value, then `press <submit-ref> Enter` to submit
