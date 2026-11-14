# USB Operations and Recovery

Update, boot, repair, and synchronize the portable NixOS installation. Start from a repository containing `flake.nix`; for host configuration commands see the [README](../README.md).

## Update USB Drive

Run updates while booted from another system, with the USB root unmounted. The updater refuses a root already mounted outside its own workspace, including the USB you are currently running.

```bash
sudo update-usb /path/to/system-manifest
```

`update-usb` builds the desired system in the host Nix store, then prepares an independent USB store on the desktop SSD. The previous USB squashfs stays compressed and read-only; a private OverlayFS directory holds added packages and deletions. Host store files are never hard-linked into staging. The final USB image remains one complete squashfs with the current and previous generations.

The space check reports missing packages, the estimated replacement image, safety headroom, and available space before caching the previous image. Retained generation closures are included so rollback data stays accounted for. When there is room for both the update and the old image, the updater caches that image on the SSD for faster reads. Otherwise it reads the old image directly from the USB as a read-only layer, saving its full size on the staging filesystem while keeping new packages and the replacement image on the SSD.

Staging defaults to `/var/tmp/update-usb-stage`. To use another Linux drive with OverlayFS support:

```bash
sudo update-usb --stage-dir /mnt/ssd/update-usb-stage /path/to/system-manifest
```

The staging directory must be empty or marked as owned by this updater. `--in-place` instead expands and stages on the USB, saving host space at the cost of slower USB I/O. `--force` rewrites an otherwise current installation. `--no-rollback` builds a single-generation image without preserving the previous rollback generation, saving staging and USB space. Always pass a repository containing `flake.nix`.

Normal terminal output keeps a single updating progress line; redirected output prints updates once a minute. Copy progress shows percentage and elapsed time; `-v` also shows byte counts and average rate. Buffered writes make copy-time predictions unreliable, so copies do not display an ETA. Other phases use the last completed timing for the same USB, update mode, staging location, and image source when available; these estimates can vary with package changes and system load. A first run shows elapsed time only; an exceeded historical estimate reports remaining time as unknown. Estimates apply to the current phase, not the entire update; flushing and verification remain separate steps. Add `-v` for full command output and separate progress lines every ten seconds. The latest ten JSON reports in `/var/log/update-usb/` record timings, image sizes, available USB space, and tool versions.

USB image copies reserve their destination space up front and use direct writes, limiting buffered-write backlog. Copy progress follows written file length, and the writer flushes data before reporting success. Full-image verification and recoverable publication still follow; physical write speed depends on the device.

Installation uses private Nix metadata and defers activation and bootloader changes. Before installation, the updater reconciles that metadata with the previous image so stale registrations cannot prevent missing packages from being copied; missing packages still referenced by existing store objects stop the update before publication. The updater verifies both retained package closures, copies and checksums the complete replacement image, then publishes the image, Nix metadata, and boot configuration in that order. The USB needs temporary space for the previous image, replacement image, and pending metadata. A persistent transaction record lets the next invocation resume interrupted publication before checking whether an update is needed. Cancellation removes disposable staging but preserves a prepared transaction and completed boot data.

A lock serializes updates, and the updater recovers its own mounts under `/run/update-usb`. Image replacement and metadata exchange are atomic individually; publication across the USB root and EFI partition is not one atomic operation. Keep the USB connected until cleanup completes. These changes reduce staging space and improve recovery and diagnosis; they do not guarantee faster physical USB writes.

The workflow lives in `modules/home/scripts/usb/`. The `usb-update-integration` check uses small real Nix stores and EFI boots to exercise staging, garbage collection, interrupted publication, and rollback. Validation still requires a real update and boot on target hardware before claiming USB runtime behavior is working. After boot, inspect `nixos-version --json` and `readlink -f /run/current-system`.

## Choose a Previous Generation

The top-level GRUB entries select the current generation's Default, `host-auto-store`, or `ram-store` mode. Open **NixOS - All configurations** at the bottom to see the retained generations. Open the older **Configuration** entry, identified by its number and date, then choose the desired mode, such as **host-auto-store**. Generation numbers change after updates.

The updater retains the current generation and one complete previous generation when available. The boot menu stays visible for five seconds; press an arrow key to stop the countdown while choosing.

## DMS on Portable Hosts

Desktop and USB share the committed DMS appearance and control-center settings. The USB adds automatic monitor selection, portable lock/power settings, and rendering compatibility. On unfamiliar displays it uses the Unified Bar rather than the desktop's two monitor-specific bars.

