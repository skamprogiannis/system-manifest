# CI and Validation

The check registry and CI jobs are defined by `checks/registry.nix`, `checks/`, and `.github/workflows/`. See the [README](../README.md) for the shortest rebuild path.

## Flake check (all host builds)

```bash
nix flake check
```

In this repo, `nix flake check` runs every host and support check defined in `checks/registry.nix`. GitHub Actions evaluates all three hosts and selects regression checks from the changed paths. Lightweight checks consume specific generated scripts, configuration files, and packages; selected support checks share one runner and Nix store. Host-specific changes build that host, shared runtime/package changes build all hosts, and documentation changes avoid system builds. Unknown paths or unavailable comparison commits select comprehensive validation.

Full host jobs are serialized and reuse their built packages for installed-environment checks, including activation ordering and Steam registration. The speech check validates packaging when enabled; with Bannerlord speech disabled, it verifies its absence and checks the independently configured CPU-only desktop dictation. A weekly Sunday run at 01:17 UTC and the **Validate** workflow's manual trigger cover the complete registry. Superseded push/PR runs are cancelled; main pushes compare against the last successful ancestor run so changes from interrupted runs remain covered. The final result rejects failed, cancelled, or unexpectedly skipped selected jobs. Cache keys include dependency and source revisions; PRs restore caches and only main writes them. Cache retention is opportunistic: the 5 GiB garbage-collection target can discard intermediate builds, so hosted measurements determine whether further tuning is useful.

The default desktop check builds the CUDA-light `desktop-ci` output. Run the separate manual **Validate Full Desktop** workflow to validate the production Ollama CUDA closure. CI timings, fetch sizes, and cache retention must be measured on hosted runners; a successful configuration check does not prove hardware behavior. CI does not deploy; activate with `nixos-rebuild switch --flake .#desktop`, `nixos-rebuild switch --flake .#laptop`, or `update-usb` when requested or already authorized.

For shared-contract refactors, select checks based on affected hosts and risk; broad or uncertain changes warrant `nix flake check` and a desktop build or dry-build. Runtime wallpaper/DMS ownership changes still need a manual wallpaper-switch smoke test, and USB-only session changes still require `update-usb` plus a real boot on target hardware.

## Maintainer rules

- `checks/registry.nix` owns exported checks and CI lane/ownership metadata. Keep selector/result regression fixtures and coverage aligned with changes to this registry.
- GitHub Actions evaluates all three hosts, conservatively selects checks by changed paths, shares lightweight support-check builds, and serializes affected host integration builds.
- Installed-environment checks must exercise actual assembled activation/install artifacts; lightweight checks should use precise generated outputs instead of entire Home Manager environments.
- Register new shell sources in `checks/context.nix` so ShellCheck covers generated Home Manager entrypoints, variants, and standalone fixtures.
- CI builds and `nix flake check` do **not** prove target hardware behavior. Validate wallpaper/greeter changes on the desktop and USB changes with a real update and boot.
