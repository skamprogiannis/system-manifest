# System and Desktop Reference

Detailed desktop features, dependencies, and user-facing commands. For the quick-start, see the [README](../README.md).

### Local AI Web Search (desktop)

The desktop's Ollama model inventory is declared in `hosts/desktop/default.nix`: `huihui_ai/qwen3.5-abliterated:9b` (primary, tool-capable research and vision) and `huihui_ai/qwen2.5-abliterate:7b` (lighter non-thinking alternative). `services.ollama.syncModels = true` makes this authoritative: on model-loader runs, **all undeclared Ollama models are removed**, including those downloaded manually, and the declared models are pulled. This removes the earlier Gemma 3, Qwen2.5 3B, Qwen3 8B, and Qwen3-Coder 30B models. Downloads require network access and may continue after a rebuild. The existing server-wide 65K context setting is unchanged; use a smaller per-model context in Open WebUI when VRAM is constrained.

**SearXNG starts automatically at boot** and works independently at `http://127.0.0.1:8888`, without LLM inference. Open WebUI stays off until you select **Open WebUI** in the DMS launcher. This starts its server, waits for a response, and opens a standalone Brave app window. Closing the window does not stop the server. A narrowly scoped Polkit rule allows the active desktop user to manage only these two services without a terminal authentication prompt.

After `sudo nixos-rebuild switch --flake .#desktop`, the controls are:

```bash
ai-search launch       # Start Open WebUI and open its app window
ai-search start        # Start only Open WebUI
ai-search stop         # Stop only Open WebUI
ai-search status       # Show Open WebUI status
searxngctl start       # Start only SearXNG (normally starts at boot)
searxngctl stop        # Stop only SearXNG
searxngctl status      # Show SearXNG status
```

Open WebUI listens at `http://127.0.0.1:8080`. Create an administrator account on first launch and enable Web Search in the chat as needed. SearXNG supports JSON results at `http://127.0.0.1:8888/search?q=nixos&format=json`. Both bind to localhost and keep firewall ports closed.

The SearXNG secret persists at `/var/lib/searx-local/secret.env` outside the Nix store. Diagnose issues with `systemctl status open-webui searx searx-init` and `journalctl -u open-webui -u searx`. Open WebUI's saved admin settings can override its environment defaults.

## Flake Inputs

Hyprland, its portal, and stable Ghostty use system Nixpkgs packages. Ghostty shares the desktop graphics package set and uses the NixOS binary cache, avoiding development builds that exceed local RAM. Treesitter uses the editor Nixpkgs package and its matching grammars. These inputs remain independently tracked for configuration modules, upstream features, or release-matched resources:

| Input | Source | Why |
|-------|--------|-----|
| `catppuccin` | `github:catppuccin/nix` | Shared static Mocha palette for supported Home Manager applications |
| `home-manager` | `github:nix-community/home-manager` | Tracks nixpkgs-unstable |
| `neovim-nixpkgs` | `github:nixos/nixpkgs/nixos-unstable` | Editor and plugin packages can be refreshed independently of desktop packages |
| `nixvim` | `github:nix-community/nixvim` | Full Neovim config in Nix |
| `spicetify-nix` | `github:Gerg-L/spicetify-nix` | Declarative Spicetify wrapper for the themed Spotify GUI |
| `skwd-wall` | `github:liixini/skwd-wall/nix` | skwd-wall v2 wallpaper selector/engine, daemon, and semantic model suite |
| `visual-explainer` | `github:nicobailon/visual-explainer` | HTML visualization generator for architecture diagrams and code explanations |
| `impeccable` | `github:pbakaus/impeccable` (pinned revision) | Frontend design skill bundle kept with its pinned 0.1.17 engine for offline typography, color, layout, and motion tools |
| `mattpocock-skills` | `github:mattpocock/skills` | Engineering skills used here for diagnosis, grilling, domain and module design, review, TDD, and prototyping |
| `trailofbits-skills` | `github:trailofbits/skills` | Security and analysis skill marketplace used here as the upstream source for the compact `static-analysis` skill |
| `pinchtab-src` | `github:pinchtab/pinchtab` | Release-matched PinchTab skill and safety references for browser automation |
| `dux-files` | `github:duxlabs-dev/dux-files/v2.0.0` | Stable graphical file manager and on-demand file chooser portal; Nixpkgs follows the root input, while its release QML dependency remains pinned independently |
| `dms` | `github:AvengeMedia/DankMaterialShell` | Fast-moving shell UI |

