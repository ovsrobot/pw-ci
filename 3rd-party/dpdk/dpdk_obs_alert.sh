#!/bin/bash
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2020 PANTHEON.tech s.r.o.
#
# DPDK OBS alert script - monitor OBS builds and report results
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

./obs_mon patchwork.dpdk.org obs_user obs_password | \
    grep '^pw|' | while IFS="|" read -r PW series_id result result_details build_url; do

    SERIES_LINE=$(./series_get patchwork.dpdk.org $series_id)
    url=$(echo $SERIES_LINE | cut -d\| -f3)
    author=$(echo $SERIES_LINE | cut -d\| -f4)
    email=$(echo $SERIES_LINE | cut -d\| -f5)

    series_url=$(curl -s $url | jq -rc '.url')
    series_name=$(curl -s $url | jq -rc '.name')

    if [ "$result" == "succeeded" ]; then
        RESULT="SUCCESS"
    elif [ "$result" == "failed" ]; then
        RESULT="WARNING"
    else
        RESULT="ERROR"
    fi

    echo "To: test-report@dpdk.org" > report.eml
    echo "From: robot@bytheb.org" >> report.eml

    if [ "$RESULT" != "SUCCESS" ]; then
        echo "Cc: $author <$email>" >> report.eml
    fi

    echo "Subject: |$RESULT| pw$series_id $series_name" >> report.eml
    echo "Date: $(date +"%a, %e %b %Y %T %::z")" >> report.eml
    echo "" >> report.eml

    echo "Test-Label: obs-robot" >> report.eml
    echo "Test-Status: $RESULT" >> report.eml
    echo "$series_url" >> report.eml
    echo "" >> report.eml

    if [ "${result_details}" != "" ]
    then
        echo "Result-Details:" >> report.eml
        ifs_orig=${IFS}
        IFS=#
        for result in ${result_details}
        do
            echo "  ${result}" >> report.eml
        done
        IFS=${ifs_orig}
    fi

    echo "Build URL: $build_url" >> report.eml

    cat report.eml
done
