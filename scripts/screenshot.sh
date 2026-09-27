#!/usr/bin/env bash
# Photograph a running harness, one shot per line of a plugin's shot list.
#
#   scripts/screenshot.sh <shots.tsv> [output-dir]
#
# The shot list is the plugin's, not the harness's: which screens sell a plugin
# is an editorial decision and the only part of this that cannot be automated.
# Columns, tab separated, '#' comments and blank lines ignored:
#
#   name  path  frame-selector  click-selector  pad  margin  width  height  caption
#
#   name             output file stem, e.g. screenshot-1
#   path             site-relative, e.g. /product/a-book/ or
#                    /wp-admin/admin.php?page=my-settings. May carry
#                    {{kind.key}} placeholders for ids the seed created
#   frame-selector   CSS selector list; the union of every match is the crop
#   click-selector   clicked before the frame is measured, or '-'
#   pad              page pixels kept round the subject
#   margin           flat pixels of page colour added after cropping
#   width height     viewport in CSS pixels; height only has to be enough to
#                    hold the subject, since the crop decides the result
#   caption          optional; the readme caption this shot answers. Nothing
#                    here reads it, scripts/contact-sheet.py does
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

# A shot list used to carry the ids the seed happened to mint -- post=11, id=31
# -- which made the seed and the shot list one artefact filed in two places. A
# reseeded shop renumbers them and nothing fails: the run photographs whatever
# is at that id now, or a 404, and the pictures come back wrong rather than
# missing. So a seed records what it made and a path says
# {{product.the-salt-path-home}} instead.
#
# tests/helpers/seed-common.php writes this file; the path is spelled out in
# both places and each says so.
seed_ids_file=/var/www/html/pc-seed-ids.json
seed_ids_json=''
if docker exec "$container" test -f "$seed_ids_file" >/dev/null 2>&1; then
  seed_ids_json="$(docker exec "$container" cat "$seed_ids_file")"
fi

# The failure has to be loud. Rendering a URL with the braces still in it is the
# one outcome worth engineering against: it answers 404, gets photographed
# successfully, and then the crop fails for a reason that has nothing to do with
# the cause.
resolve_path() {
  python3 - "$1" "$seed_ids_json" <<'PY'
import json
import re
import sys

path, raw = sys.argv[1], sys.argv[2]
ids = json.loads(raw) if raw.strip() else {}


def resolve(match):
    token = match.group(1).strip()
    shown = '{{' + token + '}}'
    kind, dot, key = token.partition('.')

    if not dot or not kind or not key:
        sys.exit(shown + ' is not kind.key -- write it like {{product.some-slug}}')

    of_that_kind = ids.get(kind) or {}
    if key not in of_that_kind:
        known = ', '.join(sorted(of_that_kind)) or '(nothing of that kind)'
        sys.exit(
            'Nothing recorded for ' + shown + '.\n'
            '  Recorded under ' + kind + ': ' + known + '\n'
            "  The seed needs seed_record_id( '" + kind + "', '" + key + "', $id ),"
            ' and seed_finish() to write the file.'
        )

    return str(of_that_kind[key])


out = re.sub(r'\{\{([^{}]*)\}\}', resolve, path)

if '{{' in out or '}}' in out:
    sys.exit('Braces left over in ' + out + ': a placeholder is malformed.')

print(out)
PY
}

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

# Every path is rendered once before any of them is photographed, and the
# pictures from that pass are thrown away.
#
# A first signed-in view of a site is not like the views after it. WordPress and
# WooCommerce both write things to the database the first time somebody who may
# edit them looks at a page -- a block theme with no navigation menu gets one
# persisted from the theme's fallback, and WooCommerce's header icons are hooked
# in around it -- so a storefront shot taken on the first pass came back with a
# header fourteen pixels shorter than the identical shot on the second. Nothing
# failed. The two sets simply disagreed, and whichever had been committed was
# the one nobody else could reproduce.
#
# Warming every path rather than just the home page is deliberate. What gets
# written on a first view is WordPress's business and changes between releases,
# so the only warm-up that stays correct is the set itself: whatever a shot's own
# page settles on being viewed, it has settled before the shutter opens.
#
# The token has to be on the request. An anonymous view writes none of this,
# which is why fetching the home page five times as a visitor changes nothing.
# Failures are ignored: a page that cannot be served will fail its real shot
# below, and that message names the URL and the shot.
warm_count=0
while IFS=$'\t' read -r _name _path _rest; do
  case "${_name:-}" in ''|'#'*) continue;; esac
  case "$_path" in
    *'{{'*|*'}}'*) _path="$(resolve_path "$_path")" || exit 1;;
  esac
  case "$_path" in
    *\?*) _warm="${base}${_path}&pc_shot=${token}";;
    *)    _warm="${base}${_path}?pc_shot=${token}";;
  esac
  curl -fsS -o /dev/null --max-time 30 "$_warm" 2>/dev/null || true
  warm_count=$(( warm_count + 1 ))
done < "$shots"
echo "Warmed ${warm_count} pages."

count=0
# 'caption' last so a ninth column lands there rather than being appended to
# height, which is the one field a stray tab would corrupt silently.
while IFS=$'\t' read -r name path frame click pad margin width height caption; do
  case "${name:-}" in ''|'#'*) continue;; esac

  case "$path" in
    *'{{'*|*'}}'*) path="$(resolve_path "$path")" || exit 1;;
  esac

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