## Workflow & UI

- **Glassmorphism Aesthetics:** Vesktop is the visual reference for glass surfaces: transparent enough to carry wallpaper context, but dark enough to keep text readable. The shared glass contract lives in `modules/home/glass.nix` and is documented in `DESIGN.md`. Ghostty uses native RGBA transparency with `background-opacity = 0.40`, applies it to colored cells, and keeps compositor opacity at `1.0` so text remains fully opaque. Hyprland uses a restrained native blur profile for Ghostty, Vesktop, DMS layers, and Hazy/Spicetify surfaces instead of heavy global blur.
- **Theming:** `modules/home/catppuccin.nix` centralizes the static Mocha palette for Brave, Bat, Ghostty, Nixvim, and GTK 3. skwd-wall v2 owns wallpaper-derived colours. DMS consumes its palette and application templates render from those supplied colours. Vesktop regenerates Translucence/QuickCSS from DMS `dms-colors.json`, and Hyprland updates window/group borders through a targeted Lua `hl.config(...)` evaluation.
- **Wallpaper Integration:** `Super+W` opens skwd-wall v2, backed by the `skwd-walld` user service. Existing v1 Steam library settings and private credentials seed missing v2 fields while preserving user preferences; SteamCMD supports Workshop downloads. The `wallpaper-sync` service follows successful applications, synchronizes DMS session state, and saves a matching wallpaper/palette snapshot for the greeter. Temporary picker previews affect desktop colours; the greeter follows the last applied snapshot. With different wallpapers across monitors, the latest applied wallpaper determines shared colours and the greeter image. Use `wallpaper-sync status --json` to inspect synchronization and pending errors.
- **Terminal sessions:** Ghostty opens ordinary shells; Hyprland windows and groups handle everyday layout. Optional tmux provides detachable sessions without automatic startup or plugins. Run `tmux new -As work` to create or attach to `work`, then press `Ctrl+B`, release it, and press `D` to detach. Run the same command to reconnect. Sessions survive terminal closure, not a reboot.
- **Keyboard Layout:** `us altgr-intl` + `gr simple`. `Super+Space` toggles layouts, and IBus is started with the Hyprland session for Greek dead-key composition.
- **Window Controls:** Super-based Hyprland keybindings cover moving, resizing, grouped-window tabs, monitor focus, and monitor-to-monitor window moves.
- **Hard Quit:** `Super+Shift+X` force-terminates the active app process for clients like Vesktop or ProtonVPN that minimize to tray on normal close.
- **File manager:** `Super+E` runs `dfiles show`, opening Dux Files or reusing its running window. Folder links (`xdg-open`) use its upstream `dev.duxlabs.files.desktop` entry. Yazi remains available in the terminal as `yazi` or the `y` shell wrapper.
- **File dialogs:** The Hyprland portal routes FileChooser requests to Dux Files, with GTK as fallback. Portal-aware apps, including Brave, use its open/save dialogs. Settings stays on GTK, and screen sharing/screenshots stay on the Hyprland backend. D-Bus starts Dux Files on demand; there is no always-running file-manager service.
- **File manager appearance:** Dux Files follows the DMS wallpaper palette. Its file-manager and chooser surfaces use the shared glass values through a bounded QML package patch; compositor opacity stays at full strength so text and icons remain opaque. In-app preferences remain writable.
- **Launcher Shortcuts:** Common launch actions cover Dux Files, wallpapers, screenshots, and the DMS notepad.
- **DMS Shell:** Core shell layout, widget placement, and launcher behavior are managed declaratively in Nix. `Super+C` toggles the control panel, with a pinned widget grid for volume, network, root-disk usage, audio devices, power profile, quick toggles, and running apps.
- **Screenshots:** Region/window/full keybinds use `dms screenshot` to save under `~/pictures/screenshots` and copy the image to the clipboard. `screenshot-path-copy` copies the file path instead (useful for sharing with AI agents).
- **Screen Recording:** GPU Screen Recorder's GTK UI handles capture setup, backed by GPU Screen Recorder. `gsr-record stop` is kept as an emergency stop helper for finalizing active clips under `~/videos/screencasts`.
- **Codex GUI:** Desktop installs the official Linux ChatGPT desktop preview with Codex. Open **ChatGPT** from the DMS launcher or run `chatgpt`. The package preserves the upstream desktop entry, icon, URI handlers, and bundled Codex resources; its version and download hash are pinned separately from the CLI. The launcher provides `/usr/bin/env` and `/usr/bin/ldd` only inside a private mount namespace, preserving device access and nested Codex sandboxing. This avoids a native Electron diagnostic-report crash when the Git watcher detects libc on NixOS. NixOS is outside the officially supported distributions. The app uses XWayland by default; native Wayland is experimental (`chatgpt --ozone-platform=wayland`).
- **Codex CLI:** Codex is integrated into the Neovim + terminal workflow with repository-specific instructions, `/goal` enabled, declarative skills, Linear/Context7/Etsy/OpenAI Docs MCP servers, custom agents, BEL-based terminal urgency. Codex runs directly in Ghostty or an explicitly started tmux session. Codex and the optional Bannerlord adapter share one version pin; upgrade checks cover daemon startup and adapter preflight. `codex-auto` opts into bounded native delegation with task-specific model/effort choices; ordinary `codex` remains explicit-delegation-only. See the [Codex workflow](../modules/home/codex/WORKFLOW.md).
  The launcher defaults to the system CA bundle through `CODEX_CA_CERTIFICATE`, selecting Codex's Rustls HTTP client as a startup workaround. Explicit `CODEX_CA_CERTIFICATE` or `SSL_CERT_FILE` values take precedence. Missing optional Nix profile directories are removed from Codex’s terminal search list so Doctor can assess the installed capabilities; custom paths remain visible to diagnostics. Ordinary interactive startup retries the exact account-routing bootstrap timeout up to twice, including with `--no-daemon`; other errors and commands pass through. This mitigates intermittent connectivity failures without establishing that the network path is fixed. After applying this change, restart an existing Codex daemon when its sessions are idle so it inherits the new environment.
