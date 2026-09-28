#!/usr/bin/env bash
# Prove that the image fetch retries a registry it could not reach, that it does
# not retry a registry that has already given its answer, and that a machine
# holding the images does not contact one at all.
#
# This runs on the host and drives the helpers in scripts/lib.sh directly, with
# HARNESS_ROOT pointed at a throwaway Compose file. It never starts a container,
# so it cannot disturb a stack that is already running. It does need Docker, and
# the middle case needs to be able to reach Docker Hub in order to be refused by
# it.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SELF_DIR}/../.." && pwd)"

SCRATCH="$(mktemp -d)"
LOCAL_TAG="pc-harness-pull-selftest:local"
trap 'rm -rf "${SCRATCH}"; docker image rm -f "${LOCAL_TAG}" >/dev/null 2>&1 || true' EXIT

export HARNESS_ROOT="${SCRATCH}"
export COMPOSE_PROJECT_NAME="pc-harness-pull-selftest"
# shellcheck source=../../scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

export PC_PULL_ATTEMPTS=3
# The waits are what this check would otherwise spend its time on, and the
# number of attempts is what it is measuring, so the backoff is shortened rather
# than the count.
export PC_PULL_RETRY_SECONDS=1

failures=0
OUTPUT=""
STATUS=0

# Every case asserts on what the harness said, so the output is kept rather than
# streamed, and printed in full under a failure.
attempt_pull() {
  set +e
  OUTPUT="$( pc_pull_images 2>&1 )"
  STATUS=$?
  set -e
}

name_the_image() {
  printf 'services:\n  db:\n    image: %s\n' "$1" > "${SCRATCH}/docker-compose.yml"
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

echo "=== A registry that cannot be reached is tried ${PC_PULL_ATTEMPTS} times ==="
# A host that does not resolve stands in for the transport failure this exists
# for: a reset connection part-way through a real pull leaves the same kind of
# error and the same exit status, and takes a working registry to reproduce.
name_the_image "registry.invalid.pc-harness-selftest/nowhere:1"
attempt_pull
check "the fetch fails" "$( [[ ${STATUS} -ne 0 ]] && echo yes || echo no )"
check "a second attempt is made" "$( says 'attempt 2 of 3' )"
check "a third attempt is made" "$( says 'attempt 3 of 3' )"
check "it stops at the third" "$( does_not_say 'attempt 4 of 3' )"
check "the failure says how many attempts were made" "$( says 'after 3 attempts' )"
check "and says that nothing has run" "$( says 'has run yet' )"
if [[ ${failures} -ne 0 ]]; then printf '%s\n' "${OUTPUT}"; fi

echo
echo "=== A tag the registry says does not exist is tried once ==="
before=${failures}
name_the_image "mariadb:11-no-such-tag-pc-harness-selftest"
attempt_pull
check "the fetch fails" "$( [[ ${STATUS} -ne 0 ]] && echo yes || echo no )"
check "no second attempt is made" "$( does_not_say 'attempt 2 of 3' )"
check "it says another attempt would not help" "$( says 'asking again would not change that' )"
check "and points at the version variables" "$( says 'WP_VERSION' )"
if [[ ${failures} -ne ${before} ]]; then printf '%s\n' "${OUTPUT}"; fi

echo
echo "=== An image already on the machine is not fetched ==="
before=${failures}
# Imported from an empty archive rather than pulled, so this case holds on a
# machine with no registry at all — which is the behaviour the explicit fetch
# had to preserve, since `up` never contacted one for an image it already had.
tar -cf - --files-from /dev/null | docker image import - "${LOCAL_TAG}" >/dev/null
name_the_image "${LOCAL_TAG}"
attempt_pull
check "the fetch succeeds" "$( [[ ${STATUS} -eq 0 ]] && echo yes || echo no )"
check "it says the image was already there" "$( says 'already on this machine' )"
check "and no attempt was made" "$( does_not_say 'Pulling' )"
if [[ ${failures} -ne ${before} ]]; then printf '%s\n' "${OUTPUT}"; fi

echo
if [[ ${failures} -ne 0 ]]; then
  echo "${failures} assertion(s) failed."
  exit 1
fi
echo "The image fetch retries what it should and nothing else."
