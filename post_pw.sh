#!/bin/bash
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2021, Red Hat, Inc.
#
# Monitors a mailing lists for new reports emails. The script will then
# update a patchwork instance with the new reports using the provided
# token as authentication. The script skips unformated reports or
# reports that are already reported on patchwork.
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

[ -f "${HOME}/.mail_patchwork_sync.rc" ] && source "${HOME}/.mail_patchwork_sync.rc"

# Patchwork instance to update with new reports from mailing list
if [ "X" = "X$pw_instance" ]; then
    pw_instance="$1"
    shift
fi

# Mailing list to monitor for new reports
if [ "X" = "X$mail_archive" ]; then
    mail_archive="$1"
shift
fi

# Token to authenticate to patchwork
if [ "X" = "X$token" ]; then
    token="$1"
    shift
fi

if [ "X" = "X$pw_instance" -o "X" = "X$token" -o "X" = "X$mail_archive" ]; then
    echo "Missing arguments to $0. Exiting" 1>&2
    exit 1
fi

send_post() {
    local link="$1"

    #skip on empty link
    if [ -z "$link" ]; then
        return 0
    fi

    report="$(curl -sSf "${link}")"
    if [ $? -ne 0 ]; then
        echo "Failed to get proper server response on link ${link}" 1>&2
        return 0
    fi

    context="$(echo "$report" | sed -n 's/.*Test-Label: //p' | tr ' ' '_' | tr ':' '-')"
    state="$(echo "$report" | sed -n 's/.*Test-Status: //p')"
    description="$(echo "$report" | sed -ne 's/^_\(.*\)_$/\1/p')"
    patch_id="$(echo "$report" | sed -ne 's@.*href.*/patch[es]*/\(.*\)/\?".*@\1@ip' | sed 's@/@@')"
    target_url="$link"

    api_url="${pw_instance}/api/patches/${patch_id}/checks/"

    # Skip on missing arguments from email
    if [ -z "$context" -o -z "$state" -o -z "$description" -o -z "$patch_id" ]; then
        echo "Skpping \"$link\" due to missing context, state, description," \
             "or patch_id" 1>&2
        return 0
    fi

    # Get reports from patch
    checks="$(curl -sSf -X GET \
        --header "Content-Type: application/json" \
        "$api_url")"
    if [ $? -ne 0 ]; then
        echo "Failed to get proper server response on link ${api_url}" 1>&2
        return 0
    fi

    # Patchwork API may return http or https in the target_api field which
    # could break our contains filter. Avoid it by removing http/s substring
    mail_url="$(echo "$target_url" | sed 's@https\?://@@g')"

    if echo "$checks" | \
    jq -e "[.[].target_url] | contains([\"$mail_url\"])" >/dev/null
    then
        echo "Report ${target_url} already pushed to patchwork. Skipping." 1>&2
        return 0
    fi

    data="{\
        \"state\": \"$state\",\
        \"target_url\": \"$target_url\",\
        \"context\": \"$context\",\
        \"description\": \"$description\"\
    }"

    curl -sSf -X POST \
        -H "Authorization: Token ${token}" \
        --header "Content-Type: application/json" \
        --data "$data" \
        "$api_url" 2>&1

    if [ $? -ne 0 ]; then
        echo -e "Failed to push retults based on report ${link} to the"\
                "patchwork instance ${pw_instance} using the following REST"\
                "API Endpoint ${api_url} with the following data:\n$data\n"
        return 0
    fi
}

year_month="$(date +"%Y-%B")"
reports="$(curl -sSf "${mail_archive}${year_month}/thread.html" | \
         grep -i 'HREF=' | sed -e 's@[0-9]*<LI><A HREF="@\|@' -e 's@">@\|@')"
if [ $? -ne 0 ]; then
    echo "Failed to get proper server response on link ${reports}" 1>&2
    exit 1
fi

echo "$reports" | while IFS='|' read -r blank link title; do
    if echo "$link" | grep -Eq '[0-9]+\.html'; then
        send_post "${mail_archive}${year_month}/$link"
    fi
done
