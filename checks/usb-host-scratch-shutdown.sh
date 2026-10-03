#!/usr/bin/env bash
set -euo pipefail

helper="${1:?usage: usb-host-scratch-shutdown.sh SHUTDOWN_HELPER}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
real_findmnt="$(command -v findmnt)"
mkdir -p "$test_root/bin" "$test_root/root/var/lib/docker" \
  "$test_root/root/home/stefan/.local/state/system-manifest" \
  "$test_root/root/nix/.host-store/.nixos-usb/session/test-boot"
touch "$test_root/mapper"

for stub in umount cryptsetup findmnt; do
  printf '#!%s\n' "$BASH" > "$test_root/bin/$stub"
done
cat >> "$test_root/bin/umount" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >> "$SHUTDOWN_TEST_UNMOUNTS"
[ -n "${SHUTDOWN_TEST_MOUNTINFO:-}" ] || exit 1
target="$1"
[ "$target" != -l ] || target="$2"
[ "$target" != "${SHUTDOWN_TEST_FAIL_TARGET:-}" ] || exit 1
mount_id="$("$SHUTDOWN_TEST_FINDMNT" -rn -M "$target" -o ID)"
awk -v id="$mount_id" '$1 != id' "$SHUTDOWN_TEST_MOUNTINFO" > "$SHUTDOWN_TEST_MOUNTINFO.next"
mv "$SHUTDOWN_TEST_MOUNTINFO.next" "$SHUTDOWN_TEST_MOUNTINFO"
EOF
cat >> "$test_root/bin/cryptsetup" <<'EOF'
exit 0
EOF
cat >> "$test_root/bin/findmnt" <<'EOF'
exec "$SHUTDOWN_TEST_REAL_FINDMNT" --tab-file "$SHUTDOWN_TEST_MOUNTINFO" "$@"
EOF
chmod +x "$test_root/bin/"*

run_cleanup() {
  env USB_HOST_SCRATCH_FINDMNT="$SHUTDOWN_TEST_FINDMNT" \
    USB_HOST_SCRATCH_UMOUNT="$test_root/bin/umount" \
    USB_HOST_SCRATCH_CRYPTSETUP="$test_root/bin/cryptsetup" \
    USB_HOST_SCRATCH_MAPPER_DEVICE="$test_root/mapper" \
    USB_HOST_SCRATCH_PREFIXES="$test_root/root" \
    "$helper"
}

# This directory exists but is not a mountpoint. Real --target would select
# its containing filesystem and unrelated mounts; the fake umount only logs.
export SHUTDOWN_TEST_UNMOUNTS="$test_root/unmounts"
export SHUTDOWN_TEST_FINDMNT="$real_findmnt"
: > "$SHUTDOWN_TEST_UNMOUNTS"
run_cleanup
if [ -s "$SHUTDOWN_TEST_UNMOUNTS" ]; then
  echo "Shutdown cleanup selected a filesystem outside its requested paths:" >&2
  cat "$SHUTDOWN_TEST_UNMOUNTS" >&2
  exit 1
fi

export SHUTDOWN_TEST_REAL_FINDMNT="$real_findmnt"
export SHUTDOWN_TEST_FINDMNT="$test_root/bin/findmnt"
export SHUTDOWN_TEST_MOUNTINFO="$test_root/mountinfo"
docker_child="$test_root/root/var/lib/docker/containers/a b/back\\slash"
scratch="$test_root/root/nix/.host-scratch"
host_store="$test_root/root/nix/.host-store"
mkdir -p "$docker_child/nested" "$scratch" "$host_store" \
  "$test_root/root/var/lib/docker-other"
escaped_docker_child="${docker_child//\\/\\134}"
escaped_docker_child="${escaped_docker_child// /\\040}"
write_mountinfo() {
  cat > "$SHUTDOWN_TEST_MOUNTINFO" <<EOF
1 0 0:1 / / rw - tmpfs tmpfs rw
2 1 0:2 / $test_root/root rw - ext4 /dev/fake-root rw
3 2 0:3 / $escaped_docker_child rw - tmpfs tmpfs rw
4 3 0:4 / $escaped_docker_child/nested rw - tmpfs tmpfs rw
5 2 0:5 / $scratch rw - ext4 /dev/fake-scratch rw
6 2 0:6 / $host_store rw - ext4 /dev/fake-host rw
7 2 0:7 / $test_root/root/var/lib/docker-other rw - tmpfs tmpfs rw
EOF
}
write_mountinfo
: > "$SHUTDOWN_TEST_UNMOUNTS"
run_cleanup
cat > "$test_root/expected" <<EOF
$docker_child/nested
$docker_child
$scratch
$host_store
EOF
if ! cmp -s "$test_root/expected" "$SHUTDOWN_TEST_UNMOUNTS"; then
  echo "Shutdown cleanup did not select only requested descendants, deepest first." >&2
  diff -u "$test_root/expected" "$SHUTDOWN_TEST_UNMOUNTS" >&2 || true
  exit 1
fi
"$SHUTDOWN_TEST_FINDMNT" -rn -M "$test_root/root" >/dev/null
"$SHUTDOWN_TEST_FINDMNT" -rn -M "$test_root/root/var/lib/docker-other" >/dev/null

# Failure inside the read loop must reach the persisted cleanup result.
write_mountinfo
export SHUTDOWN_TEST_FAIL_TARGET="$scratch"
: > "$SHUTDOWN_TEST_UNMOUNTS"
run_cleanup
grep -Fxq 'result=failed' "$test_root/root/home/stefan/.local/state/system-manifest/host-scratch-last-cleanup"
grep -Fxq -- "-l $scratch" "$SHUTDOWN_TEST_UNMOUNTS"
echo "USB host scratch shutdown mount selection tests passed."
