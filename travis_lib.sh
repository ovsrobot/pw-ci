#!/bin/bash
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2019 Red Hat, Inc.
#
# Travis ci library
# Licensed under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.  You may obtain a copy of the
# license at
#
#    https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

function travis_request() {
    local TRAVIS_API_SERVER="$1"
    shift

    local TRAVIS_CREDENTIAL="$1"
    shift

    local TRAVIS_URI="$1"
    shift

    curl -s -f -H "Travis-API-Version: 3" \
         -H "User-Agent: Travis Bash LIB" \
         -H "Authorization: token ${TRAVIS_CREDENTIAL}" \
         https://${TRAVIS_API_SERVER}/${TRAVIS_URI}
}

function travis_builds_for_branch() {
    local TRAVIS_API_SERVER="$1"
    shift

    local TRAVIS_CREDENTIAL="$1"
    shift

    local TRAVIS_REPO="$1"
    shift

    local TRAVIS_BRANCH="$1"
    shift

    travis_request "${TRAVIS_API_SERVER}" "${TRAVIS_CREDENTIAL}" \
                   "repo/${TRAVIS_REPO}/builds?branch.name=${TRAVIS_BRANCH}" | jq -rc '.builds[] | .commit.sha+","+.state+","+.started_at+","+.finished_at'
}
