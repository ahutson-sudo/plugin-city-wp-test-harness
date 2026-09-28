#!/usr/bin/env bash
# Prove that handing screenshot.sh a container path is diagnosed, and that an
# ordinary missing file is not lectured at.
#
# Worth its own check because the message it asserts on is the whole of the fix.
# A sentence that has stopped printing looks exactly like a sentence nobody has
# needed, and the only reader who would notice is the one it was written for.
#
# This runs on the host and starts nothing: screenshot.sh reads the shot list
# before it asks for a plugin or for Docker, so both cases stop at the first
# check and no stack can be disturbed.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SELF_DIR}/../.." && pwd)"

failures=0
OUTPUT=""
STATUS=0

# The container's own document root, which is where the seed is run from one
# command earlier, and therefore the path a reader has every reason to reuse.
IN_CONTAINER=/var/www/html/pc-seed/shots-pro.tsv

attempt() {
  set +e
  OUTPUT="$( "${REPO_ROOT}/scripts/screenshot.sh" "$1" 2>&1 )"
  STATUS=$?
  set -e
}

check() {
  local description="$1" condition="$2"
  if [[ "${condition}" == "yes" ]]; then
    echo "  PASS  ${description}"
    return
  fi
  echo "  FAIL  ${description}"
  failures=$(( failures + 1 ))
}

says() {
  if grep -Fq "$1" <<<"${OUTPUT}"; then echo yes; else echo no; fi
}

does_not_say() {
  if grep -Fq "$1" <<<"${OUTPUT}"; then echo no; else echo yes; fi
}

echo "=== A path inside the container is refused, and the reason is given ==="
attempt "${IN_CONTAINER}"
check "the run stops" "$( [[ ${STATUS} -ne 0 ]] && echo yes || echo no )"
check "it names the file it could not read" "$( says "${IN_CONTAINER}" )"
check "it says the path is the container's" "$( says 'inside the container' )"
check "it says where the shot list is actually read" "$( says 'here on the' )"
check "and names the script that does run in there" "$( says 'scripts/wp.sh' )"
if [[ ${failures} -ne 0 ]]; then printf '%s\n' "${OUTPUT}"; fi

echo
echo "=== An ordinary missing file is refused without the explanation ==="
before=${failures}
attempt "${SELF_DIR}/no-such-shot-list.tsv"
check "the run stops" "$( [[ ${STATUS} -ne 0 ]] && echo yes || echo no )"
check "it names the file it could not read" "$( says 'no-such-shot-list.tsv' )"
check "and does not talk about the container" "$( does_not_say 'inside the container' )"
if [[ ${failures} -ne ${before} ]]; then printf '%s\n' "${OUTPUT}"; fi

echo
echo "=== A shot list that is readable gets past this check ==="
before=${failures}
# examples/screenshots.tsv is the format's own documentation, so if the check
# ever refused a real list this is the file it would refuse. It goes no further
# than the next requirement, which is a plugin, and that is the pass condition:
# the path was accepted.
attempt "${REPO_ROOT}/examples/screenshots.tsv"
check "the shot list is not what it complains about" "$( does_not_say 'No such shot list' )"
if [[ ${failures} -ne ${before} ]]; then printf '%s\n' "${OUTPUT}"; fi

echo
if [[ ${failures} -ne 0 ]]; then
  echo "${failures} assertion(s) failed."
  exit 1
fi
echo "A shot list is read on the host, and says so when it is handed the other side."
