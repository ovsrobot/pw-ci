#!/bin/sh
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2018, Red Hat, Inc.
#
# Jenkins ci library
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

[ -f "${HOME}/.jenkins-rc" ] && source "${HOME}/.jenkins-rc"

if [ "X$jenkins_url" == "X" ]; then
    echo "ERROR: needs a jenkins url - configure ${HOME}/.jenkins-rc and"
    echo "       set jenkins_url"
    exit 1
fi

if [ "X$jenkins_user" == "X" ]; then
    echo "ERROR: needs a jenkins user - configure ${HOME}/.jenkins-rc and"
    echo "       set jenkins_user"
    exit 1
fi

if [ "X$jenkins_pw" == "X" -a "X$jenkins_token" == "X" ]; then
    echo "ERROR: set one of either jenkins_token or jenkins_pw in the jenkins-rc"
    exit 1
fi

jenkins_credentials="$jenkins_user:$jenkins_pw"

if [ "X$jenkins_token" != "X" ]; then
    jenkins_credentials="$jenkins_user:$jenkins_token"
fi

jenkins_crumb_value=$(curl -s "http://${jenkins_credentials}@${jenkins_url}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

function jenkins_check_for_job() {
    local jenkins_job=jenkins_${pw_project}_job

    curl -s -f -X GET \
         "http://${jenkins_credentials}@${jenkins_url}/job/${!jenkins_job}/config.xml" >/dev/null
}

function jenkins_submit_series() {
    local jenkins_job=jenkins_${pw_project}_job
    local jenkins_job_token=jenkins_${pw_project}_token

    if [ "X${!jenkins_job}" == "X" ]; then
        echo "ERROR: set jenkins_${pw_project}_job to a jenkins job value"
        return 1
    fi

    if ! jenkins_check_for_job; then
        echo "ERROR: Job ${!jenkins_job} doesn't exist"
        return 1
    fi

    local json_data='{
          "parameter": ['

    local jenkins_submit_vars=jenkins_${pw_project}_variables

    for var in ${!jenkins_submit_vars}; do
        if [ "X$var" != "X" ]; then
            local NAME=$(echo "$var" | cut -d: -f1)
            local pre_sub_val=$(echo "$var" | cut -d: -f2)

            VAL=$(ci_get_variable "$pre_sub_val")

            json_data="${json_data}"'
                {"name":"'"$NAME"'", "value":"'"${!VAL}"'"},'
        fi
    done

    json_data="${json_data}"'
        ]
        }'

    curl -s -f -X POST \
         -H "${jenkins_crumb_value}" \
         --data token="${!jenkins_job_token}" \
         --data-urlencode json="$json_data" \
         "http://${jenkins_credentials}@${jenkins_url}/job/${!jenkins_job}/build"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed job sumission"
        return 1
    fi

    return 0
}
