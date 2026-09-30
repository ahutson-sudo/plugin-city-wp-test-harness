#!/usr/bin/env bash
# Prove that the generated first-release check refuses each fault it exists for,
# that the right check refuses each one, and that no check has nothing behind it.
#
# The reason this asserts on the check ID and not merely on a refusal: when this
# suite's predecessor was built by hand for Product Expiry, three of its eight
# faults tripped two or three sections at once. A suite that greps for "STOP"
# passes when the intended check is dead and a neighbour happens to fire, which
# is the vacuous-guard condition the whole range has been chasing. So every case
# below names the ID it must see.
#
# The coverage gate then refuses to pass while any failable check has no fault
# behind it. That is what keeps the answer true after somebody adds a check —
# otherwise this suite stops being complete the moment it stops being looked at.
#
# It needs no network, no Docker, no WordPress.org and no plugin: the fixture is
# an svnadmin repository built from nothing over file://.
#
# Two things this does NOT prove, which matter as much as what it does:
#   * It does not prove the checks are SUFFICIENT. Coverage accounting closes the
#     gap between the checks and the faults, not the gap to the mistake nobody
#     has imagined. The table grows from real incidents, which is why the two
#     faults that actually bit this range — a caption for a screen that does not
#     exist, and a plugin inside a wrapping folder — are worth more in it than
#     any invented one.
#   * It does not transfer to the sibling stable-tag guard in the plugin repos.
#     That one runs in CI against a repository; this runs against a Subversion
#     working copy. The METHOD transfers — build the fixture, inject the fault,
#     assert the specific refusal, account for the coverage — and it is the
#     method that "nothing proves its check works" is asking for. The script
#     does not.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SELF_DIR}/../.." && pwd)"
GENERATOR="${REPO_ROOT}/scripts/make-first-release-check.sh"

# shellcheck source=lib-first-release-fixture.sh
source "${SELF_DIR}/lib-first-release-fixture.sh"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH}"' EXIT

SLUG="$(fixture_slug)"
VER="$(fixture_version)"
SHOTS=3

failures=0
declare -a COVERED=()

need() {
  for tool in svn svnadmin zsh python3 shasum; do
    command -v "$tool" >/dev/null 2>&1 || {
      printf 'first-release-check: %s is required and not installed\n' "$tool" >&2
      exit 2
    }
  done
}

# Build a fresh fixture and generate a check against it. A new fixture per fault
# rather than undoing the last one: an undo that silently half-worked would make
# the next case meaningless.
build() {
  local dir="$1" shots="${2:-$SHOTS}"
  mkdir -p "$dir"
  fixture_build "$dir" "$shots" >/dev/null 2>&1
  fixture_attestation "${FIXTURE_WC}" "${dir}/attestation.txt"
  "$GENERATOR" \
    --slug "$SLUG" --version "$VER" --working-copy "${FIXTURE_WC}" \
    --product "PluginCity Fixture Plugin" --repo-url "${FIXTURE_URL}" \
    --attestation "${dir}/attestation.txt" \
    --output "${dir}/CHECK-FIRST.command" >/dev/null
  CHECK="${dir}/CHECK-FIRST.command"
}

run_check() { zsh "$CHECK" </dev/null 2>&1 || true; }

ids_in() { printf '%s\n' "$1" | grep -oE '^\s*\*\* \[[A-Z-]+\]' | grep -oE '[A-Z-]+' | sort -u; }

# ---------------------------------------------------------------- the cases
# A case is: a fault, and the id that must refuse it.
expect_refusal() {
  local name="$1" want="$2" fn="$3" shots="${4:-$SHOTS}"
  local dir="${SCRATCH}/case-$(printf '%s' "$name" | tr -cd 'a-z0-9')"
  build "$dir" "$shots"

  # A fault that fails to apply would leave a clean tree and read as a MISSED
  # check, blaming the script for the suite's own bug. So it is reported as what
  # it is.
  local applied=0
  ( cd "${FIXTURE_WC}" && "$fn" ) || applied=$?
  if (( applied != 0 )); then
    printf '  SUITE    %-34s fault could not be applied (status %s)\n' "$name" "$applied"
    failures=$(( failures + 1 ))
    return
  fi

  local out; out="$(run_check)"
  local got; got="$(ids_in "$out")"

  if ! printf '%s\n' "$out" | grep -q '^STOP'; then
    printf '  MISSED   %-34s did not refuse at all\n' "$name"
    failures=$(( failures + 1 ))
    return
  fi
  if ! printf '%s\n' "$got" | grep -qx "$want"; then
    printf '  WRONG    %-34s refused, but not by [%s]; saw [%s]\n' \
      "$name" "$want" "$(printf '%s' "$got" | tr '\n' ' ' | sed 's/ $//')"
    printf '           a refusal by a neighbouring check is how a dead check hides\n'
    failures=$(( failures + 1 ))
    return
  fi
  printf '  ok       %-34s [%s]\n' "$name" "$want"
  while read -r id; do [[ -n "$id" ]] && COVERED+=("$id"); done <<< "$got"
}

