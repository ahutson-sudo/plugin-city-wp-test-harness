#!/usr/bin/env bash
# Emit a standalone first-release check script for one plugin.
#
# The emitted file is self-contained on purpose. Andy double-clicks it on his
# Mac, so it must not depend on this repository, on a library, or on anything
# being installed beyond Subversion and the shell — the first moved path would
# otherwise become an undebuggable double-click failure on the one machine where
# debugging is most awkward. That is why this is a generator and not a library.
#
# Usage:
#   scripts/make-first-release-check.sh \
#     --slug plugincity-product-expiry-dates \
#     --version 1.0.0 \
#     --working-copy ~/Desktop/plugincity-product-expiry-dates-svn \
#     --product "Product Expiry Dates" \
#     --output ~/Desktop/plugincity-product-expiry-dates-svn-CHECK-FIRST.command
#
# Optional:
#   --svn-user NAME        username put in the printed commit command
#   --repo-url URL         defaults to https://plugins.svn.wordpress.org/<slug>
#   --attestation PATH     file of "sha256  filename" lines for pictures a human
#                          has actually opened and read
#
# The slug is checked before anything is written, the way plugin-creator refuses
# a bad slug up front: a wrong slug here produces a script that would pass a
# release whose translations can never load.

set -euo pipefail

GENERATOR_VERSION="1.0.0"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SELF_DIR}/first-release-check.template.zsh"

slug=""; version=""; wc=""; product=""; output=""
svn_user="plugincitywp"; repo_url=""; attestation=""

die() { printf 'make-first-release-check: %s\n' "$1" >&2; exit 2; }

while (( $# )); do
  case "$1" in
    --slug)         slug="${2:-}"; shift 2 ;;
    --version)      version="${2:-}"; shift 2 ;;
    --working-copy) wc="${2:-}"; shift 2 ;;
    --product)      product="${2:-}"; shift 2 ;;
    --output)       output="${2:-}"; shift 2 ;;
    --svn-user)     svn_user="${2:-}"; shift 2 ;;
    --repo-url)     repo_url="${2:-}"; shift 2 ;;
    --attestation)  attestation="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)              die "unknown argument: $1" ;;
  esac
done

[[ -n "$slug" ]]    || die "--slug is required"
[[ -n "$version" ]] || die "--version is required"
[[ -n "$wc" ]]      || die "--working-copy is required"
[[ -n "$output" ]]  || die "--output is required"
[[ -f "$TEMPLATE" ]] || die "template missing at ${TEMPLATE}"

# Refuse before writing anything.
#
# The slug is the WordPress.org directory slug as GRANTED, which is not derivable
# from the repository name and is not known until a submission is approved. It is
# also the string the plugin's text domain has to equal, which is the whole
# reason it is an argument rather than a guess.
[[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] \
  || die "slug '$slug' is not a WordPress.org directory slug (lowercase, digits, single hyphens)"
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] \
  || die "version '$version' is not a version number"
[[ -n "$attestation" && ! -f "$attestation" ]] \
  && die "attestation file not found: $attestation"

[[ -z "$product" ]] && product="$slug"
[[ -z "$repo_url" ]] && repo_url="https://plugins.svn.wordpress.org/${slug}"

# Every substitution is a literal replacement of a @@TOKEN@@, done with awk on
# fixed strings so a slug or path containing regex metacharacters cannot rewrite
# the script being generated.
emit() {
  awk -v product="$product" -v version="$version" -v wc="$wc" -v slug="$slug" \
      -v repo="$repo_url" -v att="$attestation" -v user="$svn_user" \
      -v gen="$GENERATOR_VERSION" '
    {
      gsub(/@@PRODUCT@@/, product)
      gsub(/@@VERSION@@/, version)
      gsub(/@@WC@@/, wc)
      gsub(/@@SLUG@@/, slug)
      gsub(/@@REPO_URL@@/, repo)
      gsub(/@@ATTESTATION@@/, att)
      gsub(/@@SVN_USER@@/, user)
      gsub(/@@GENERATOR_VERSION@@/, gen)
      print
    }
  ' "$TEMPLATE"
}

tmp="$(mktemp)"
emit > "$tmp"

if grep -q '@@[A-Z_]*@@' "$tmp"; then
  rm -f "$tmp"
  die "unsubstituted token left in the output: $(grep -o '@@[A-Z_]*@@' "$tmp" 2>/dev/null | sort -u | tr '\n' ' ')"
fi

# A generated script that cannot be parsed is worse than none, because the
# failure shows up on a double-click.
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$tmp" || { rm -f "$tmp"; die "generated script failed to parse"; }
else
  printf 'make-first-release-check: zsh not present, skipping the parse check\n' >&2
fi

mkdir -p "$(dirname "$output")"
mv "$tmp" "$output"
chmod +x "$output"

printf 'wrote %s\n' "$output"
printf '  slug         %s\n' "$slug"
printf '  version      %s\n' "$version"
printf '  working copy %s\n' "$wc"
printf '  repository   %s\n' "$repo_url"
if [[ -n "$attestation" ]]; then
  printf '  attestation  %s (%s picture(s))\n' "$attestation" "$(grep -cvE '^[[:space:]]*(#|$)' "$attestation")"
else
  printf '  attestation  none supplied — the script will say so rather than imply the pictures were read\n'
fi
