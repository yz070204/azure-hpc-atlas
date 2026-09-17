#!/usr/bin/env bash

active_thp() {
  sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$1"
}

enable_thp() {
  thp_dir=/sys/kernel/mm/transparent_hugepage
  command -v sudo >/dev/null || die "sudo is required for the approved THP profile."
  sudo -n true || die "Non-interactive privilege is required; no THP setting changed."
  old_enabled=$(active_thp "$thp_dir/enabled")
  old_defrag=$(active_thp "$thp_dir/defrag")
  [[ -n $old_enabled && -n $old_defrag ]] || die "Cannot determine THP values to restore."
  printf 'enabled=%s\ndefrag=%s\n' "$old_enabled" "$old_defrag" > "$output/thp-original.txt"

  trap restore_thp EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf 'always\n' | sudo -n tee "$thp_dir/enabled" > /dev/null
  printf 'always\n' | sudo -n tee "$thp_dir/defrag" > /dev/null
  [[ $(active_thp "$thp_dir/enabled") == always && $(active_thp "$thp_dir/defrag") == always ]] ||
    die "THP always did not take effect."
  cat "$thp_dir/enabled" "$thp_dir/defrag" > "$output/thp-active.txt"
}

restore_thp() {
  local status=$? failed=0
  trap - EXIT
  set +e
  printf '%s\n' "$old_enabled" | sudo -n tee "$thp_dir/enabled" > /dev/null || failed=1
  printf '%s\n' "$old_defrag" | sudo -n tee "$thp_dir/defrag" > /dev/null || failed=1
  [[ $(active_thp "$thp_dir/enabled") == "$old_enabled" &&
     $(active_thp "$thp_dir/defrag") == "$old_defrag" ]] || failed=1
  cat "$thp_dir/enabled" "$thp_dir/defrag" > "$output/thp-restored.txt" || failed=1
  if ((failed)); then
    echo "ERROR: THP restoration failed; restore values in $output/thp-original.txt." >&2
    exit 1
  fi
  exit "$status"
}