- **Browser Automation:** PinchTab is installed declaratively so the browser-automation skill has the CLI it documents.
- **Static Analysis:** CodeQL, Semgrep, and SARIF tooling are installed declaratively to back the compact `static-analysis` skill.
- **DNS:** Quad9 (`9.9.9.9`) for privacy-focused DNS resolution.
- **XDG directories:** Lowercase paths such as `~/downloads`, `~/pictures`, and `~/wallpapers` are canonical. Legacy uppercase XDG folders are migrated into the lowercase layout when it is safe to do so, and Yazi assigns the expected special-folder icons to those lowercase names.

## Custom Scripts

| Script | Description |
|--------|-------------|
| `screenshot-path-copy` | Wraps `dms screenshot` to copy the saved file path to clipboard (instead of image) |
| `hypr-quit-active` | Force-quits the active app process when a client minimizes to tray instead of exiting |
| `gsr-record` | Emergency stop helper for active GPU Screen Recorder captures; `stop` finalizes recordings and clears stale runtime state |
| `ai-search` | Starts, stops, reports the status of, and launches the Open WebUI desktop app |
| `searxngctl` | Independently controls the always-on SearXNG service |
| `torrent` | Manages the local Transmission daemon with readable `gui`, `list`, `add`, `start`, `stop`, `remove`, and guarded `delete --yes` commands |
| `transmission-port-sync` | Syncs Transmission's configured peer port (for example after a VPN-forwarded port change) |
| `codex-auto` | Native assisted Codex launch and offline workflow information with `status` |
| `codex-state-sync` | Safely merges active Codex sessions between desktop and USB (`to-usb` / `from-usb`) while leaving machine-local state alone |
| `nixos-usb-host-scratch-status` | Shows encrypted host-scratch mounts plus the last checkpoint/shutdown sync result |
| `specify` | Spec Kit CLI wrapper — scaffolds spec-driven development for new projects |
| `setup-persistent-usb` | Initialises a fresh LUKS-encrypted persistent NixOS USB drive |
| `steam-host-scratch` | Reports host-auto Steam paths and checkpoints account/config/userdata state |
| `usb-host-scratch` | Opens the temporary repositories path, checkpoints persistent app state, or shows host-scratch status |
| `update-usb` | Updates the USB image using prebuild mode by default, with `--in-place` as a lower-disk-space fallback |

