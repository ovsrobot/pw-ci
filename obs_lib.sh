#!/bin/bash
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2020 PANTHEON.tech s.r.o.
#
# Suse OBS ci library
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

function obs_results_for_package() {
    # Prerequisites:
    # installed osc with credentials stored in ~/.config/osc/oscrc
    local OBS_PROJECT="$1"
    shift

    local OBS_PACKAGE="$1"
    shift

    url="https://build.opensuse.org/package/show/${OBS_PROJECT}/${OBS_PACKAGE}"

    final_result="succeeded"

    failed_found=0
    scheduled_found=0
    building_found=0
    errored_found=0
    result_details=""
    while read -r repo arch result
    do
        case "${result}" in
            "scheduled"*)
                scheduled_found=1
                ;;
            "building"*)
                building_found=1
                ;;
            "failed"*)
                failed_found=1
                result_details="${result_details}#${repo} ${arch} ${result}"
                ;;
            "succeeded"*)
                ;;
            "broken"*)
                # package source is bad (i.e. no specfile), report as error
                errored_found=1
                result_details="${result_details}#${repo} ${arch} ${result}"
                ;;
            "unresolvable"*)
                # build needs unavailable binary packages, report as error
                errored_found=1
                result_details="${result_details}#${repo} ${arch} ${result}"
                ;;
            "*")
                # disabled: build is disabled in package config
                # excluded: build is excluded in spec file
                # these are not failures in series, but OBS (mis)configuration
                # add them to report, but don't evaluate as error/failure
                result_details="${result_details}#${repo} ${arch} ${result}"
                ;;
        esac
    done <<< "$(osc results ${OBS_PROJECT} ${OBS_PACKAGE})"

    if [ ${scheduled_found} -eq 1 ]
    then
        final_result="scheduled"
    elif [ ${building_found} -eq 1 ]
    then
        final_result="building"
    elif [ ${errored_found} -eq 1 ]
    then
        final_result="errored"
    elif [ ${failed_found} -eq 1 ]
    then
        final_result="failed"
    fi

    if [[ "${result_details}" == "#"* ]]
    then
        result_details="${result_details:1}"
    fi

    echo "${final_result}|${result_details}|${url}"
}
