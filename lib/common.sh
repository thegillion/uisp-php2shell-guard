# uisp-php2shell-guard — shared helpers (POSIX sh). Sourced by install/uninstall/status.
NGINX_CT=${NGINX_CT:-unms-nginx}
# Part of uisp-php2shell-guard by Kentucky Fi (MIT license, see LICENSE).
CRM_CT=${CRM_CT:-ucrm}
CONF=/usr/local/openresty/nginx/conf
F_PROXY=$CONF/snippets/ucrm-proxy.conf
F_LOC=$CONF/snippets/ucrm-locations.conf
F_SUSP=$CONF/conf.d/ucrm-suspend.conf
MARK_BEGIN='>>> uisp-php2shell-guard'
MARK_END='<<< uisp-php2shell-guard <<<'
MAX_ANON_BODY=${MAX_ANON_BODY:-2097152}   # bytes; anonymous bodies above this need a login
GUARD_TEXT='Blocked: please sign in first.'

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_root_docker() {
  [ "$(id -u)" = 0 ] || die "run as root (sudo)."
  command -v docker >/dev/null 2>&1 || die "docker not found."
  for c in "$NGINX_CT" "$CRM_CT"; do
    docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true || die "container '$c' is not running (is this a UISP server with CRM?)."
  done
}

# PHP version inside the CRM container, e.g. 8.1.34
php_version() { docker exec "$CRM_CT" php -r 'echo PHP_VERSION;' 2>/dev/null; }

# 0 = this PHP already has the PHP2Shell fix (8.2.35+, 8.3.36+, 8.4.27+, 8.5.12+, 8.6+)
php_is_fixed() {
  v=$1; maj=${v%%.*}; rest=${v#*.}; min=${rest%%.*}; pat=${rest#*.}; pat=${pat%%[!0-9]*}
  [ "$maj" -gt 8 ] && return 0
  [ "$maj" -lt 8 ] && return 1
  case $min in
    0|1) return 1 ;;
    2) [ "$pat" -ge 35 ] ;;
    3) [ "$pat" -ge 36 ] ;;
    4) [ "$pat" -ge 27 ] ;;
    5) [ "$pat" -ge 12 ] ;;
    *) return 0 ;;
  esac
}

has_lua() { docker exec "$NGINX_CT" nginx -V 2>&1 | grep -qi 'lua'; }

ct_has_file() { docker exec "$NGINX_CT" test -f "$1"; }

# copy a file out of / into the nginx container
pull() { docker cp "$NGINX_CT:$1" "$2" >/dev/null; }
push() { docker cp "$2" "$NGINX_CT:$1" >/dev/null && docker exec "$NGINX_CT" sh -c "chown root:root '$1' && chmod 644 '$1'"; }

is_patched() { grep -q "$MARK_BEGIN" "$1"; }

# remove every marked block from a file (in place)
strip_guard() {
  # Drops each marked block plus the single blank line install.sh put in front
  # of an appended block; every other line (blank or not) is kept as-is.
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    skip { if (index($0, e)) skip = 0; next }
    index($0, b) { skip = 1; held = 0; next }
    /^$/ { if (held) print ""; held = 1; next }
    { if (held) print ""; held = 0; print }
    END { if (held) print "" }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

render() { sed "s/__MAX_ANON_BODY__/$MAX_ANON_BODY/" "$1"; }

nginx_test_reload() {
  docker exec "$NGINX_CT" nginx -t >/dev/null 2>&1 || return 1
  docker exec "$NGINX_CT" nginx -s reload >/dev/null 2>&1 || return 1
  # "reload" returns at once; old worker processes keep answering for a moment
  # with the previous config. Give the new ones time to take over.
  sleep 3
}

# Self-test against this server's own HTTPS port. Prints lines, returns 0 if all good.
self_test() {
  base=${SELFTEST_URL:-https://127.0.0.1}
  ok=0
  body=$(curl -sk --max-time 15 -F 'php2shell_guard_selftest=1' "$base/crm/login" 2>/dev/null)
  if ! printf '%s' "$body" | grep -q "$GUARD_TEXT"; then   # one retry, in case an old worker answered
    sleep 2; body=$(curl -sk --max-time 15 -F 'php2shell_guard_selftest=1' "$base/crm/login" 2>/dev/null)
  fi
  if printf '%s' "$body" | grep -q "$GUARD_TEXT"; then say "  PASS  anonymous upload to /crm/login is blocked"; else say "  FAIL  anonymous upload to /crm/login was NOT blocked"; ok=1; fi
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "$base/crm/login")
  if [ "$code" = 200 ] || [ "$code" = 302 ]; then say "  PASS  login page still loads ($code)"; else say "  FAIL  login page answered $code"; ok=1; fi
  big=$(head -c $((MAX_ANON_BODY + 1024)) /dev/zero | tr '\0' 'a')
  body=$(printf 'x=%s' "$big" | curl -sk --max-time 30 --data-binary @- "$base/crm/login" 2>/dev/null)
  if printf '%s' "$body" | grep -q "$GUARD_TEXT"; then say "  PASS  anonymous oversized body is blocked"; else say "  FAIL  anonymous oversized body was NOT blocked"; ok=1; fi
  body=$(curl -sk --max-time 15 -d 'a=b' "$base/crm/login" 2>/dev/null)
  if printf '%s' "$body" | grep -q "$GUARD_TEXT"; then say "  FAIL  a normal small form post was blocked"; ok=1; else say "  PASS  normal small form posts are untouched"; fi
  return $ok
}
