#!/bin/sh
# Is uisp-php2shell-guard installed and working? Read-only.
# Part of uisp-php2shell-guard by Kentucky Fi (MIT license, see LICENSE).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"
need_root_docker
pv=$(php_version)
if [ -n "$pv" ] && php_is_fixed "$pv"; then say "CRM PHP $pv — includes the PHP2Shell fix (guard no longer needed)."; else say "CRM PHP ${pv:-unknown} — VULNERABLE to PHP2Shell; keep the guard installed."; fi
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
n=0; for f in "$F_PROXY" "$F_LOC" "$F_SUSP"; do ct_has_file "$f" || continue; pull "$f" "$W/f"; if is_patched "$W/f"; then say "  guard present: $f"; n=$((n+1)); else say "  guard MISSING: $f"; fi; done
[ $n = 0 ] && { say "NOT INSTALLED (or removed by a UISP update) — run install.sh"; exit 1; }
say "Self-test:"; self_test
