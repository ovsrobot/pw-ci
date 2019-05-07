#!/bin/sh
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2018,2019 Red Hat, Inc.
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

    # 0001 - completion information
    run_db_command "select * from series_schema_version;" | egrep '^1$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
ALTER TABLE series ADD COLUMN series_completed INTEGER;
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (1);"
    fi

    # 0002 - series patchwork instance
    run_db_command "select * from series_schema_version;" | egrep '^2$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
ALTER TABLE series ADD COLUMN series_instance TEXT NOT NULL DEFAULT 'none';
EOF
        # we rely on the instance being leaked to the library here.
        # it's a layering violation.. :-/
        if [ "X$pw_instance" != "X" ]; then
            run_db_command "UPDATE series SET series_instance=\"$pw_instance\";"
        fi
        run_db_command "INSERT INTO series_schema_version(id) values (2);"
    fi

    # 0003 - series download retry mechanism
    run_db_command "select * from series_schema_version;" | egrep '^3$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
ALTER TABLE series ADD COLUMN series_downloaded INTEGER;
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (3);"
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
    local instance="$1"
    local project="$2"
    local id="$3"
    local url="$4"
    local submitter_name="$5"
    local submitter_email="$6"
    local completed="$7"

    echo "insert into series(series_id, series_project, series_url, series_submitter, series_email, series_submitted, series_completed, series_instance) values (${id}, \"${project}\", \"${url}\", \"${submitter_name}\", \"${submitter_email}\", \"false\", \"${completed}\", \"${instance}\");" | series_db_execute
}

function series_id_exists() {

    series_db_exists

    local CHECK_FOR_ID=$(echo "select series_id from series where series_id=${2} and series_instance=\"${1}\";" | series_db_execute)

    if [ "$CHECK_FOR_ID" != "" ]; then
        return 0
    fi

    return 1
}

function get_unsubmitted_jobs_as_line() {
    local instance="$1"
    local project="$2"

    series_db_exists

    echo "select series_id,series_url,series_submitter,series_email from series where series_instance=\"$instance\" and series_project=\"$project\" and series_completed=\"1\" and series_submitted=\"false\";" | series_db_execute
}

function get_uncompleted_jobs_as_line() {
    local instance="$1"
    local project="$2"

    series_db_exists

    echo "select series_id,series_url,series_submitter,series_email from series where series_instance=\"$instance\" and series_project=\"$project\" and series_completed=\"0\" and series_submitted=\"false\" and series_downloaded=\"0\";" | series_db_execute
}

function get_undownloaded_jobs_as_line() {
    local instance="$1"
    local project="$2"

    series_db_exists

    echo "select series_id,series_url,series_submitter,series_email from series where series_instance=\"$instance\" and series_project=\"$project\" and series_completed=\"1\" and series_submitted=\"true\" and series_downloaded=\"1\";" | series_db_execute
}

function series_id_set_submitted() {
    local instance="$1"
    local id="$2"

    if ! series_id_exists "$instance" "$id"; then
        return 0
    fi

    echo "update series set series_submitted=\"true\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
    return 0
}

function series_id_clear_submitted() {
    local instance="$1"
    local id="$2"

    if ! series_id_exists "$instance" "$id"; then
        return 0
    fi
    
    echo "update series set series_submitted=\"false\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
    return 0
}

function series_id_set_complete() {
    local instance="$1"
    local id="$2"

    if ! series_id_exists "$instance" "$id"; then
        return 0
    fi

    echo "update series set series_completed=\"1\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
    return 0
}

function series_id_set_downloading() {
    local instance="$1"
    local id="$2"

    if ! series_id_exists "$instance" "$id"; then
        return 0
    fi

    echo "update series set series_downloaded=\"1\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
}

function series_id_set_downloaded() {
    local instance="$1"
    local id="$2"

    if ! series_id_exists "$instance" "$id"; then
        return 0
    fi

    # Just in case we 'race' with the resubmit.  It shouldn't happen.
    series_id_set_submitted "$instance" "$id"
    echo "update series set series_downloaded=\"2\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
}

function series_id_clear_downloaded() {
    local instance="$1"
    local id="$2"

    if ! series_id_exists "$instance" "$id"; then
        return 0
    fi

    series_id_clear_submitted "$instance" "$id"
    echo "update series set series_downloaded=\"0\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
}
