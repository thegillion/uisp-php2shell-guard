#!/bin/sh
# Remove uisp-php2shell-guard from UISP's web server and reload.
# Part of uisp-php2shell-guard by Kentucky Fi (MIT license, see LICENSE).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"
need_root_docker
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
changed=0
for f in "$F_PROXY" "$F_LOC" "$F_SUSP"; do
  ct_has_file "$f" || continue
  pull "$f" "$W/f"; cp "$W/f" "$W/f.orig"
  if is_patched "$W/f"; then strip_guard "$W/f"; push "$f" "$W/f"; changed=1; say "removed guard from $f"; fi
done
[ $changed = 0 ] && { say "The guard is not installed — nothing to do."; exit 0; }
nginx_test_reload || die "web server rejected the config after removal — the .php2shell-guard.bak files next to each file in the container hold the pre-install versions."
say "Uninstalled and web server reloaded."
