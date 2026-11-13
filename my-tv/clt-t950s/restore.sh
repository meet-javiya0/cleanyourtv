#!/usr/bin/env bash
# Undo the debloat on this TV: re-enable every component in components-disabled.txt,
# then every package, then reboot.
#
# Usage: TV_HOST=<tv ip> my-tv/clt-t950s/restore.sh
#
# This firmware resets PACKAGE-level `pm disable-user` at every boot, so the bloat was
# disabled component by component. Undo re-enables components first, then packages.
set -euo pipefail
if [ -z "${TV_HOST:-}" ]; then
  echo "set TV_HOST to the TV IP address, e.g. TV_HOST=192.168.1.50 $0" >&2
  exit 2
fi
export TV_HOST
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIST="$HERE/components-disabled.txt"
[ -f "$LIST" ] || { echo "no components-disabled.txt beside this script" >&2; exit 2; }
cd "$ROOT"

echo "== re-enabling components"
while read -r pkg comp; do
  [ -n "${comp:-}" ] || continue
  tools/tv.py "pm enable --user 0 $comp" >/dev/null 2>&1 || true
done < "$LIST"

echo "== re-enabling packages (in case any is still off)"
while read -r pkg _; do
  [ -n "$pkg" ] || continue
  tools/tv.py "pm enable --user 0 $pkg" >/dev/null 2>&1 || true
done < "$LIST"

echo "done: reboot the TV"
