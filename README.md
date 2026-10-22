# uisp-php2shell-guard

A temporary shield for **UISP servers running the CRM**, against the
**PHP2Shell** vulnerabilities (CVE-2026-109618 and CVE-2026-109619, published
21 October 2026), until Ubiquiti ships a UISP update with a patched PHP.

By **Kentucky Fi** (https://kentuckyfi.com), a rural fixed-wireless ISP in
central Kentucky, shared for other UISP operators. MIT licensed (see `LICENSE`).

Unofficial. Not made by, affiliated with, or endorsed by Ubiquiti. No warranty.
Read "What it does not do" before relying on it, and try it on a test server
first if you have one.

## Do I need it?

Run this on your UISP server:

```sh
sudo docker exec ucrm php -r 'echo PHP_VERSION, "\n";'
```

PHP2Shell is fixed in PHP **8.2.35, 8.3.36, 8.4.27 and 8.5.12**. Anything older
is vulnerable, including **PHP 8.1, which gets no fix at all**. UISP CRM 4.5.33
ships PHP 8.1.34. If your version is vulnerable and your CRM can be reached
from the internet, this guard is for you.

## What it does

PHP2Shell is triggered while PHP **reads** an incoming request, before the CRM
checks whether anyone is logged in. So a login screen alone does not help.

The guard adds a check to UISP's own web server (the `unms-nginx` container).
For the request types that can reach the vulnerable code, it first asks the CRM
"is this visitor signed in?" with a small, safe request (no body). It only lets
the request through if the answer is yes:

| Request | Not signed in | Signed in (staff or client zone) |
|---|---|---|
| Any upload (`multipart/form-data`) | **Blocked (403)** | Allowed |
| Any request body over 2 MB | **Blocked (403)** | Allowed |
| A request body with no declared size (chunked) | **Blocked (403)** | Allowed |
| Everything else (pages, logins, payments, API calls, webhooks) | Unchanged | Unchanged |

It also blocks those request types completely on the **suspended-service
page** (port 81), which never needs them.

Blocked visitors see: `Blocked: please sign in first. (Temporary security measure for PHP2Shell.)`

Tested on a live UISP server (CRM 4.5.33, unms-nginx 3.0.159) while signed in:
ticket replies with attachments, scheduling jobs, client Documents uploads,
client-zone ticket replies and plugin uploads all kept working. Webhooks such as
Twilio, payment gateways and JSON integrations are not affected, because they
don't send uploads or large bodies.

## What it does not do

- **It is not a fix.** The only fix is a UISP update with a patched PHP. Keep
  an eye on Ubiquiti's release notes.
- **Anyone with a valid login can still send these requests.** That includes
  staff accounts and **any client-zone customer account**. The guard cuts the
  risk from "anyone on the internet" to "someone holding a working login".
- **A UISP update or a rebuild of the `unms-nginx` container removes it.** Run
  `status.sh` after every UISP update and re-run `install.sh` if needed.
- It only protects traffic that goes through UISP's web server. If you expose
  the `ucrm` container some other way (custom port mappings, another proxy),
  that path is not covered.

## Install

Copy this folder to the UISP server and, as root:

```sh
sudo sh install.sh
```

It will:

1. check that this is a UISP server with the CRM, and that the web server has
   Lua support;
2. show your CRM's PHP version, and tell you if it's already fixed;
3. back up the three files it changes (to `backups/` here, and as
   `*.php2shell-guard.bak` next to each file in the container);
4. add its marked blocks, **test the web-server config**, and reload. If the
   test fails it restores the originals and changes nothing;
5. run a self-test: an anonymous upload and an oversized body must be blocked,
   while the login page and a normal small form must still work.

To use a different size limit (in bytes), for example 5 MB:

```sh
sudo MAX_ANON_BODY=5242880 sh install.sh --reinstall
```

Files changed inside the `unms-nginx` container:

- `/usr/local/openresty/nginx/conf/snippets/ucrm-proxy.conf` (shared by every CRM route)
- `/usr/local/openresty/nginx/conf/snippets/ucrm-locations.conf` (adds one internal login-check route)
- `/usr/local/openresty/nginx/conf/conf.d/ucrm-suspend.conf` (suspended-service page)

Everything the guard adds sits between `>>> uisp-php2shell-guard` and
`<<< uisp-php2shell-guard <<<` lines.

## Check it

```sh
sudo sh status.sh
```

This shows the PHP version, whether the guard is in each file, and reruns the
self-test. Also sign in and try one upload you normally use (a ticket attachment
is enough).

Blocked requests are written to UISP's web-server error log with the text
`uisp-php2shell-guard: blocked`. Where that log goes depends on your UISP
setup; this usually finds them:

```sh
sudo docker logs unms-nginx 2>&1 | grep uisp-php2shell-guard | tail
```

## Remove it

```sh
sudo sh uninstall.sh
```

This removes only the marked blocks and reloads the web server. Removal still
works after a UISP update has changed the rest of those files.

## Requirements

- UISP installed with Docker (containers `unms-nginx` and `ucrm`), run as root
- `docker`, `curl`, `awk` and `sed` on the host
- UISP's web server must include Lua (OpenResty). It does on current UISP.

## References

- CISA: Critical Vulnerabilities in PHP Require Immediate Patching —
  https://www.cisa.gov/news-events/alerts/2026/10/21/critical-vulnerabilities-php-require-immediate-patching
- Sansec: PHP2Shell technical summary and mitigations — https://sansec.io/research/php2shell
- NCSC-NL: php2shell operational information — https://github.com/NCSC-NL/php2shell

## License

MIT, © 2026 Kentucky Fi. Use it, change it, share it. See `LICENSE`.
