---
name: modern-web-guidance
description: Consult local web-platform guides when choosing a browser API, native UI primitive, accessibility implementation, or compatibility fallback, or when asked to scan for legacy web patterns.
---

# Modern Web Guidance

Use the project's design system and browser support policy. Use Impeccable for visual design and UX. Consult these guides when a browser implementation decision would benefit from compatibility or platform details.

- Search with a short English phrase for one capability, such as `@cli@ search "light dismiss dialog"`.
- Retrieve relevant results by ID with `@cli@ retrieve "<id>"`. Read the returned file if long output was saved to disk. Consult `@cli@ list` if you need to browse the catalogue.
- Apply the guidance that fits the project's support policy and established components. Use dependencies pinned by the project and bundled or vendored locally.
- For an explicitly requested broad modernization audit, run `@cli@ legacy-scan <path> --json`. Check findings against the source and retrieve relevant guides before proposing changes.
