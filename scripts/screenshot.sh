#!/usr/bin/env bash
# Photograph a running harness, one shot per line of a plugin's shot list.
#
#   scripts/screenshot.sh <shots.tsv> [output-dir]
#
# The shot list is the plugin's, not the harness's: which screens sell a plugin
# is an editorial decision and the only part of this that cannot be automated.
# Columns, tab separated, '#' comments and blank lines ignored:
#
#   name  path  frame-selector  click-selector  pad  margin  width  height
#
#   name             output file stem, e.g. screenshot-1
#   path             site-relative, e.g. /product/a-book/ or
#                    /wp-admin/admin.php?page=my-settings
#   frame-selector   CSS selector list; the union of every match is the crop
#   click-selector   clicked before the frame is measured, or '-'
#   pad              page pixels kept round the subject
#   margin           flat pixels of page colour added after cropping
#   width height     viewport in CSS pixels; height only has to be enough to
#                    hold the subject, since the crop decides the result
#
# Everything is rendered at device scale 2 and halved, because Chrome's 2x text
# downsampled is visibly cleaner than its 1x, and the published sets in this
# range are 1x.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

shots="${1:?usage: screenshot.sh <shots.tsv> [output-dir]}"
outdir="${2:-dist/screenshots}"
here="$(cd "$(dirname "$0")" && pwd)"

[ -r "$shots" ] || { echo "No such shot list: $shots" >&2; exit 1; }

pc_require_plugin
pc_require_docker

command -v google-chrome >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1 || {
  echo "Headless Chrome is needed and was not found on PATH." >&2
  exit 1
}
chrome="$(command -v google-chrome || command -v chromium)"

mkdir -p "$outdir"

container="$(pc_compose ps -q wordpress)"
[ -n "$container" ] || { echo "The harness is not running. Run scripts/install.sh first." >&2; exit 1; }

token="$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; docker exec "$container" rm -f /var/www/html/wp-content/mu-plugins/pc-screenshot-mode.php >/dev/null 2>&1 || true' EXIT

sed "s/REPLACE_TOKEN/${token}/" "${here}/../tests/helpers/screenshot-mode.php" > "${tmp}/pc-screenshot-mode.php"
docker exec "$container" mkdir -p /var/www/html/wp-content/mu-plugins
docker cp "${tmp}/pc-screenshot-mode.php" "${container}:/var/www/html/wp-content/mu-plugins/pc-screenshot-mode.php"

base="http://localhost:${WP_PORT}"

urlencode() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

# Chrome writes its PNG and then hangs on dbus and xdg lookups that have no
# service behind them in a container-shaped machine, so waiting for the process
# costs the full timeout -- ninety seconds a frame. Watching the file instead
# and killing the browser once it has stopped growing brings it under one.
shoot() {
  local url="$1" out="$2" width="$3" height="$4"
  rm -f "$out"
  local profile; profile="$(mktemp -d)"
  "$chrome" --headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage \
    --hide-scrollbars --force-color-profile=srgb --font-render-hinting=none \
    --user-data-dir="$profile" --window-size="${width},${height}" \
    --force-device-scale-factor=2 --virtual-time-budget=12000 \
    --screenshot="$out" "$url" >/dev/null 2>&1 &
  local pid=$! last=-1 stable=0 waited=0 size
  while [ "$waited" -lt 75 ]; do
    sleep 0.4; waited=$(( waited + 1 ))
    size=$( [ -f "$out" ] && stat -c%s "$out" || echo 0 )
    if [ "$size" -gt 0 ] && [ "$size" -eq "$last" ]; then
      stable=$(( stable + 1 )); [ "$stable" -ge 2 ] && break
    else
      stable=0
    fi
    last="$size"
  done
  sleep 2
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -rf "$profile"
  [ -s "$out" ]
}

count=0
while IFS=$'\t' read -r name path frame click pad margin width height; do
  case "${name:-}" in ''|'#'*) continue;; esac

  query="pc_shot=${token}&pc_frame=$(urlencode "$frame")&pc_pad=${pad}"
  [ "$click" != "-" ] && query="${query}&pc_click=$(urlencode "$click")"

  case "$path" in *\?*) url="${base}${path}&${query}";; *) url="${base}${path}?${query}";; esac

  raw="${tmp}/${name}.raw.png"
  if ! shoot "$url" "$raw" "$width" "$height"; then
    echo "FAILED to render ${name} (${path})" >&2
    exit 1
  fi

  python3 "${here}/crop-to-frame.py" "$raw" "${outdir}/${name}.png" "$margin"
  count=$(( count + 1 ))
done < "$shots"

echo "Wrote ${count} screenshots to ${outdir}"