# --- section 1
f_url() { :; }   # handled specially below

# --- section 2: the three parts
f_trunk_empty()  { svn revert -q -R trunk && rm -rf trunk; mkdir trunk; }
f_tag_empty()    { svn revert -q -R tags && rm -rf "tags/$VER"; }
f_assets_empty() { svn revert -q -R assets && rm -f assets/*; }
f_stray()        { printf 'notes\n' > trunk/LEFTOVER.txt; }

# --- section 3: layout
f_mainfile() { svn revert -q "trunk/${SLUG}.php" && rm -f "trunk/${SLUG}.php"; }
f_wrapped()  {
  svn revert -q "trunk/${SLUG}.php"
  mkdir -p "trunk/${SLUG}"
  mv "trunk/${SLUG}.php" "trunk/${SLUG}/${SLUG}.php"
  svn add -q "trunk/${SLUG}"
}
f_readme()   { svn revert -q trunk/readme.txt && rm -f trunk/readme.txt; }

# --- section 4
f_tagdiff() { printf '\nAn extra line only in trunk.\n' >> trunk/readme.txt; }

# --- section 5: the text domain
f_domain()      { sed -i.bak "s/ \* Text Domain: ${SLUG}/ * Text Domain: fixture-plugin/" "trunk/${SLUG}.php" && rm -f "trunk/${SLUG}.php.bak"; }
f_domain_code() { sed -i.bak "s/'A fixture notice.', '${SLUG}'/'A fixture notice.', 'fixture-plugin'/" trunk/includes/bootstrap.php && rm -f trunk/includes/bootstrap.php.bak; }
f_domain_load() { sed -i.bak "s/^\t\t'${SLUG}',/\t\t'fixture-plugin',/" trunk/includes/bootstrap.php && rm -f trunk/includes/bootstrap.php.bak; }
f_pot()         { svn revert -q "trunk/languages/${SLUG}.pot" && rm -f "trunk/languages/${SLUG}.pot"; }
f_pot_domain()  { sed -i.bak "s/X-Domain: ${SLUG}/X-Domain: fixture-plugin/" "trunk/languages/${SLUG}.pot" && rm -f "trunk/languages/${SLUG}.pot.bak"; }

# --- section 6
f_stable() { sed -i.bak "s/^Stable tag: ${VER}/Stable tag: 9.9.9/" trunk/readme.txt && rm -f trunk/readme.txt.bak; }

# --- section 7: captions and pictures
f_cap_orphan()  { svn revert -q assets/screenshot-2.png && rm -f assets/screenshot-2.png; }
f_shot_orphan() { fixture_png assets/screenshot-9.png 210 110 && svn add -q assets/screenshot-9.png; }

# --- section 8: artwork
f_art_missing() { svn revert -q assets/banner-772x250.png && rm -f assets/banner-772x250.png; }
f_art_size()    { fixture_png assets/banner-772x250.png 100 40; }

# --- section 9: currency and the attestation
f_gbp()    { sed -i.bak 's/\$19\.00/£19.00/' trunk/readme.txt && rm -f trunk/readme.txt.bak; }
f_attest() { fixture_png assets/screenshot-1.png 640 480; }

# --- section 10
f_devfiles() { mkdir -p trunk/vendor && printf '<?php\n' > trunk/vendor/autoload.php && svn add -q trunk/vendor; }

# ------------------------------------------------------------------- run it
need
printf '\nFirst-release check — fault suite\n'
printf '=================================\n'
printf 'Fixture: an svnadmin repository over file://, built from nothing.\n'
printf 'No network, no Docker, no plugin, no WordPress.org.\n\n'

printf 'Baseline — a correctly staged first release must PASS:\n'
build "${SCRATCH}/baseline"
BASE_OUT="$(run_check)"
if printf '%s\n' "$BASE_OUT" | grep -q '^PASS'; then
  printf '  ok       clean fixture passes\n\n'
else
  printf '  FAILED   the clean fixture does not pass, so every result below is meaningless\n'
  printf '%s\n' "$BASE_OUT" | sed 's/^/           /'
  exit 1
fi

printf 'Each fault must be refused, and refused BY THE NAMED CHECK:\n'

# URL is the one case that is about how the script was generated rather than
# about the working copy, so it gets its own build.
URLDIR="${SCRATCH}/case-url"
build "$URLDIR"
"$GENERATOR" --slug "$SLUG" --version "$VER" --working-copy "${FIXTURE_WC}" \
  --product "PluginCity Fixture Plugin" \
  --repo-url "file:///nonexistent-repository" \
  --output "${URLDIR}/CHECK-WRONG-URL.command" >/dev/null
CHECK="${URLDIR}/CHECK-WRONG-URL.command"
URL_OUT="$(run_check)"
if printf '%s\n' "$URL_OUT" | grep -q '^STOP' && ids_in "$URL_OUT" | grep -qx URL; then
  printf '  ok       %-34s [URL]\n' "working copy is a different repository"
  COVERED+=("URL")
else
  printf '  MISSED   %-34s\n' "working copy is a different repository"
  failures=$(( failures + 1 ))
fi

expect_refusal "trunk staged empty"                TRUNK-EMPTY  f_trunk_empty
expect_refusal "tag staged empty"                  TAG-EMPTY    f_tag_empty
expect_refusal "assets staged empty"               ASSETS-EMPTY f_assets_empty
expect_refusal "an unversioned file left behind"   STRAY        f_stray
expect_refusal "no main plugin file in trunk"      MAINFILE     f_mainfile
expect_refusal "plugin inside a wrapping folder"   WRAPPED      f_wrapped
expect_refusal "readme.txt missing"                README       f_readme
expect_refusal "trunk and the tag differ"          TAGDIFF      f_tagdiff
expect_refusal "text domain is not the slug"       DOMAIN       f_domain
expect_refusal "a string names another domain"     DOMAIN-CODE  f_domain_code
expect_refusal "textdomain loader names another"   DOMAIN-LOAD  f_domain_load
expect_refusal "translation template missing"      POT          f_pot
expect_refusal "template X-Domain is wrong"        POT-DOMAIN   f_pot_domain
expect_refusal "stable tag is not the version"     STABLE       f_stable
expect_refusal "caption with no picture"           CAP-ORPHAN   f_cap_orphan
expect_refusal "picture with no caption"           SHOT-ORPHAN  f_shot_orphan
expect_refusal "required banner missing"           ART-MISSING  f_art_missing
expect_refusal "banner is not the size it claims"  ART-SIZE     f_art_size
expect_refusal "sterling in the readme"            GBP          f_gbp
expect_refusal "a picture changed after it was read" ATTEST     f_attest
expect_refusal "vendor/ riding along in trunk"     DEVFILES     f_devfiles

# ------------------------------------------------------- the coverage gate
printf '\nCoverage — every failable check must have a fault behind it:\n'
CHECK="${SCRATCH}/baseline/CHECK-FIRST.command"
ALL="$(zsh "$CHECK" --list-checks | grep -v ' informational$' | sort -u)"
INFO="$(zsh "$CHECK" --list-checks | grep ' informational$' | awk '{print $1}' | sort -u)"
HAVE="$(printf '%s\n' "${COVERED[@]:-}" | grep -E '^[A-Z-]+$' | sort -u)"

total=$(printf '%s\n' "$ALL" | grep -c .)
have=$(printf '%s\n' "$HAVE" | grep -c . || true)
UNCOVERED="$(comm -23 <(printf '%s\n' "$ALL") <(printf '%s\n' "$HAVE"))"

printf '  checks the script can fail: %s\n' "$total"
printf '  checks proved to refuse:    %s\n' "$have"
if [[ -n "$INFO" ]]; then
  printf '  declared informational (no fault required, and the exemption is visible):\n'
  printf '%s\n' "$INFO" | sed 's/^/     /'
fi

if [[ -n "$UNCOVERED" ]]; then
  printf '  ** these checks have NOTHING proving they refuse anything:\n'
  printf '%s\n' "$UNCOVERED" | sed 's/^/       /'
  printf '     Add a fault for each, or the check is decoration.\n'
  failures=$(( failures + 1 ))
else
  printf '  ok       every failable check was proved to refuse its own fault\n'
fi

UNKNOWN="$(comm -13 <(printf '%s\n' "$ALL") <(printf '%s\n' "$HAVE"))"
if [[ -n "$UNKNOWN" ]]; then
  printf '  ** a fault produced an id the script does not declare: %s\n' \
    "$(printf '%s' "$UNKNOWN" | tr '\n' ' ')"
  failures=$(( failures + 1 ))
fi

# ------------------------------------------- the gate, and the generator
# A coverage gate nobody has watched refuse is a gate that might not. This
# declares a check that nothing can trigger and asserts the gate names it.
printf '\nThe coverage gate itself must refuse an unproved check:\n'
GATEDIR="${SCRATCH}/gate"; mkdir -p "$GATEDIR"
sed 's/^  URL          /  NEVER        "a check with no fault behind it"\n  URL          /' \
  "${SCRATCH}/baseline/CHECK-FIRST.command" > "${GATEDIR}/CHECK-GATE.command"
GATE_ALL="$(zsh "${GATEDIR}/CHECK-GATE.command" --list-checks | grep -v ' informational$' | sort -u)"
GATE_UNCOVERED="$(comm -23 <(printf '%s\n' "$GATE_ALL") <(printf '%s\n' "$HAVE"))"
if printf '%s\n' "$GATE_UNCOVERED" | grep -qx NEVER; then
  printf '  ok       an undeclared-fault check is reported as unproved [NEVER]\n'
else
  printf '  ** the coverage gate did not notice a check with no fault behind it\n'
  failures=$(( failures + 1 ))
fi

# An id used in the code but absent from the declaration is a hard error rather
# than a silent omission, which is what keeps --list-checks honest. The
# declaration is removed AND the fault is triggered, since an id that is never
# reached would prove nothing.
printf '  checking that an undeclared id is a hard error:\n'
UNDECL="${GATEDIR}/CHECK-UNDECLARED.command"
sed -e 's|^REPO_URL=.*|REPO_URL="file:///nonexistent-repository"|' \
    -e 's/^  URL          "working copy points at the expected repository"$//' \
  "${SCRATCH}/baseline/CHECK-FIRST.command" > "$UNDECL"
UNDECL_OUT="$(zsh "$UNDECL" </dev/null 2>&1 || true)"
if printf '%s\n' "$UNDECL_OUT" | grep -q 'INTERNAL ERROR: undeclared check id'; then
  printf '  ok       using an id that is not declared stops the script\n'
else
  printf '  ** an undeclared check id did not stop the script\n'
  failures=$(( failures + 1 ))
fi

printf '\nThe generator must refuse bad input before writing anything:\n'
gen_refuses() {
  local why="$1"; shift
  local out="${SCRATCH}/should-not-exist-$(printf '%s' "$why" | tr -cd 'a-z')"
  if "$GENERATOR" --output "$out" "$@" >/dev/null 2>&1; then
    printf '  ** %s was accepted\n' "$why"; failures=$(( failures + 1 ))
  elif [[ -e "$out" ]]; then
    printf '  ** %s was refused but a file was written anyway\n' "$why"; failures=$(( failures + 1 ))
  else
    printf '  ok       %s refused, nothing written\n' "$why"
  fi
}
gen_refuses "an uppercase slug"   --slug "PluginCity-Thing" --version 1.0.0 --working-copy /tmp
gen_refuses "a slug with spaces"  --slug "two words"        --version 1.0.0 --working-copy /tmp
gen_refuses "a double hyphen"     --slug "a--b"             --version 1.0.0 --working-copy /tmp
gen_refuses "a non-version"       --slug "good-slug"        --version "1.0-beta" --working-copy /tmp
gen_refuses "a missing version"   --slug "good-slug"        --working-copy /tmp
gen_refuses "a missing attestation file" --slug "good-slug" --version 1.0.0 \
  --working-copy /tmp --attestation "${SCRATCH}/no-such-attestation"

printf '\n=================================\n'
if (( failures )); then
  printf 'FAILED — %s problem(s) above.\n\n' "$failures"
  exit 1
fi
printf 'PASSED — every check refuses its own fault, none is unproved,\n'
printf '         the coverage gate refuses an unproved check, and the\n'
printf '         generator refuses bad input without writing a file.\n\n'
