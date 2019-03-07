#!/bin/bash

# Copyright 2018 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script runs a long-running test against it.

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_PATH}/../../.." && pwd)"
. ${ROOT}/scripts/all-utilities.sh || { echo "Cannot load Bash utilities" ; exit 1 ; }

API_KEY=''
SERVICE_NAME=''
HOST=''
DURATION_IN_HOUR=0

while getopts :a:h:l:s: arg; do
  case ${arg} in
    a) API_KEY="${OPTARG}";;
    h) HOST="${OPTARG}";;
    l) DURATION_IN_HOUR="${OPTARG}";;
    s) SERVICE_NAME="${OPTARG}";;
    *) echo "Invalid option: -${OPTARG}";;
  esac
done

[[ -n "${HOST}" ]] || error_exit 'Please specify a host with -h option.'

if ! [[ -n "${API_KEY}" ]]; then
  set_api_keys;
  API_KEY="${ENDPOINTS_JENKINS_API_KEY}"
fi

# Download api Keys with restrictions from Cloud storage.
TEMP_DIR="$(mktemp -d)"
POST_FILE="${ROOT}/e2e/testdata/35k.json"

END_TIME=$(date +"%s")
END_TIME=$((END_TIME + DURATION_IN_HOUR * 60 * 60))
RUN_COUNT=0
STRESS_FAILURES=0
BOOKSTORE_FAILURES=0

detect_memory_leak_init ${HOST}

while true; do
  ((RUN_COUNT++))

  #######################
  # Insert tests here
  #######################

  echo "Starting test run ${RUN_COUNT} at $(date)."
  echo "Failures so far: Stress: ${STRESS_FAILURES}, Bookstore: ${BOOKSTORE_FAILURES}."

  # Generating token for each run, that they expire in 1 hour.
  JWT_TOKEN=`${ROOT}/tests/e2e/scripts/gen-auth-token.sh -a ${SERVICE_NAME}`
  echo "Auth token is: ${JWT_TOKEN}"

  echo "Starting bookstore test at $(date)."
  python ${ROOT}/tests/e2e/client/apiproxy_bookstore_test.py \
      --host=${HOST} \
      --api_key=${API_KEY} \
      --auth_token=${JWT_TOKEN} \
      --allow_unverified_cert=true \
    || ((BOOKSTORE_FAILURES++))

  # TODO(jilinxia): add other tests.

  #######################
  # End of test suite
  #######################

  # TODO(jilinxia): enable memory leak check.
  # detect_memory_leak_check ${RUN_COUNT}

  # Break if test has run long enough.
  [[ $(date +"%s") -lt ${END_TIME} ]] || break
done

echo "Finished ${RUN_COUNT} test runs."
echo "Failures: Stress: ${STRESS_FAILURES}, Bookstore: ${BOOKSTORE_FAILURES}."

RESULT=0
# We fail the test if all bookstore runs failed.
[[ ${BOOKSTORE_FAILURES} == ${RUN_COUNT} ]] \
  && RESULT=1

# We fail the test if memory increase is large.
detect_memory_leak_final && MEMORY_LEAK=0 || MEMORY_LEAK=1

exit $((${RESULT} + ${MEMORY_LEAK}))