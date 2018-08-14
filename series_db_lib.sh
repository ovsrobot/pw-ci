#!/bin/sh
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

function run_db_command() {
    echo "$@" | sqlite3 ${HOME}/.series-db 2>/dev/null
}

function series_db_upgrade() {
    # 0000 - upgrade infrastructure
    run_db_command "select * from series_schema_version;" >/dev/null
    if [ $? -eq 1 ]; then
        run_db_command "CREATE TABLE series_schema_version (id INTEGER);"
        run_db_command "INSERT INTO series_schema_version(id) values (0);"
    fi

    run_db_command "select * from series_schema_version;" | egrep '^1$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
ALTER TABLE series ADD COLUMN series_completed INTEGER;
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (1);"
    fi
}

function series_db_exists() {
    if [ ! -e ${HOME}/.series-db ]; then
        sqlite3 ${HOME}/.series-db <<EOF
CREATE TABLE series (
series_id INTEGER,
series_project TEXT NOT NULL,
series_url TEXT NOT NULL,
series_submitter TEXT NOT NULL,
series_email TEXT NOT NULL,
series_submitted BOOLEAN
);
EOF
    fi
    series_db_upgrade
}

function series_db_execute() {
    local NOTDONE="false"
    while IFS=\n read command; do
        if [ "$NOTDONE" == "false" ]; then
            NOTDONE="true"
            series_db_exists
        fi
        run_db_command "$command"
    done
}

function series_db_add_false() {
    project="$1"
    id="$2"
    url="$3"
    submitter_name="$4"
    submitter_email="$5"
    completed="$6"

    echo "insert into series(series_id, series_project, series_url, series_submitter, series_email, series_submitted, series_completed) values (${id}, \"${project}\", \"${url}\", \"${submitter_name}\", \"${submitter_email}\", \"false\", \"${completed}\");" | series_db_execute
}

function series_id_exists() {

    series_db_exists

    local CHECK_FOR_ID=$(echo "select series_id from series where series_id=${1};" | series_db_execute)

    if [ "$CHECK_FOR_ID" != "" ]; then
        return 0
    fi

    return 1
}

function get_unsubmitted_jobs_as_line() {
    project="$1"

    series_db_exists

    echo "select series_id,series_url,series_submitter,series_email from series where series_project=\"$project\" and series_completed=\"1\" and series_submitted=\"false\";" | series_db_execute
}

function get_uncompleted_jobs_as_line() {
    project="$1"

    series_db_exists

    echo "select series_id,series_url,series_submitter,series_email from series where series_project=\"$project\" and series_completed=\"0\" and series_submitted=\"false\";" | series_db_execute
}

function series_id_set_submitted() {
    id="$1"

    if ! series_id_exists "$id"; then
        return 0
    fi
    
    echo "update series set series_submitted=\"true\" where series_id=$id;" | series_db_execute
    return 0
}

function series_id_set_complete() {
    id="$1"

    if ! series_id_exists "$id"; then
        return 0
    fi

    echo "update series set series_completed=\"1\" where series_id=$id;" | series_db_execute
}
