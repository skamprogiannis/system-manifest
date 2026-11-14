# Continue USB recovery and desktop fixes

Continue work on https://github.com/skamprogiannis/system-manifest.
Read AGENTS.md, docs/maintainers.md, docs/system.md, docs/usb.md, and DESIGN.md before changes.

## Durable recovery
GitHub main was advanced normally to 07b41a916668b0904ceceaaf548f727f134a9c53 on 2026-11-14.
It contains nine atomic commits: seven recovered USB/DMS/docs commits, shared Go 1.27.4 toolchain plus CI coverage, and declarative lockscreen recovery plus Brave helper regression coverage.
Trees were verified identical to RAM integration HEAD 0e27fefd59dd022583a8a68e0bf81049543828d5.
The normal Git credential helper failed after USB disconnection; connected GitHub APIs recreated commit metadata while preserving every tree and message.
Branch recovery/usb-20261114 contains recovered.bundle: the exact original nine rebased commits before API publication. Its prerequisite is be0f30b6c86d37665ec2afe7ec57b02467596928 (an ancestor of main). Clone main first, extract the bundle from the recovery branch, and use git bundle verify/list-heads if exact original commit IDs are needed.
The recovery branch is an artifact branch, not the normal source checkout.

Before disconnection, seven empty Git objects were reconstructed exactly and original git fsck passed. Original main was bfc3bad, seven ahead and 32 behind origin. An interrupted merge aff14d1 and uncommitted Go work were in /tmp/system-manifest-go-upgrade. Its indexed DMS settings file was empty, but the valid working file was recovered; do not restore the empty snapshot.
Raw repository and worktree archives were verified under ~/.local/state/system-manifest/recovery-20261114 on the USB before it failed. They may require offline filesystem recovery to access.

## Machine state and boundaries
USB root /dev/mapper/root entered ext4 emergency_ro and then the user reported the USB disconnected.
Do not remount it writable or run fsck on a mounted filesystem.
The original checkout could not be advanced to the final main because of this. Start from a fresh clone on reliable storage; identify the actual current worktree instead of assuming documentation paths.
Last-session RAM checkout: /run/user/1000/system-manifest-recovery/integrated, independent .git with no alternates. It disappears on reboot.
No NixOS rebuild/switch, USB image update, or reboot was performed. Updating Git does not update the installed USB generation.

## Lockscreen
Evidence: DMS reported locked at 14:47:44, then the USB event watchdog restarted DMS a second later. This killed its locker; Hyprland remained running.
Main removes that watchdog and enables shared misc.allow_session_lock_restore. Docs describe authenticated TTY recovery; never automate clearing the lockscreen.
Last-session workaround: runtime watchdog drop-in ExecCondition=/run/current-system/sw/bin/false, watchdog stopped; targeted hl.config enabled restoration, readback true.
A marked temporary block was appended to ~/.config/hypr/dms/binds-user.lua, preserving custom bindings. The original file and cleanup instructions are in the USB recovery directory.
Only remove that block after effective declarative activation supplies restoration. Runtime readback is not proof of actual crash recovery.
Do not restart DMS while locked; inspect dms ipc call lock status first. User did not verify a deliberate crash/relock cycle.

## Brave
Earlier Codex investigation found missing right-hand tab rows after crash/session recovery.
The local declarative fix clearing stale USB profile markers was recovered into main; the installed brave-apply-state helper predates it.
During this session, Brave preferences and Sessions were backed up, Brave was closed gracefully, only profile.exit_type=Normal and profile.exited_cleanly=true were patched, and Brave reopened normally.
Tab, extension, browser, and session preferences were checked unchanged. User confirmed new right-hand tabs and Catppuccin theme both work.
Do not reset profiles, delete Sessions, disable extensions, or change graphics flags without fresh evidence. The second planned restart was not verified after the USB failure.
A new script-smoke test exercises the actual helper in an isolated HOME and verifies running-browser refusal and preservation of unrelated JSON fields.

## Battery: unfinished live verification
User asks for the laptop battery on the Dank bar, as previously configured.
Kernel and UPower reported 100%. Current installed generation had no upower.service/system-bus registration, although the package existed.
With user polkit authentication, a reversible RAM-only setup was applied:
- /run/system-manifest-upower/system.conf copies the existing system bus config plus the upstream UPower policy include.
- It is bind-mounted over /etc/dbus-1/system.conf; the bus configuration was reloaded, not restarted.
- upower-session.service is a transient root service running the existing /nix/store/wcpyz54aw8ks18shn94knfh6inv63v6v-upower-1.91.5/libexec/upowerd.
- Bus enumeration and DisplayDevice showed a present, fully charged battery at 100%.
DMS still did not show the battery; user suggested refreshing DMS, then reported USB disconnection. Do not claim the widget is fixed. We deliberately left DMS running to avoid losing the session while saving work.
Current installed settings had battery enabled AFTER notifications; recovered declarative settings place it immediately BEFORE notifications and provide UPower for USB/laptop plus battery availability patches.
Next investigate whether a safe unlocked DMS restart discovers UPower. Do not restart from missing USB binaries. Use a healthy boot/reliable store first.
The attempted scalar IPC settings showBatteryPercent/showBatteryPercentOnlyOnBattery were invalid keys and changed nothing; these are per-widget options. Arrays cannot be set with installed settings IPC. Preserve existing layout and theme. Runtime /run setup disappears on reboot.

## Validation and remaining work
Passed: git fsck, exact object/tree verification, changed Nix syntax parsing, Python syntax parsing, git diff --check, and all 26 CI selector tests.
Go check uses its own CI unit group/domain so documentation changes do not trigger a Go build.
Not run: full Nix checks/builds, actual Go/CGO toolchain build, desktop dry-build, new Brave smoke check execution, real USB boot and lock/authentication tests.
Nix evaluation failed with daemon connection reset after storage failure. Reestablish a healthy environment; run proportional focused checks with --max-jobs 1 --cores 1, and desktop dry-build before desktop integration/deployment.
Review the final diff independently when available. A requested second worker could not launch because the local delegation budget hook could not verify its state; no new independent final architecture review completed.
Correct stale documentation: README still claims ChatGPT on all hosts although upstream restricts it to desktop; docs/usb.md still describes Unified Bar/two desktop bars despite current shared Main Bar layout.
Use atomic Conventional Commits; preserve system.configurationRevision. No force push. Do not activate or update the USB until authorized and the hardware/storage situation is understood.
