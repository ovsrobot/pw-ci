#!/bin/sh
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2019, Red Hat, Inc.
#
# Dummy ci library
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

[ -f "${HOME}/.dummy-rc" ] && source "${HOME}/.dummy-rc"

function dummy_submit_series() {
    echo "Submitted with parameters: $@"
}