USB permits a replacement locker to restore a crashed session lock and has no log-triggered DMS restart watchdog. Restarting DMS kills its active locker, so recover from an authenticated TTY by enabling lock restoration in the affected running instance, restarting DMS, and requesting the lock again. Follow [crashed lockscreen recovery](system.md#crashed-lockscreen-recovery) for the targeted Lua commands and the manual last-resort `hl.clear_crashed_lockscreen()` API. Recovery must not automatically unlock the session. Verify locking and authentication after a real USB update and boot.

Changing or pulling the repository does not refresh the running session. Update the USB image from another booted system to make those settings part of the next USB generation. A temporary Home Manager refresh can update the current session, but packages built into the writable host-scratch store do not survive shutdown; the persistent image still needs its own update.

USB enables UPower for DMS battery readings in the bar and control center. The bar battery widget sits immediately left of notifications and appears only when UPower detects a laptop battery, including when the USB runs on laptop hardware. Desktop hosts without a laptop battery do not show a placeholder. UPower also needs system-bus registration; having its package in the store alone does not make battery telemetry available to DMS.

Closing the lid is configured to leave the system awake on battery, AC power, and while docked; explicit sleep remains available. Keep ventilation clear when closing a running laptop. This avoids lid-triggered suspend but does not establish a fix for compositor crashes during manual suspend/resume.

Before a USB image update, a temporary lid inhibitor can be started without a rebuild:

```bash
systemd-run --user --unit=usb-ignore-lid systemd-inhibit --what=handle-lid-switch --mode=block --who="USB session" --why="Keep portable USB awake on lid close" sleep infinity
```

Inspect it with `systemd-inhibit --list`. Stop it with `systemctl --user stop usb-ignore-lid.service`. It lasts until stopped or the user manager exits.

USB Brave preference synchronization clears stale crash-recovery markers while preserving session restoration and right-hand vertical tabs. This runs during Home Manager activation only when Brave is stopped; to reapply it manually, close Brave completely and run `brave-apply-state`. That command also restores the configured Vimium C state. A running browser is left untouched. If tabs are blank again, verify the recovery marker and a clean restart before changing graphics flags or deleting profile data.

## USB RAM Store Mode

Choose the USB **`ram-store` specialisation** from the bootloader when you want the system to copy `nix-store.squashfs` into RAM before NixOS mounts `/nix/store`.

That mode improves steady-state store reads after boot, uses an encrypted USB-root scratch directory for the writable overlay layer, and falls back to the USB-backed lower store if the host does not have enough free memory. After boot, run `nixos-usb-store-status` to confirm whether the lower store came from RAM or the USB image.

## USB Host Auto Store Mode

Choose the USB **`host-auto-store` specialisation** on lab machines where it is acceptable to use a writable host partition as temporary scratch storage. The USB scans non-removable Linux filesystems first (`ext2`, `ext3`, `ext4`, `xfs`, and `btrfs`), then tries `ntfs`/`ntfs3` and `exfat` as lower-priority fallbacks. A per-boot encrypted sparse image is created under `.nixos-usb/session/<boot-id>/` on the selected host filesystem, and only that encrypted image is used for the copied `nix-store.squashfs`, writable store overlay, Docker state, local cache, Codex state, Brave profile, Steam library, and temporary `repositories` directory.

After boot, check which path was used:

```bash
cat /run/nixos-usb-store-mode
nixos-usb-store-status
nixos-usb-host-scratch-status
```

`writable-encrypted-host-auto-overlay` means store reads and writes are backed by the encrypted host scratch image. If no suitable partition can be mounted or copied to, the specialisation falls back to the USB-backed squashfs and encrypted USB-root scratch writable layer. `nixos-usb-store-status` prints the selected store mode, host candidates, mount diagnostics, and relevant initrd service logs. `nixos-usb-host-scratch-status` shows Docker/cache/Codex/Brave/Steam bind mounts and the active repositories path.

Host-auto does not unlock BitLocker or other encrypted host partitions. If the main Windows partition is BitLocker-encrypted and only small EFI/recovery partitions remain, `no-candidates` is expected. On this fallback, `nixos-usb-store-status` also shows a current partition inventory and explains the exclusions; this inventory is separate from the recorded boot diagnostics. A supported partition needs both sufficient total size and free space, as reported by `min_candidate_bytes`, and must mount writable.

If the owner chooses to turn off Windows device encryption, let Windows finish fully decrypting the volume before booting USB. Suspending BitLocker protection leaves the filesystem encrypted and is insufficient. Use a full Windows shutdown before host-auto writes NTFS; do not use a hibernated Windows volume or force a dirty volume to mount. Decryption removes protection for Windows files; host scratch remains separately encrypted. Verify NTFS scratch operation on a real boot.

USB display defaults remain at 100% scaling for lab computers. The Samsung Display Corp. 0x4154 high-density panel has a specific 200% rule, preserving its preferred native resolution and refresh rate. That rule lives in `hypr/system-manifest/usb-outputs.lua`, loaded after DMS output configuration so DMS startup cannot overwrite it.

USB GPU widgets use portable selection instead of pinning the desktop NVIDIA device. Confirm GPU temperature after DMS startup and after moving to another host; package/configuration checks do not establish hardware monitoring correctness.

To make essential Codex and Brave changes durable before shutdown, quit Brave normally first so its saved session is consistent, then checkpoint. You can reopen Brave afterwards:

```bash
usb-host-scratch checkpoint
usb-host-scratch checkpoint --include-cache
usb-host-scratch status
```

Checkpoints are serialized and update phase, scope, and result diagnostics shown by `status`. The default checkpoint persists essential Codex session state and Brave profile state while excluding volatile caches and USB-local Codex authentication/configuration. Add `--include-cache` for an explicit, potentially slow full `~/.cache` copy. Docker state, everything under the host-scratch `repositories` directory, and games installed in `~/games/SteamLibrary` remain intentionally temporary. Steam Cloud is the durability path for supported game saves. Push repository work you want to keep, or copy the repository to persistent storage before powering off; local commits inside host scratch are temporary too.

Keep the USB connected until the computer has powered off. The console message `Reached target System Power Off` can appear before final filesystem and encrypted scratch cleanup finishes. If shutdown stops there, leave the USB attached while diagnosing it.

For fast temporary clones:

```bash
cd "$(usb-host-scratch)"
git clone https://github.com/OWNER/REPO.git
```

Steam is included with the USB's portable 32-bit graphics runtime and GameMode. When encrypted host scratch is active, launching Steam in `host-auto-store` automatically bootstraps its mutable client and default `steamapps` library on the host SSD. The existing `~/games/SteamLibrary` location remains available too. Inspect the client path with:

```bash
steam-host-scratch status
```

Both locations are temporary and erased at shutdown. Account configuration, Steam Guard sentry files, and userdata are imported from persistent USB home on first launch. After exiting Steam, save changes explicitly with:

```bash
steam-host-scratch checkpoint
```

Games and compatibility prefixes are not checkpointed. Wait for Steam Cloud to finish syncing supported saves before powering off; saves outside Steam userdata need their own backup. Normal USB boots and host-auto fallback retain Steam's persistent data-home behavior.

On clean shutdown, the USB first detaches live Docker and user-state bind mounts, then gives the essential Codex/Brave sync 50 seconds plus at most five seconds to terminate, leaving cleanup time inside systemd's hard 60-second stop budget. The two initrd-created host mounts bypass systemd's generic `umount.target`; the shutdown-ramfs hook owns their dependency-sensitive teardown so it can unmount scratch, close the mapper, and only then unmount the host backing filesystem without misleading failed-unmount messages. Cleanup still removes host-side encrypted session files after a sync failure or timeout. A forced power-off cannot guarantee the final sync; use `usb-host-scratch checkpoint` first when recent state matters. If power is cut, the host may retain ciphertext under `.nixos-usb/session/`, but the key only lived in RAM and stale session files are removed on the next successful host-auto boot.

## Initialize / Reformat Persistent USB

```bash
sudo setup-persistent-usb /dev/sdX
```

`setup-persistent-usb` takes an explicit target disk path (for safety). It wipes the disk, creates `NIXOS_BOOT` + `NIXOS_USB_CRYPT` partitions, initializes LUKS, and formats the encrypted root as ext4.

## Sync Codex State (Desktop <-> USB)

```bash
codex-state-sync to-usb    # before leaving for a lab machine
codex-state-sync from-usb  # after returning
```

The script merges only active rollout files under `~/.codex/sessions/`; it never deletes destination-only sessions, and it preserves a newer destination copy. Before replacing an older same-path rollout, it saves the old file under `~/.local/state/codex-state-sync/backups/`. When files change, it also backs up the destination state database and requests a rollout reindex for the next Codex launch.

Close Codex before running `from-usb`; the command refuses to import while a local Codex process is active. Auth, declarative config, databases, archived sessions, goals, memories, skills, agents, caches, and logs remain local to each machine.

## Maintainer constraints

The USB-specific invariants below complement the operational instructions above.

- **Purpose:** Updates the bootable USB drive configuration from the `usb` flake output.
- **Command:** `sudo update-usb /path/to/system-manifest`
- **Ownership:** The USB installer workflow lives under `modules/home/scripts/usb/`; keep Nix focused on constants/packaging and runtime behavior in the extracted `update-usb` shell fragments.
- **Flow:** Validates labeled partitions and locks the updater; recovers its `/run/update-usb` mounts and any pending publication; builds the desired system in the host store; stages a private USB store and Nix database on the SSD. The prior squashfs is a read-only OverlayFS lower layer, cached on the SSD only when it fits alongside the estimated update; otherwise it stays on the USB. Changed files use a private upper directory. `--stage-dir PATH` selects another Linux drive; `--in-place` expands staging on USB. Installation defers activation and bootloader changes. Target-local garbage collection runs in a private PID/mount namespace without activation. Both retained closures are verified and stage mounts are released before publishing image, metadata, and boot configuration in order.
- **Recovery:** The completed `nix-store.squashfs` is persistent boot data. A `.tmp` image belonging to `.update-usb-transaction` is also protected during cleanup and recovered before no-op detection. Private staging is disposable only after target bindings and stage mounts are released. Marker ownership protects unrelated staging files. GRUB retains current and previous generations; inconsistent profile/image metadata starts a clean private install. The image and Nix state each publish atomically, but the root and EFI partitions are not one atomic transaction. Reports retain the latest ten runs under `/var/log/update-usb`. Always pass a repository containing `flake.nix`.
- **Boot Modes:** The USB keeps the default squashfs+tmpfs hybrid store path as native NixOS `fileSystems`, and also exposes manual `ram-store` and `host-auto-store` specialisations through small initrd preparation units. `ram-store` copies `nix-store.squashfs` into RAM before mounting `/nix/store`, uses USB-root scratch for the writable overlay backing directory, and falls back to the USB-backed lower layer if memory is tight. `host-auto-store` aggressively scans large non-removable host Linux partitions first, then `ntfs`/`ntfs3` and `exfat` fallbacks. When a host candidate works, it creates a per-boot encrypted sparse image under `.nixos-usb/session/<boot-id>/` and uses the decrypted `/nix/.host-scratch` mount for the copied squashfs lower image, writable overlay layer, Docker state, `~/.cache`, `~/.codex`, Brave profile, temporary Steam library at `~/games/SteamLibrary`, and temporary `repositories` directory. Clean shutdown syncs essential Codex and Brave state back to USB and removes host-side encrypted session files; a full `~/.cache` copy requires `usb-host-scratch checkpoint --include-cache`. Steam games are not checkpointed. Power loss can leave only ciphertext, which the next host-auto boot prunes. If host-auto setup fails, it falls back to the USB-backed lower layer and USB-root scratch. After boot, use `nixos-usb-store-status` and `nixos-usb-host-scratch-status` to inspect the selected mode, bind mounts, repositories path, and fallback diagnostics.
- **Host Scratch Repositories:** On host-auto USB boots, use `cd "$(usb-host-scratch)"` before cloning repos for fast host-SSD I/O. The directory is named `repositories` inside encrypted host scratch.
- **Runtime Validation:** `nix flake check` and `dry-build` do not prove USB-only runtime behavior. For cursor/rendering/DMS issues, update the stick and boot it on real target hardware before declaring the fix done.
- **GH auth on foreign machines:** Prefer `gh auth login --web --git-protocol https`. If gnome-keyring is unavailable, log in again for that environment rather than exporting a long-lived PAT through `GH_TOKEN`.

## Codex session-sync invariants

Codex resumable state lives under `~/.codex/`. To share it between desktop and USB, plug in the USB and use `codex-state-sync`:

- `codex-state-sync to-usb` — push desktop Codex state to USB (run before leaving for a lab)
- `codex-state-sync from-usb` — pull USB Codex state back to desktop (run when back home)

The script finds the USB automatically via the `NIXOS_USB_CRYPT` disk label, unlocks LUKS, mounts, merges only active rollout files under `~/.codex/sessions/`, and unmounts. It never deletes destination-only sessions, preserves newer destination copies, and backs up overwritten rollouts plus the destination state database under `~/.local/state/codex-state-sync/backups/`. When rollouts change, it requests a destination reindex for the next Codex launch.

Close Codex before running `from-usb`; the command refuses to import while a local Codex process is active. Auth, declarative config, databases, archived sessions, goals, memories, skills, agents, caches, and logs remain local to each machine. Requires `sudo` for the USB unlock and mount steps.

At the lab: `codex resume` to pick up synced sessions.

Linear MCP auth is local to each machine. If Codex says Linear is not logged in, run `codex mcp login linear` once on that machine; do not sync the resulting auth state through `codex-state-sync`.

**tmux sessions** remain on the machine where their server is running; rebuilding or booting the USB elsewhere does not transfer running processes. A session can be reattached over SSH to that same running machine. The optional tmux configuration is shared across hosts.
