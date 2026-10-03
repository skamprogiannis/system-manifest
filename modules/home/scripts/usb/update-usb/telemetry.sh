#!/usr/bin/env bash
# jq filters use their own variables inside single-quoted strings.
# shellcheck disable=SC2034,SC2016

report_warning() {
  printf 'Warning: update report could not be saved: %s\n' "$*" >&2
}

report_update() {
  local filter="$1" temporary
  shift
  [ -n "${UPDATE_REPORT_FILE:-}" ] || return 0
  if ! temporary="$(mktemp "${UPDATE_REPORT_FILE}.XXXXXX")"; then
    report_warning "$UPDATE_REPORT_FILE"
    return 0
  fi
  if "${UPDATE_USB_JQ:-jq}" "$@" "$filter" "$UPDATE_REPORT_FILE" >"$temporary" && mv -f -- "$temporary" "$UPDATE_REPORT_FILE"; then
    return 0
  fi
  rm -f -- "$temporary"
  report_warning "$UPDATE_REPORT_FILE"
}

prune_update_reports() {
  local directory="$1" name count=0
  while IFS= read -r name; do
    count=$((count + 1))
    if [ "$count" -gt 10 ]; then rm -f -- "$directory/$name"; fi
  done < <(find "$directory" -maxdepth 1 -type f -name 'update-usb-*.json' -printf '%f\n' | sort -r)
}

start_update_report() {
  local directory="$1" source_dir="$2" target_mount="$3"
  local source_revision device free_bytes tools_json
  UPDATE_REPORT_FILE=""
  UPDATE_REPORT_STARTED_AT="$(date +%s)"
  if [ -L "$directory" ] || ! mkdir -p -- "$directory" || ! chmod 0700 "$directory"; then
    report_warning "$directory"
    return 0
  fi
  if ! UPDATE_REPORT_FILE="$(mktemp "$directory/update-usb-$(date -u +%Y%m%dT%H%M%S%N)-XXXXXX.json")"; then
    report_warning "$directory"
    return 0
  fi
  source_revision="$(git -C "$source_dir" describe --always --dirty --abbrev=40 2>/dev/null || printf unknown)"
  device="$(findmnt -n -o SOURCE --target "$target_mount" 2>/dev/null || printf unknown)"
  free_bytes="$(df -B1 --output=avail -- "$target_mount" 2>/dev/null | awk 'NR == 2 { print $1 }')" || free_bytes=0
  tools_json="$("${UPDATE_USB_JQ:-jq}" -n \
    --arg nix "$(nix --version 2>/dev/null || true)" \
    --arg squashfs "$(mksquashfs -version 2>/dev/null | sed -n '1p' || true)" \
    --arg cp "$(cp --version 2>/dev/null | sed -n '1p' || true)" \
    --arg mount "$(mount --version 2>/dev/null | sed -n '1p' || true)" \
    --arg cryptsetup "$(cryptsetup --version 2>/dev/null || true)" \
    '{nix: $nix, squashfs: $squashfs, cp: $cp, mount: $mount, cryptsetup: $cryptsetup}')" || tools_json='{}'
  if ! "${UPDATE_USB_JQ:-jq}" -n \
    --arg started_at "$(date -u +%FT%TZ)" \
    --arg source_revision "$source_revision" \
    --arg updater_revision "${UPDATE_USB_REVISION:-unknown}" \
    --arg kernel "$(uname -r)" \
    --arg mode "${MODE:-unknown}" \
    --arg mount "$target_mount" --arg device "$device" \
    --argjson free_bytes "${free_bytes:-0}" --argjson tools "$tools_json" \
    '{schema: 1, started_at: $started_at, status: "running", source_revision: $source_revision,
      updater_revision: $updater_revision, kernel: $kernel, mode: $mode, tools: $tools,
      target: {mount: $mount, device: $device, free_bytes: $free_bytes}, phases: [], images: {}}' >"$UPDATE_REPORT_FILE"; then
    report_warning "$UPDATE_REPORT_FILE"
    rm -f -- "$UPDATE_REPORT_FILE"
    UPDATE_REPORT_FILE=""
    return 0
  fi
  prune_update_reports "$directory" || report_warning 'report retention'
}

report_phase() {
  report_update '.phases += [{name: $name, label: $label, seconds: $seconds, status: $status}]' \
    --arg name "$1" --arg label "$2" --argjson seconds "$3" --arg status "${4:-completed}"
}

report_image() {
  local role="$1" path="$2" bytes
  [ -n "${UPDATE_REPORT_FILE:-}" ] || return 0
  if ! bytes="$(stat -c '%s' -- "$path")"; then return 0; fi
  report_update '.images[$role] = {path: $path, bytes: $bytes}' \
    --arg role "$role" --arg path "$path" --argjson bytes "$bytes"
}

finish_update_report() {
  local exit_status="$1" status=failed elapsed
  [ -n "${UPDATE_REPORT_FILE:-}" ] || return 0
  if [ "$exit_status" -eq 0 ]; then status=completed;
  elif [ "${CANCELED:-0}" -eq 1 ]; then status=canceled; fi
  if [ "${PHASE_ACTIVE:-0}" -eq 1 ]; then
    elapsed=$(( $(date +%s) - PHASE_STARTED_AT ))
    report_phase "$CURRENT_PHASE" "$PHASE_LABEL" "$elapsed" "$status"
    PHASE_ACTIVE=0
  fi
  elapsed=$(( $(date +%s) - UPDATE_REPORT_STARTED_AT ))
  report_update '.status = $status | .exit_status = $exit_status | .finished_at = $finished_at | .elapsed_seconds = $elapsed' \
    --arg status "$status" --argjson exit_status "$exit_status" \
    --arg finished_at "$(date -u +%FT%TZ)" --argjson elapsed "$elapsed"
  printf 'Update report: %s\n' "$UPDATE_REPORT_FILE"
  UPDATE_REPORT_FILE=""
}
