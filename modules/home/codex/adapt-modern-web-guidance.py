"""Adapt the pinned Modern Web Guidance distribution for declarative use."""

from pathlib import Path
import re
import sys

runtime = Path(sys.argv[1])
command = sys.argv[2]
entrypoint = runtime / "modern-web.mjs"
source = entrypoint.read_text()

# Keep the opt-out effective even when Node runs the store entrypoint directly.
startup = "// src/cli/modern-web.ts\nensureNodeVersion();"
assert source.count(startup) == 1
source = source.replace(
    startup,
    '// src/cli/modern-web.ts\n'
    'process.env.DISABLE_TELEMETRY = "1";\n'
    'process.env.ENABLE_FILE_LOGGING = "false";\n'
    'ensureNodeVersion();',
)

# Remove the self-management and policy-writing dispatch branches altogether.
start = source.index('  } else if (command === "install") {')
end = source.index('  } else {\n    console.error(`Unknown command:', start)
source = source[:start] + source[end:]
start = source.index("  set-allow-origin-trials   Opt in")
end = source.index("\n\nOptions:", start)
source = source[:start].rstrip("\n") + source[end:]
source = source.replace(
    '    choose: { type: "boolean" },\n', ""
).replace(
    "  --choose                  Choose specific skills from the repository interactively\n",
    "",
)

# Project opt-ins still apply when reading guidance. Describe the condition
# without prescribing a setter command or a mandatory response footer.
start = source.index("function formatGateMessage(")
end = source.index("async function retrieveUseCase(", start)
source = source[:start] + '''function formatGateMessage({
  guideId, featureIds, optInKey, headingLabel, explicitOptOut
}) {
  const policy = explicitOptOut
    ? "The project explicitly disables this guidance."
    : "This guidance requires project opt-in.";
  return `Guide "${guideId}" covers ${featureIds} (${headingLabel}). ${policy} See the "${optInKey}" setting in .mwgrc.`;
}
''' + source[end:]

# The skill and CLI update together through Nix.
source = source.replace("    maybeEmitUpdateMessage(skillVersion);\n", "")
source = source.replace("  maybeEmitUpdateMessage(skillVersion);\n", "")
start = source.index("function getCLISkillVersion()")
end = source.index("main().catch(", start)
source = source[:start] + source[end:]
source = re.sub(
    r"Ask the developer to run .*? in their own terminal\.",
    "Review the project policy in .mwgrc.",
    source,
)
assert "modern-web-guidance@latest" not in source
entrypoint.write_text(source)

for guide in (runtime / "guides").rglob("*.md"):
    content = guide.read_text()
    content = re.sub(r"\b(?:npx|pnpx)(?: -y)? modern-web-guidance@latest\b", command, content)
    content = re.sub(
        r'If not using a package manager, import from a CDN, e\.g\. `"https://unpkg\.com/[^"]+"`\.',
        "Use the project's pinned dependency or a locally vendored copy.",
        content,
    )
    content = content.replace("https://unpkg.com/interestfor@latest", "interestfor")
    content = content.replace(
        "https://unpkg.com/@oddbird/css-anchor-positioning", "@oddbird/css-anchor-positioning"
    )
    assert "modern-web-guidance@latest" not in content, guide
    assert "https://unpkg.com/" not in content, guide
    guide.write_text(content)
