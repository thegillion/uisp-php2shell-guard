#!/bin/sh
# Install uisp-php2shell-guard into UISP's web server (container unms-nginx).
# Part of uisp-php2shell-guard by Kentucky Fi (MIT license, see LICENSE).
# Usage:  sudo sh install.sh            (MAX_ANON_BODY=bytes to change the 2 MB default)
#         sudo sh install.sh --reinstall
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"

need_root_docker
pv=$(php_version); say "UISP CRM PHP version: ${pv:-unknown}"
if [ -n "$pv" ] && php_is_fixed "$pv"; then
  say "This PHP already includes the PHP2Shell fix. The guard is not needed; installing anyway is harmless."
fi
has_lua || die "UISP's web server here has no Lua support; this guard can't be installed on this UISP version."
for f in "$F_PROXY" "$F_LOC"; do ct_has_file "$f" || die "expected UISP file not found: $f (unsupported UISP version)."; done

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pull "$F_PROXY" "$W/proxy.conf"; pull "$F_LOC" "$W/loc.conf"
SUSP=0; if ct_has_file "$F_SUSP"; then pull "$F_SUSP" "$W/susp.conf"; SUSP=1; fi

if is_patched "$W/proxy.conf"; then
  if [ "${1:-}" = --reinstall ]; then say "Already installed: removing the old guard first."; strip_guard "$W/proxy.conf"; strip_guard "$W/loc.conf"; [ $SUSP = 1 ] && strip_guard "$W/susp.conf"
  else say "Already installed. Run status.sh to check it, or install.sh --reinstall to replace it."; exit 0; fi
fi

# Sanity: every CRM route must go through ucrm-proxy.conf, or it wouldn't be guarded.
grep -q 'location /crm/' "$W/loc.conf" || die "ucrm-locations.conf has no 'location /crm/' (unsupported UISP version)."
unguarded=$(awk '/^location /{loc=$0; inc=0} /ucrm-proxy.conf/{inc=1} /^}/{ if (loc != "" && !inc) print loc; loc="" }' "$W/loc.conf")
[ -n "$unguarded" ] && warn "these CRM routes don't include ucrm-proxy.conf and will NOT be guarded: $unguarded"

# Backups: package folder (timestamped) + next to the file inside the container (first install only).
B="$HERE/backups/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$B"
cp "$W/proxy.conf" "$B/ucrm-proxy.conf"; cp "$W/loc.conf" "$B/ucrm-locations.conf"; [ $SUSP = 1 ] && cp "$W/susp.conf" "$B/ucrm-suspend.conf"
for f in "$F_PROXY" "$F_LOC" "$F_SUSP"; do docker exec "$NGINX_CT" sh -c "[ -f '$f' ] && [ ! -f '$f.php2shell-guard.bak' ] && cp -p '$f' '$f.php2shell-guard.bak' || true"; done
cp "$W/proxy.conf" "$W/proxy.orig"; cp "$W/loc.conf" "$W/loc.orig"; [ $SUSP = 1 ] && cp "$W/susp.conf" "$W/susp.orig"

# Patch the copies.
{ printf '\n'; render "$HERE/lib/guard-proxy.lua.conf"; } >> "$W/proxy.conf"
{ printf '\n'; render "$HERE/lib/guard-location.conf"; } >> "$W/loc.conf"
if [ $SUSP = 1 ]; then
  if [ "$(grep -c '^  location / {' "$W/susp.conf")" = 1 ]; then
    render "$HERE/lib/guard-suspend.lua.conf" > "$W/susp.block"
    awk -v blk="$W/susp.block" '{ print } /^  location \/ \{/ { while ((getline l < blk) > 0) print l }' "$W/susp.conf" > "$W/susp.new" && mv "$W/susp.new" "$W/susp.conf"
  else warn "ucrm-suspend.conf has an unexpected layout; the suspended-service page (port 81) is NOT guarded."; SUSP=0; fi
fi

push "$F_PROXY" "$W/proxy.conf"; push "$F_LOC" "$W/loc.conf"; [ $SUSP = 1 ] && push "$F_SUSP" "$W/susp.conf"
if ! nginx_test_reload; then
  warn "web server rejected the new config; restoring the originals."
  docker exec "$NGINX_CT" nginx -t 2>&1 | tail -5 >&2
  push "$F_PROXY" "$W/proxy.orig"; push "$F_LOC" "$W/loc.orig"; [ -f "$W/susp.orig" ] && push "$F_SUSP" "$W/susp.orig"
  nginx_test_reload || die "could not reload the restored config — check 'docker exec $NGINX_CT nginx -t' now."
  die "install aborted; nothing changed."
fi
say "Installed and web server reloaded. Backups: $B"
say "Self-test:"; if self_test; then say "All good."; else warn "self-test found a problem — run uninstall.sh if anything misbehaves."; fi
say "Note: a UISP update or container rebuild removes the guard. Run status.sh after every UISP update."
