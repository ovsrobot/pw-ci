#!/bin/bash
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2021, Red Hat, Inc.
#
# Prints out Github Actions build logs for failed jobs, when provided
# wtih repo_name ("user/repo"), series_id, and shasum of commit.
#
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


[ -f "${HOME}/.github_actions_mon_rc" ] && source "${HOME}/.github_actions_mon_rc"

if [ "X" = "X$repo_name" ]; then
    repo_name="$1"
    shift
fi

if [ "X" = "X$series_id" ]; then
    series_id="$1"
    shift
fi

if [ "X" = "X$sha" ]; then
    sha="$1"
    shift
fi

if [ "X" = "X$github_token" ]; then
    github_token="$1"
    shift
fi

if [ "X" = "X$test_name" ]; then
    test_name="$1"
    shift
fi

if [ "X" = "X$repo_name" -o "X" = "X$series_id" -o "X" = "X$sha" -o "X" = "X$github_token" -o "X" = "X$test_name" ]; then
    echo "repo_name, series_id, sha, token, or test_name were not passed in as an arugment. Exiting" 1>&2
    exit 1
fi

tmp_dir=`mktemp -d`
if [ "$?" -eq "1" ]; then
    echo "Failed to make temp directory" 1>&2
    exit 1
fi
cd "$tmp_dir"

AUTH="Authorization: token ${github_token}"
APP="Accept: application/vnd.github.v3+json"
GITHUB_API="https://api.github.com"

# Parameters series_id, shasum
print_errored_logs_for_commit () {

    # Get run metadata
    select="select(.head_branch==\"series_${series_id}\") | select(.head_sha==\"${sha}\") | select(.name==\"${test_name}\")"
    headers="{id, logs_url}"
    run_meta="$(echo "$runs" | jq "$select | $headers")"

    redirect_url="$(echo "$run_meta" | jq -r ".logs_url")"
    run_id="$(echo "$run_meta" | jq -r ".id")"

     # Get the real logs url, download logs, and unzip logs
    logs_url="$(curl -s -S -H "${AUTH}" -H "${APP}" "${redirect_url}" -I | \
        grep -i 'Location: '| sed 's/Location: //i' | tr -d '\r')"
    curl -s -S "$logs_url" -o "build_logs_series_${series_id}.zip"
    unzip -o -q "build_logs_series_${series_id}.zip" -d "build_logs_series_${series_id}"

    # Get the names of the failed jobs and the steps that failed
    tmp_url="$GITHUB_API/repos/$repo_name/actions/runs/${run_id}/jobs"
    jobs_results="$(curl -s -S -H "${AUTH}" -H "${APP}" "${tmp_url}")"
    jobs_results="$(echo "$jobs_results" | jq "[.jobs[] | \
        select(.conclusion==\"failure\") | {name, failed_step: .steps[] | \
        select(.conclusion==\"failure\") | {name, conclusion, number}}]")"

    length="$(echo "$jobs_results" | jq -r "length")"

    if [ "X$length" == "X" -o "X$length" == "X0" ]; then
        echo "No build failures detected for series_${series_id}/${sha}. Exiting" 1>&2
        return 0
    fi

    echo "Build Logs:"

    # Print out which jobs failed
    echo "-----------------------Summary of failed steps-----------------------"
        echo "$jobs_results" | jq -r ".[] | .name + \";\" + .failed_step.name " | while IFS=";" \
        read -r job step; do
        echo "\"$job\" failed at step $step"
    done
    echo "----------------------End summary of failed steps--------------------"

    echo ""
    echo "-------------------------------BEGIN LOGS----------------------------"
    spacing=0

    # Print out logs for failed jobs
    echo "$jobs_results" | jq -r ".[] | .name + \";\" + .failed_step.name + \";\" + (.failed_step.number|tostring)" | \
        while IFS=';' read -r job step log_number; do

        if [ ! "$spacing" -eq "0" ]
        then
            echo -ne "\n\n\n\n"
        fi

        echo "####################################################################################"
        echo "#### [Begin job log] \"$job\" at step $step"
        echo "####################################################################################"

        cat "build_logs_series_$series_id/$job/$log_number"_* | tail -n 25 | cut -d' ' -f2- | sed 's/\r$//'

        echo "####################################################################################"
        echo "#### [End job log] \"$job\" at step $step"
        echo "####################################################################################"

        spacing=1
    done
    echo "--------------------------------END LOGS-----------------------------"
}

repo_name=$(echo "$repo_name" | sed -e 's@%2F@/@g' -e 's,%40,@,g')

# Get GHA runs
tmp_url="$GITHUB_API/repos/$repo_name/actions/runs?per_page=9000"
all_runs="$(curl -s -S -H "${AUTH}" -H "${APP}" "${tmp_url}")"
runs=$(echo $all_runs | jq -rc ".workflow_runs[] | select(.head_branch == \"series_$series_id\")")
not_found="$(echo "$runs" | jq -rc ".message")"
if [ "$not_found" == "Not Found" ]; then
    echo "\"$tmp_url\" could not be reached." 1>&2
elif [ "$not_found" == "Bad credentials" ]; then
    echo "Bad credentials - could not authenticate with token ${github_token}. \"$tmp_url\" could not be reached." 1>&2
else
    print_errored_logs_for_commit
fi

cd - > /dev/null
rm -rf "$tmp_dir"
