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

# This creates the docker image:
/usr/bin/sudo /usr/bin/docker build -t openvswitch/pwci Jenkins

# Next, start the docker image
/usr/bin/sudo /usr/bin/docker run --rm --name ovspwci \
              -p 8080:8080 -p 50000:50000 \
              -v jenkins_home:/var/jenkins_home openvswitch/pwci &