## Desktop maintenance

### NVIDIA compositor scheduling

The desktop sets `HYPRLAND_NO_RT=1` for login sessions and the greetd service, so both the user and greeter compositors use normal scheduling. Hyprland 0.57.1 can otherwise exceed rtkit's 200 ms real-time CPU limit during NVIDIA display-connector queries and receive a kernel `SIGKILL`, followed by a restart into recovery configuration. Normal scheduling avoids that fatal limit; a slow driver operation can still cause a temporary stall. Idle, monitor power-off, locking, and suspend settings remain enabled.

After rebuilding, a fresh login or reboot applies the environment setting. Verify the user compositor with `chrt -p "$(pgrep -u "$USER" -x '.Hyprland-wrapp')"`; its policy should be `SCHED_OTHER` (possibly with `SCHED_RESET_ON_FORK`) at priority `0`. Idle/wake testing on the physical desktop is still required after activation.

### Crashed lockscreen recovery

Hyprland allows a replacement locker to restore a crashed session lock on every host. The session stays locked while DMS restarts; recovery does not automatically unlock it. USB does not restart DMS in response to an event-socket log message, because restarting the shell also kills its active locker.

If Hyprland shows a crashed-lockscreen screen, switch to a TTY with `Ctrl+Alt+F3` and authenticate as the desktop user. Run `hyprctl instances`, identify the affected session, and export its instance signature. On an older USB generation, first stop the legacy watchdog with `systemctl --user stop dms-hyprland-event-watchdog.service`.

```bash
export HYPRLAND_INSTANCE_SIGNATURE='<affected instance signature>'
hyprctl --instance "$HYPRLAND_INSTANCE_SIGNATURE" --quiet eval 'hl.config({ misc = { allow_session_lock_restore = true } })'
systemctl --user restart dms.service
dms ipc call lock lock
```

Wait for DMS IPC to become available before issuing the lock command; retry that command if the shell is still starting. Return to the graphical session and authenticate at the restored lockscreen. The targeted `hl.config(...)` evaluation changes only the running instance; persist the setting through the normal configuration update. Avoid a full configuration reload during recovery, because generated DMS Lua files may contain a separate startup error.

If restoring the locker fails and the authenticated local user deliberately chooses to expose the desktop, the installed Lua API provides this last-resort command from the authenticated TTY:

```bash
hyprctl --instance "$HYPRLAND_INSTANCE_SIGNATURE" --quiet eval 'hl.clear_crashed_lockscreen()'
```

This clears a crashed lockscreen; it must remain a manual recovery action, never a watchdog or automatic unlock policy. Package/configuration checks do not establish successful recovery on actual displays; test a fresh lock and authentication after updating the session.

### Hyprland keybinds

- **Prefer readable key names**: use bindings like `x` or `Return` by default; only fall back to `code:<n>` when Hyprland rejects the named key or layout-independent behavior is truly required.
- **Keyboard layouts**: This repo uses `us altgr-intl` and `gr simple`; `Super+Space` toggles between them.
- **Validation**: After keybind changes, test in both US and Greek layouts.
- **InvalidFormat troubleshooting**: Try a valid Hyprland key name first; use `code:<n>` only if the named key is rejected.
- **Managed config reloads:** The launcher selects the Home Manager symlink through `HYPRLAND_CONFIG`, so reloads follow rebuilt configurations. Explicit `--config` paths are canonicalized by Hyprland at startup and can retain an older Nix store file until the next login.
- **Window cycling:** `Super+Tab` cycles windows on the current workspace, including floating windows; `Super+Shift+Tab` reverses direction. `Super+[` and `Super+]` select the previous and next tabs within a window group. Hold `Super` and drag a window onto an unlocked group’s tab bar to add it; drops on the window body retain normal movement behavior.
- **Scratchpads:** `Super+Minus` toggles the default scratchpad; `Super+Grave` toggles music. Add `Shift` to move the focused window there and follow it, or `Ctrl` to move it without following.

### File manager validation

After activating and starting a fresh Hyprland session, check `Super+E` in both US and Greek layouts, run `xdg-open "$HOME/downloads"`, and open/save a file in Brave. Confirm that reopening Dux Files reuses its window and that screen sharing still uses the Hyprland picker. `xdg-mime query default inode/directory` should report `dev.duxlabs.files.desktop`. The portal is configured declaratively; do not run `dfiles portal install`, which writes competing user portal preferences. Existing app processes may need restarting after the session refresh. These runtime checks are separate from configuration/package checks.

