#!/bin/sh
# SPDX-Identifier: gpl-2.0-or-later
# Copyright (C) 2018-2023 Red Hat, Inc.
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
    echo "$@" | sqlite3 -cmd '.timeout 500000' ${HOME}/.series-db 2>/dev/null
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

    # 0004 - travis information
    run_db_command "select * from series_schema_version;" | egrep '^4$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
CREATE TABLE travis_build (
pw_series_id INTEGER,
pw_series_instance TEXT,
travis_api_server TEXT,
travis_repo TEXT,
travis_branch TEXT,
travis_sha TEXT,
pw_patch_url TEXT
);
ALTER TABLE series ADD COLUMN series_branch TEXT;
ALTER TABLE series ADD COLUMN series_repo TEXT;
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (4);"
    fi

    # 0005 - travis information
    run_db_command "select * from series_schema_version;" | egrep '^5$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
ALTER TABLE SERIES ADD COLUMN series_sha TEXT;
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (5);"
    fi

    # 0006 - patch data for github and patchwork sync
    run_db_command "select * from series_schema_version;" | egrep '^6$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
CREATE TABLE git_builds (
series_id INTEGER,
patch_id INTEGER,
patch_url STRING,
patch_name STRING,
sha STRING,
patchwork_instance STRING,
patchwork_project STRING,
repo_name STRING,
gap_sync INTEGER);
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (6);"
    fi

    # 0007 - patch data for Open Build Service and Patchwork sync
    run_db_command "select * from series_schema_version;" | egrep '^7$' >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
ALTER TABLE git_builds ADD COLUMN obs_sync INTEGER;
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (7);"
    fi

    run_db_command "select * from series_schema_version;" | egrep '^8$' > /dev/null 2>&1
    if [ $? -eq 1 ]; then
        sqlite3 ${HOME}/.series-db <<EOF
CREATE TABLE recheck_requests (
recheck_id INTEGER,
recheck_message_id STRING,
recheck_requested_by STRING,
recheck_series STRING,
recheck_patch INTEGER,
patchwork_instance STRING,
patchwork_project STRING,
recheck_sync INTEGER
);
EOF
        run_db_command "INSERT INTO series_schema_version(id) values (8);"
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

    echo "insert into series(series_id, series_project, series_url, series_submitter, series_email, series_submitted, series_completed, series_instance, series_downloaded) values (${id}, \"${project}\", \"${url}\", \"${submitter_name}\", \"${submitter_email}\", \"false\", \"${completed}\", \"${instance}\", \"0\");" | series_db_execute
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

