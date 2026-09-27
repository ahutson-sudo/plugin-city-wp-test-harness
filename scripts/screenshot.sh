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
#                    {{kind.key}} placeholders for ids the seed created, and may
#                    be prefixed with who is looking: 'visitor:/cart/' for a
#                    shopper who has not signed in, 'jo:/my-account/' for the
#                    login jo. Without a prefix, the administrator
#   frame-selector   CSS selector list; the union of every match is the crop
#   click-selector   what to do before the frame is measured, or '-'. One step,
#                    or several separated by '|'. A step is a selector to click;
#                    a step written 'selector ::= value' types the value into
#                    that field instead. Every step has to happen or the shot is
#                    refused and the step is named
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
#
# Nothing is saved unless the page says it finished drawing itself. A shot whose
# screen loads its own content -- over admin-ajax, the REST API, WooCommerce's
# Store API -- is refused if any of that came back an error, if any of it had
# not answered when the shutter opened, or if the subject moved after it was
# measured. The run stops and names the reason, because a warning in a log is
# read by nobody and a file that exists is published. A request that is known to
# fail and known to change nothing can be excused one shot at a time; see the
# allow lines below.
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

# Who a shot is taken as when its path does not say. Most of a set is wp-admin,
# so the administrator is the default and the storefront shots are the ones that
# have to ask.
default_viewer=admin
nobody=visitor

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

# A screen may ask for something that is never going to arrive and draw itself
# perfectly anyway. WooCommerce 11.1 does it on the cart: the mini-cart block in
# a block theme's header is not rendered on the cart page, but the script module
# it registers is still loaded, and that module asks for a REST route it was
# never told the address of. The request 404s, retries, and changes nothing you
# could photograph.
#
# So a shot list may say so, in a line of its own, and only about one shot:
#
#   allow<TAB>shot-name<TAB>url-fragment<TAB>why it does not matter
#
# All four fields are required, the reason because the next person to read the
# file is the one who has to decide whether it is still true.
#
# This is the only way past the check, and it is deliberately narrow. It names
# one request on one screen rather than a kind of error anywhere, and it has to
# keep being needed: a fragment nothing on the page asks for any more refuses the
# shot, because an exception that has stopped applying is a hole in the check
# that nobody knows is open.
declare -A allow_for=()
while IFS=$'\t' read -r keyword who fragment reason; do
  [ "${keyword:-}" = "allow" ] || continue
  if [ -z "${who:-}" ] || [ -z "${fragment:-}" ] || [ -z "${reason:-}" ]; then
    echo "An allow line needs all four fields: allow, the shot's name, a piece of the URL, and why it does not matter." >&2
    exit 1
  fi
  allow_for["$who"]="${allow_for["$who"]:-}${fragment}"$'\n'
done < "$shots"

for who in "${!allow_for[@]}"; do
  if ! awk -F'\t' -v n="$who" '$1==n{found=1} END{exit !found}' "$shots"; then
    echo "The shot list allows a request on '${who}', and has no shot called that." >&2
    exit 1
  fi
done