### Vesktop blank-window recovery

A transparent window with no Discord UI can result from outdated Vencord startup patches. Inspect the renderer error before changing graphics or glass settings. Quit Vesktop, back up `~/.config/vesktop/sessionData/vencordFiles`, run `vesktop --repair`, and reopen through the normal launcher. Repair refreshes the downloaded Vencord bundle; it does not require a NixOS rebuild or deleting the login/profile. Verify that Discord renders after repair. A login screen still needs user authentication.

### Desktop integration invariants

- **Terminal attention:** Codex emits BEL on completion and approval requests; Ghostty keeps its bell title until interaction. DMS treats that marker on Ghostty windows as workspace urgency alongside native urgency. This bridges Ghostty's serial-less Wayland activation request, which Hyprland 0.57 rejects. Other applications retain their native urgency behavior.
- **Native Glass Transparency:** Prefer app-native RGBA transparency plus Hyprland native blur. For text-heavy apps such as Ghostty, keep compositor opacity at `1.0 override` so glyphs stay opaque, and tune the app's own background opacity instead.
- **Glass Token Source:** `modules/home/glass.nix` is the source of truth for Ghostty, Vesktop, DMS, Spicetify/Hazy, GTK popovers, and Hyprland glass values. Tune that module first instead of scattering one-off opacity numbers.
- **Hyprland Blur Tuning:** For broad transparent surfaces, avoid excessive vibrancy because it can blend wallpaper colors into pastel blobs. Use the restrained native blur baseline (`size = 3`, `passes = 2`, `contrast = 0.9`) and tune app-side surface opacity/darkness toward the corrected Vesktop glass reference instead of increasing global blur.
- **XWayland Menus:** XWayland applications are excluded from compositor blur because transparent menu padding can produce rectangular halos outside menu borders. Global blur and native Wayland glass surfaces (Ghostty, Vesktop, and DMS) remain enabled. The `xwayland-no-blur` window rule in `modules/home/hyprland.nix` owns this compatibility exception.
- **Systemd buffers:** When managing video surfaces (like `mpvpaper`) on Nvidia/Wayland, use systemd with `RestartSec=2.5` to prevent GPU buffer race conditions that crash the compositor.
- **Cursor Baking:** Always manually symlink modern cursor names (`left_ptr`, `pointer`, `default`, `progress`, `alias`) in custom theme derivations to prevent Adwaita fallbacks in browsers and system bars.
- **Hyprland Syntax:** `windowrulev2` is deprecated; use `windowrule` with `match:class` or `match:title` for all new configuration.
- **Vesktop Glass Model:** Vesktop must stay compositor-opaque (`opacity = "1.0 override"`). Its transparency comes from `transparent = true`, `useQuickCss = true`, Translucence, and Matugen CSS surfaces; do not replace that with compositor opacity.
- **Vesktop Darkness Rule:** The five-point darkness correction applies to Vesktop's pre-removal Translucence CSS surface ramp. Do not apply `+0.05` mechanically to Ghostty, DMS, or unrelated opacity settings; match them visually to the corrected Vesktop target.
- **NIXOS_OZONE_WL Placement:** Must be in `home.sessionVariables` (e.g., in `modules/home/codex/default.nix`), NOT in Hyprland's `env =` block. Hyprland env= only propagates to keybind-launched apps, not DMS/QuickShell spotlight launchers. Session variables propagate to all user processes (D-Bus, systemd) and require log-out/log-in to take effect.
- **Desktop Entry Exec Lines:** Cannot contain complex shell syntax, pipes, redirects, or unquoted special characters. Use `pkgs.writeShellScript` to create a wrapper script and reference it in `exec`. Example: Vesktop uses a wrapper to sync settings and regenerate the Translucence + QuickCSS theme bridge before launch.

