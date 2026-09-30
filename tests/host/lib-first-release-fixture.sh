#!/usr/bin/env bash
# Build a throwaway WordPress.org-shaped SVN repository and a staged first
# release inside it, from nothing.
#
# Why this exists rather than copying a real working copy: a real one only exists
# after somebody has staged a release by hand, so the check could only ever be
# tested after the thing it is meant to guard had already been built — and it
# could not be tested at all for a plugin whose repository does not exist yet,
# which is every plugin before its submission is approved. Free Shipping Bar and
# Order Cancellation are both in exactly that position.
#
# svnadmin create over file:// needs no network, no credentials and no
# WordPress.org, and it exercises the real `svn add` and `svn status` paths that
# two of the checks read all their signal from.
#
# Sourced by first-release-check.sh. Sets FIXTURE_WC and FIXTURE_URL.

fixture_slug() { printf 'plugincity-fixture-plugin'; }
fixture_version() { printf '1.0.0'; }

# A minimal but genuine plugin: a real header block, a readme with a stable tag
# and N captions, translatable strings, a .pot with an X-Domain, and N pictures.
fixture_build() {
  local root="$1" shots="${2:-3}"
  local slug; slug="$(fixture_slug)"
  local ver; ver="$(fixture_version)"

  local repo="${root}/repo" wc="${root}/wc"
  mkdir -p "$repo" "$wc"

  svnadmin create "$repo"
  FIXTURE_URL="file://${repo}"
  svn mkdir -q --parents -m "layout" \
    "${FIXTURE_URL}/trunk" "${FIXTURE_URL}/tags" "${FIXTURE_URL}/assets"
  svn checkout -q "${FIXTURE_URL}" "$wc"
  FIXTURE_WC="$wc"

  mkdir -p "${wc}/trunk/includes" "${wc}/trunk/languages" "${wc}/tags/${ver}"

  cat > "${wc}/trunk/${slug}.php" <<PHP
<?php
/**
 * Plugin Name: PluginCity Fixture Plugin for WooCommerce
 * Description: A fixture. It does nothing.
 * Version: ${ver}
 * Text Domain: ${slug}
 * Domain Path: /languages
 * License: GPL-2.0-or-later
 */

defined( 'ABSPATH' ) || exit;

require_once __DIR__ . '/includes/bootstrap.php';
PHP

  cat > "${wc}/trunk/includes/bootstrap.php" <<PHP
<?php
defined( 'ABSPATH' ) || exit;

function pcfx_load_textdomain(): void {
	load_plugin_textdomain(
		'${slug}',
		false,
		dirname( plugin_basename( __FILE__ ) ) . '/languages'
	);
}

function pcfx_notice(): string {
	return __( 'A fixture notice.', '${slug}' );
}

function pcfx_other(): string {
	return esc_html__( 'Another string.', '${slug}' );
}
PHP

  cat > "${wc}/trunk/uninstall.php" <<'PHP'
<?php
defined( 'WP_UNINSTALL_PLUGIN' ) || exit;
PHP

  {
    printf '=== PluginCity Fixture Plugin for WooCommerce ===\n'
    printf 'Contributors: plugincitywp\n'
    printf 'Requires at least: 6.7\n'
    printf 'Tested up to: 7.1\n'
    printf 'Requires PHP: 8.1\n'
    printf 'Stable tag: %s\n' "$ver"
    printf 'License: GPLv2 or later\n\n'
    printf 'A fixture. It does nothing.\n\n'
    printf '== Description ==\n\nA fixture, priced in dollars: $19.00.\n\n'
    printf '== Screenshots ==\n\n'
    local i
    for (( i = 1; i <= shots; i++ )); do
      printf '%d. Fixture screenshot %d.\n' "$i" "$i"
    done
    printf '\n== Changelog ==\n\n= %s =\n* First public release.\n' "$ver"
  } > "${wc}/trunk/readme.txt"

  {
    printf '# Copyright (C) 2026 PluginCity\nmsgid ""\nmsgstr ""\n'
    printf '"Project-Id-Version: PluginCity Fixture Plugin %s\\n"\n' "$ver"
    printf '"Content-Type: text/plain; charset=UTF-8\\n"\n'
    printf '"X-Domain: %s\\n"\n\n' "$slug"
    printf 'msgid "A fixture notice."\nmsgstr ""\n'
  } > "${wc}/trunk/languages/${slug}.pot"

  cp -R "${wc}/trunk/." "${wc}/tags/${ver}/"

  local i
  for (( i = 1; i <= shots; i++ )); do
    fixture_png "${wc}/assets/screenshot-${i}.png" $(( 200 + i )) $(( 100 + i ))
  done
  fixture_png "${wc}/assets/banner-772x250.png" 772 250
  fixture_png "${wc}/assets/banner-1544x500.png" 1544 500
  fixture_png "${wc}/assets/icon-128x128.png" 128 128
  fixture_png "${wc}/assets/icon-256x256.png" 256 256

  ( cd "$wc" && svn add -q --force trunk tags assets --no-ignore )
}

# A real PNG at an exact pixel size, written without ImageMagick or sips so the
# fixture builds the same on a Mac and in CI. One IHDR, one zlib-stored IDAT of
# a single-colour image, one IEND, with CRCs computed properly — the check reads
# width and height straight out of the IHDR, so these have to be genuine.
fixture_png() {
  local out="$1" w="$2" h="$3"
  python3 - "$out" "$w" "$h" <<'PY'
import sys, struct, zlib
out, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

def chunk(tag, data):
    return (struct.pack('>I', len(data)) + tag + data
            + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
raw = b''.join(b'\x00' + bytes([40, 80, 120]) * w for _ in range(h))
png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
       + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))
with open(out, 'wb') as fh:
    fh.write(png)
PY
}

# An attestation listing every staged picture, as though somebody had opened them.
fixture_attestation() {
  local wc="$1" out="$2"
  : > "$out"
  local f
  for f in "${wc}"/assets/screenshot-*.png; do
    printf '%s  %s  read-by-fixture 2026-09-30\n' \
      "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$(basename "$f")" >> "$out"
  done
}