# Split 'visitor:/cart/' into who is looking and what they are looking at. A
# path is site-relative and therefore begins with a slash, so anything before
# one is a login and a prefix cannot be mistaken for part of a URL.
shot_viewer=''
shot_path=''
split_viewer() {
  case "$1" in
    /*)
      shot_viewer="$default_viewer"
      shot_path="$1"
      ;;
    *:/*)
      shot_viewer="${1%%:*}"
      shot_path="${1#*:}"
      ;;
    *)
      echo "'$1' is neither a site-relative path nor viewer:/path -- a path starts with a slash." >&2
      exit 1
      ;;
  esac
}

# The columns are positional, so one tab too few slides every one of them along
# and the first thing to notice used to be Python failing to read the word
# 'margin' as a number -- a traceback from the cropper, about a shot it names
# nowhere, for a mistake in the shot list.
whole_number() {
  case "$2" in
    ''|*[!0-9]*)
      echo "${1}: '${2}' is not a whole number, so the columns have slipped. Check the tabs on that line." >&2
      exit 1
      ;;
  esac
}

shot_url() {
  local path="$1" extra="${2:-}" viewer="$3" query
  query="pc_shot=${token}&pc_as=$(urlencode "$viewer")${extra}"
  case "$path" in
    *\?*) printf '%s%s&%s' "$base" "$path" "$query" ;;
    *)    printf '%s%s?%s' "$base" "$path" "$query" ;;
  esac
}

allowed_params() {
  local fragment
  while IFS= read -r fragment; do
    [ -n "$fragment" ] || continue
    printf '&pc_allow%%5B%%5D=%s' "$(urlencode "$fragment")"
  done <<< "${allow_for["$1"]:-}"
  return 0
}

# Ask the server, with curl rather than with a browser, whether it really did
# sign this shot in as the person the shot list asked for.
#
# This is the one moment in a capture when something can read a header, and it is
# worth using: the browser gets its session from Set-Cookie on exactly this
# request, so a capture whose session is not going to work can be stopped here
# instead of producing a picture of a screen that could not load its own
# content. A shot list naming a user the shop has never heard of would otherwise
# be photographed signed out, which looks like a shop with an empty basket.
check_session() {
  local url="$1" name="$2" viewer="$3" headers said cookie
  headers="$(curl -sS -D - -o /dev/null --max-time 30 "$url" 2>/dev/null | tr -d '\r' | tr 'A-Z' 'a-z' || true)"

  # No response at all is left to the real shot below, whose message names the
  # URL and the file it was going to write.
  [ -n "$headers" ] || return 0

  if printf '%s' "$headers" | grep -q '^x-pc-shot-error:'; then
    echo "${name} cannot be photographed as ${viewer}: $(printf '%s' "$headers" | sed -n 's/^x-pc-shot-error: *//p' | head -n1)" >&2
    exit 1
  fi

  said="$(printf '%s' "$headers" | sed -n 's/^x-pc-shot-viewer: *//p' | head -n1)"
  if [ -z "$said" ]; then
    echo "${name}: the site did not answer as the screenshot shim, so nothing has been signed in." >&2
    echo "  Either the must-use plugin is not in place or the token on the URL did not match." >&2
    exit 1
  fi
  if [ "$said" != "$(printf '%s' "$viewer" | tr 'A-Z' 'a-z')" ]; then
    echo "${name}: asked to be photographed as ${viewer}, and the site signed in ${said}." >&2
    exit 1
  fi

  cookie="$(printf '%s' "$headers" | sed -n 's/^x-pc-shot-session: *//p' | head -n1)"
  if [ "$viewer" = "$nobody" ]; then
    if [ -n "$cookie" ]; then
      echo "${name}: asked for a signed-out picture and the site sent a session cookie anyway." >&2
      exit 1
    fi
    return 0
  fi

  if [ -z "$cookie" ]; then
    echo "${name}: the site signed ${viewer} in without saying which cookie carries the session." >&2
    exit 1
  fi
  if ! printf '%s' "$headers" | grep -q "^set-cookie: *${cookie}="; then
    echo "${name}: the site signed ${viewer} in for its own render and sent the browser no ${cookie}." >&2
    echo "  Everything the page loads for itself would arrive anonymous. Nothing has been photographed." >&2
    exit 1
  fi
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
# The administrator's pass is what writes any of that, which is why a shot taken
# as somebody else is warmed twice: once as the administrator so the site has
# settled, and once as the person who will be photographed so that the session
# check below is asking about the request the browser is going to make.
warm_count=0
while IFS=$'\t' read -r _name _path _rest; do
  case "${_name:-}" in ''|'#'*|allow) continue;; esac
  split_viewer "$_path"
  case "$shot_path" in
    *'{{'*|*'}}'*) shot_path="$(resolve_path "$shot_path")" || exit 1;;
  esac
  _as_admin="$(shot_url "$shot_path" '' "$default_viewer")"
  curl -fsS -o /dev/null --max-time 30 "$_as_admin" 2>/dev/null || true
  if [ "$shot_viewer" = "$default_viewer" ]; then
    check_session "$_as_admin" "$_name" "$shot_viewer"
  else
    check_session "$(shot_url "$shot_path" '' "$shot_viewer")" "$_name" "$shot_viewer"
  fi
  warm_count=$(( warm_count + 1 ))
done < "$shots"
echo "Warmed ${warm_count} pages."

# Chrome writes its PNG and then hangs on dbus and xdg lookups that have no
# service behind them in a container-shaped machine, so waiting for the process
# costs the full timeout -- ninety seconds a frame. Watching the file instead
# and killing the browser once it has stopped growing brings it under one.
shoot() {
  local url="$1" out="$2" width="$3" height="$4"
  rm -f "$out"
  local profile; profile="$(mktemp -d)"
  # A profile per shot, thrown away with it. Session cookies do not survive a
  # browser restart, so each shot arrives with no session until the page it
  # renders gives it one -- which is what keeps a signed-out shot signed out
  # however many signed-in shots came before it.
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
  # Killed mid-write, Chrome can leave a file behind in the profile after the
  # directory listing has been read, so this is allowed to fail: a leftover
  # profile in a temporary directory is not worth a line of output.
  rm -rf "$profile" 2>/dev/null || true
  [ -s "$out" ]
}

count=0
# 'caption' last so a ninth column lands there rather than being appended to
# height, which is the one field a stray tab would corrupt silently.
while IFS=$'\t' read -r name path frame click pad margin width height caption; do
  case "${name:-}" in ''|'#'*|allow) continue;; esac

  split_viewer "$path"
  path="$shot_path"
  case "$path" in
    *'{{'*|*'}}'*) path="$(resolve_path "$path")" || exit 1;;
  esac

  whole_number "$name" "$pad"
  whole_number "$name" "$margin"
  whole_number "$name" "$width"
  whole_number "$name" "$height"

  extra="&pc_frame=$(urlencode "$frame")&pc_pad=${pad}$(allowed_params "$name")"
  [ "$click" != "-" ] && extra="${extra}&pc_click=$(urlencode "$click")"
  url="$(shot_url "$path" "$extra" "$shot_viewer")"

  # Last run's picture goes before this run's is attempted. A refusal that left
  # the old file in place would leave a set looking complete and current when
  # one of its screens had not been photographed at all.
  rm -f "${outdir}/${name}.png" "${outdir}/${name}.rejected.png"

  raw="${tmp}/${name}.raw.png"
  if ! shoot "$url" "$raw" "$width" "$height"; then
    echo "FAILED to render ${name} (${path})" >&2
    exit 1
  fi

  if ! python3 "${here}/crop-to-frame.py" "$raw" "${outdir}/${name}.png" "$margin"; then
    cp "$raw" "${outdir}/${name}.rejected.png"
    echo "REFUSED ${name} (${shot_viewer}: ${path}) -- nothing was saved." >&2
    echo "  The render it refused is kept at ${outdir}/${name}.rejected.png, twice final size." >&2
    exit 1
  fi
  count=$(( count + 1 ))
done < "$shots"

echo "Wrote ${count} screenshots to ${outdir}"