function get_series_line() {
    local instance="$1"
    local project="$2"

    series_db_exists

    echo "select series_url,series_submitter,series_email from series where series_id=\"$3\" and series_instance=\"$instance\";" | series_db_execute
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

function series_id_set_sha() {
    local instance="$1"
    local id="$2"

    if ! series_id_exists "$instance" "$id"; then
        return 0
    fi

    echo "update series set series_sha=\"$3\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
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

function series_get_active_branches() {
    local instance="$1"

    series_db_exists

    echo "select series_id,series_project,series_url,series_branch,series_repo from series where series_instance=\"$instance\" and series_branch is not null and series_branch != \"\";" | series_db_execute
}

function series_activate_branch() {
    local instance="$1"
    local id="$2"
    local repo="$3"
    local branchname="$4"

    echo "update series set series_branch=\"$branchname\",series_repo=\"$repo\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
}

function series_clear_branch() {
    local instance="$1"
    local id="$2"

    echo "update series set series_branch=\"\" where series_id=$id and series_instance=\"$instance\";" | series_db_execute
}

function series_by_sha() {
    local instance="$1"
    local sha="$2"

    echo "select series_url,series_submitter,series_email from series where series_sha=\"$sha\" and series_instance=\"$instance\";" | series_db_execute
}

function travis_add_sha() {
    local instance="$1"
    local sha="$2"
    local series_id="$3"
    local travis_api_server="$4"
    local travis_repo="$5"
    local travis_branch="$6"
    local patch_id="$7"

    echo "insert into travis_build(pw_series_id,pw_series_instance,travis_api_server,travis_repo,travis_branch,travis_sha,pw_patch_url) values (${series_id}, \"${instance}\", \"${travis_api_server}\", \"${travis_repo}\", \"${travis_branch}\", \"${sha}\", \"${patch_id}\");" | series_db_execute
}

function patch_id_by_sha() {
    local instance="$1"
    local sha="$2"

    echo "select patch_id from travis_build where pw_series_instance=\"$instance\" and travis_sha=\"$sha\";" | series_db_execute
}

function get_unsynced_series() {
    local instance="$1"
    local ci_instance="$2"

    series_db_exists

    echo "select * from git_builds where patchwork_instance=\"$instance\" and $ci_instance=0 order by series_id;" | series_db_execute
}

function set_synced_patch() {
    local patch_id="$1"
    local instance="$2"
    local ci_instance="$3"

    series_db_exists

    echo "update git_builds set $ci_instance=1 where patchwork_instance=\"$instance\" and patch_id=$patch_id;" | series_db_execute
}

function set_synced_for_series() {
    local series_id="$1"
    local instance="$2"
    local ci_instance="$3"

    series_db_exists

    echo "update git_builds set gap_sync=1, obs_sync=1 where patchwork_instance=\"$instance\" and series_id=$series_id;" | series_db_execute
}

function insert_commit() {
    local series_id="$1"
    local patch_id="$2"
    local patch_url="$3"
    local patch_name="$4"
    local sha="$5"
    local instance="$6"
    local project="$7"
    local repo_name="$8"

    series_db_exists

    echo "INSERT INTO git_builds (series_id, patch_id, patch_url, patch_name, sha, patchwork_instance, patchwork_project, repo_name, gap_sync, obs_sync) VALUES($series_id, $patch_id, \"$patch_url\", \"$patch_name\", \"$sha\", \"$instance\", \"$project\", \"$repo_name\", 0, 0);" | series_db_execute
}

function get_patch_id_by_series_id_and_sha() {
    local series_id="$1"
    local sha="$2"
    local instance="$3"

    series_db_exists

    echo "select patch_id from git_builds where patchwork_instance=\"$instance\" and series_id=$series_id and sha=\"$sha\";" | series_db_execute
}

function get_sha_for_series_id_and_patch() {
    local series_id="$1"
    local patch_id="$2"
    local instance="$3"

    echo "select sha from git_builds where patchwork_instance=\"$instance\" and series_id=\"$series_id\" and patch_id=\"$patch_id\"" | series_db_execute
}

function get_recheck_requests_by_project() {
    local recheck_instance="$1"
    local recheck_project="$2"
    local recheck_state="$3"
    local recheck_requested_by="$4"

    series_db_exists

    echo "select recheck_message_id,recheck_series,recheck_patch from recheck_requests where patchwork_instance=\"$recheck_instance\" and patchwork_project=\"$recheck_project\" and recheck_sync=$recheck_state and recheck_requested_by=\"$recheck_requested_by\";" | series_db_execute
}

function insert_recheck_request_if_needed() {
    local recheck_instance="$1"
    local recheck_project="$2"
    local recheck_msgid="$3"
    local recheck_requested_by="$4"
    local recheck_series="$5"
    local recheck_patch="$6"

    if ! echo "select * from recheck_requests where recheck_message_id=\"$recheck_msgid\";" | series_db_execute | grep $recheck_msgid >/dev/null 2>&1; then
        echo "INSERT INTO recheck_requests (recheck_message_id, recheck_requested_by, recheck_series, recheck_patch, patchwork_instance, patchwork_project, recheck_sync) values (\"$recheck_msgid\", \"$recheck_requested_by\", \"$recheck_series\", $recheck_patch, \"$recheck_instance\", \"$recheck_project\", 0);" | series_db_execute
    fi
}

function get_recheck_request() {
    local recheck_instance="$1"
    local recheck_project="$2"
    local recheck_msgid="$3"
    local recheck_requested_by="$4"
    local recheck_series="$5"
    local recheck_state="$6"

    echo "select * from recheck_requests where patchwork_instance=\"$recheck_instance\" and patchwork_project=\"$recheck_project\" and recheck_requested_by=\"$recheck_requested_by\" and recheck_series=\"$recheck_series\" and recheck_message_id=\"$recheck_msgid\" and recheck_sync=$recheck_state;" | series_db_execute
}

function set_recheck_request_state() {
    local recheck_instance="$1"
    local recheck_project="$2"
    local recheck_msgid="$3"
    local recheck_requested_by="$4"
    local recheck_series="$5"
    local recheck_state="$6"

    echo "UPDATE recheck_requests set recheck_sync=$recheck_state where patchwork_instance=\"$recheck_instance\" and patchwork_project=\"$recheck_project\" and recheck_requested_by=\"$recheck_requested_by\" and recheck_series=\"$recheck_series\";" | series_db_execute
}