- **Launcher app overrides:** `modules/home/dms/launcher-app-overrides.json` owns the complete per-app exception list. Home Manager replaces that map on activation so removed exceptions stay removed; other runtime state is preserved.
- **Wellbeing game titles:** Digital wellbeing reads game titles locally from Steam's configured libraries at shell startup and whenever its panel opens. `modules/home/dms/game-title-aliases.json` supplies explicit display names for ambiguous IDs, including `steam_app_0` as Crowns & Blades. Aliases take precedence over Steam metadata, followed by DMS's desktop-entry fallback. This changes labels, including limit labels and notifications; recorded app IDs, totals, limits, and icons stay intact. Uninstalled or unknown games use the existing fallback name.

## Wallpaper System Architecture

Wallpaper integration is split between the upstream skwd-wall v2 service and DMS session state.

- `services.skwd-deck` is enabled system-wide from the upstream `github:liixini/skwd-wall/nix` module. It installs `skwd-wall-v2` and runs `skwd-walld`; do not reintroduce the retired v1 `skwd-daemon`/Quickshell patch stack.
- `modules/home/wallpaper/default.nix` stays the thin shared entrypoint; `modules/home/wallpaper/skwd-wall-v2.nix` owns the declarative v2 colour contract.
- skwd-wall v2 uses wallpaper-driven Matugen with skwd-wall as colour authority and DMS as a palette target. `skwd-walld` therefore needs `matugen` in its service PATH.
- `wallpaper-sync` subscribes to successful skwd theme applications and synchronizes DMS session state plus a persistent applied snapshot under `~/.local/state/wallpaper-sync/current`. The system `wallpaper-greeter-sync.path` publishes its session, palette, and still together into `/var/lib/dms-greeter`, including changes between logins; previews must never update it. Inspect synchronization with `wallpaper-sync status --json`.
- DMS runs with `DMS_DISABLE_MATUGEN=1`; its enabled application templates are rendered separately from supplied skwd colour roles. Keep `externalSet` state-only so DMS cannot regenerate a stale wallpaper palette. The skwd preview integration may temporarily change desktop colours; the latest applied wallpaper remains the global theme and greeter authority.
- DMS watches `~/.cache/DankMaterialShell/dms-colors.json`; skwd-wall v2 publishes that full Material palette. Vesktop consumes `dms-colors.json` directly, normalizes the active dark/light roles into its legacy token contract, and a systemd path unit regenerates its Translucence/QuickCSS bridge after palette changes. Hyprland watches the DMS palette and updates normal, group, and groupbar border colours through `hyprctl eval` with one `hl.config({...})` expression. The config provider is Lua, so `hyprctl keyword` must not be used here. DMS's own Hyprland Matugen template is disabled so there is only one border owner. Do not replace this with a full compositor reload.
- `modules/home/dms/lockscreen.json` records the owner-selected lockscreen widgets and appearance. Its placement defaults seed missing session state; existing runtime positions remain writable. The greeter follows this layout when `greeterFollowLockScreen` is enabled.
- `modules/home/dms/session-state.nix` owns the baseline `~/.local/state/DankMaterialShell/session.json`. Runtime updates use DMS IPC; the greeter consumes the matching saved session from the applied snapshot. Do not write the removed `greeterWallpaperPath` setting.
- `Super+W` launches `skwd-wall-v2`; the old custom skwd-wall keybind layer is intentionally abandoned.
- Validation floor for wallpaper changes: run `nix flake check`, `nixos-rebuild dry-build --flake .#desktop`, and a manual wallpaper/greeter smoke test. If USB behavior changes, also run `update-usb` and boot the stick on real hardware.
- `Super+Shift+W` (`dms ipc call dash toggle wallpaper`) still toggles the DMS wallpaper dashboard widget.

## Go toolchain

All hosts use the shared Go 1.27.4 package override under `modules/home/go/`. The override retains Nixpkgs' Go 1.27 patches without changing the default Go dependency of unrelated applications.

On a running USB that cannot be rebuilt, install the checksum-verified upstream Linux AMD64 SDK under `~/.local/share/go/1.27.4/go`. Keep the `go` launcher and `gofmt` link under `~/.local/bin`; the launcher defaults unset `CC`/`CXX` to `cc`/`c++` for the installed compiler wrappers. Respect explicit compiler choices and let the SDK infer GOROOT. This user installation persists outside host-scratch caches.

After a future declarative activation provides the same or newer Go, remove only these owned launcher links so they no longer shadow managed upgrades. Confirm `command -v go`, `go version`, formatting and a CGO build. No NixOS or USB activation is needed for the standalone SDK.
