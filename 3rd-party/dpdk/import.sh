#!/bin/bash
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2018, Red Hat, Inc.
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

# Creates the docker job

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

if [ "X$pw_project" == "X" ]; then
    pw_project="$1"
fi

if [ "X$pw_project" == "X" ]; then
    echo "ERROR: set pw_project, or pass it as $1"
    exit 1
fi

jenkins_job=jenkins_${pw_project}_job

jenkins_crumb_value=$(curl -s "http://${jenkins_credentials}@${jenkins_url}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

curl -X POST -H "Content-Type: text/xml" -H "${jenkins_crumb_value}" "http://${jenkins_credentials}@${jenkins_url}/createItem?name=${!jenkins_job}" --data-binary @config.xml
