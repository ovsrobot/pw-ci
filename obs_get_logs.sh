#!/bin/bash
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2021, Red Hat, Inc.
#
# Prints out openSUSE Build Service build logs for failed jobs, when
# provided wtih project (e.g. "home:rhobsrobot:dpdk"), series_id.
# Although shasum and token are not used, they must be passed to be
# consistent with other *_mon scripts. Pass in "NULL" for those parameters.
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


[ -f "${HOME}/.obs_ci_mon_rc" ] && source "${HOME}/.obs_ci_mon_rc"

# Also known as repo_name in github_actions
if [ "X" = "X$project" ]; then
    project="$1"
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

if [ "X" = "X$obs_token" ]; then
    obs_token="$1"
    shift
fi

if [ "X" = "X$project" -o "X" = "X$series_id" -o "X" = "X$sha" -o "X" = "X$obs_token" ]; then
    echo "project, series_id, sha or token were not passed in as an arugment. Exiting" 1>&2
    exit 1
fi

OSCBIN=osc
res_file=/tmp/obs_build_results.xml
path="//status[@package=\"$series_id\"]/@code"
$OSCBIN -c ~/.dpdkoscconf api -X GET /build/$project/_result > $res_file

repository="$(xmllint --xpath "/resultlist//@repository" $res_file | sort | uniq | sed 's/ *repository="\(.*\)".*/\1/' | tr '\n' ' ')"
arch="$(xmllint --xpath "/resultlist//@arch" $res_file | sort | uniq | sed 's/ *arch="\(.*\)".*/\1/' | tr '\n' ' ')"

# Make sure there is something to process
series_results="$(xmllint --xpath "$path" $res_file)"
if [ $? -ne 0 ]; then
    echo -n "Error parsing api response. " 1>&2
    echo "Perhaps series=$series_id is not in the api result below:" 1>&2
    cat $res_file 1>&2
    echo "End of api response. Skipping series $series_id" 1>&2
    exit 1
fi

# Print summary of failed jobs
echo "---------------------------------Summary of failed jobs-----------------------------"
for arch_iter in $arch; do
    for repo_iter in $repository; do
        p1="//result[@repository=\"${repo_iter}\" and @arch=\"${arch_iter}\"]"
        p2="status[@package=\"$series_id\"]/@code"

        # Get result (i.e. success, failed)
        code="$(xmllint --xpath "$p1/$p2" $res_file 2>/dev/null)"

        if echo "$code" | grep -iq failed; then
            echo failure on repo: $repo_iter --- arch: $arch_iter
        fi
    done
done
echo "-------------------------------End summary of failed jobs---------------------------"


# Print logs of failed jobs
echo -ne "\n\n\n\n"
echo "---------------------------------------BEGIN LOGS-----------------------------------"
spacing=0
for arch_iter in $arch; do
    for repo_iter in $repository; do
        p1="//result[@repository=\"${repo_iter}\" and @arch=\"${arch_iter}\"]"
        p2="status[@package=\"$series_id\"]/@code"
        p3="/build/$project/${repo_iter}/${arch_iter}/$series_id/_log"

        # Get result (i.e. success, failed)
        code="$(xmllint --xpath "$p1/$p2" $res_file 2>/dev/null)"

        if echo "$code" | grep -iq failed; then
            if [ ! "$spacing" -eq "0" ]
            then
                echo -ne "\n\n\n\n"
            fi

            echo "################################################################################"
            echo "#### [Begin job log] repo: \"$repo_iter\", arch: \"$arch_iter\""
            echo "################################################################################"

            echo failure on $arch_iter and $repo_iter

            # Get failed logs and print them out
            $OSCBIN -c ~/.dpdkoscconf api -X GET "$p3" | tail -n 50

            echo "################################################################################"
            echo "#### [End job log] repo: \"$repo_iter\", arch: \"$arch_iter\""
            echo "################################################################################"

            spacing=1
        fi
    done
done
echo "------------------------------------END LOGS------------------------------------"

# Delete series after getting the logs
$OSCBIN -c ~/.dpdkoscconf api -X DELETE /source/$project/$series_id > /dev/null
