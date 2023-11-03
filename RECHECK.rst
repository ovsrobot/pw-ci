..
      Licensed under the terms of the GNU General Public License as published
      by the Free Software Foundation; either version 2 of the License, or
      (at your option) any later version.  You may obtain a copy of the
      license at

         https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

      Unless required by applicable law or agreed to in writing, software
      distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
      WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
      License for the specific language governing permissions and limitations
      under the License.


============================
Recheck Requests
============================

Various testing labs performing CI testing on new patch series send
their results to the appropriate mailing lists for a pw-ci monitor
to collect the reports and publish them to patchwork.  On each
patch in the series, the results will appear with test category
contexts corresponding to the various test types which are run.
Examples include github-<worfklow>, travis-ci, etc.

If a reported failure on a series seems suspicious to the patch submitter
or maintainer, then there may be an interest in requesting a retest on the
series for the failing label(s) in order to verify the failure is not
spurious or a false positive. This retest demonstrates to the submitter or
maintainer that the failure can be reliably reproduced. Unfortunately, at
present, the best way to accomplish this is to reach out to lab maintainers
via email or Slack. This is not ideal for developers in need of quick test
results.

Going forward, CI testing labs have the option to implement a request for
retest of their respective test labels on patchwork via emails sent to the
developer mailing list.  This is accomplished using the the `recheck_tool`
to advance the retest check state through various points.

An example might look like::

  $ export PROJ=foo
  $ export INST=patches.foo.com
  $ export FILTER=foo-ci
  $ export FOO_TOKEN=abcd1234!@$%
  $ ./pw_mon --pw-project=$PROJ --pw-instance=$INST \
    --add-filter-recheck=$FILTER

  $ for recheck in $(./recheck_tool --pw-project=$PROJ --pw-instance=$INST \
                                    --filter=$FILTER --state=0); do
        echo "Asking for retest $recheck"
        SERIES=$(echo $recheck | jq -rc '.series_id')
        SHA=$(echo $recheck | jq -rc '.sha')
        MSG=$(echo $recheck | jq -rc '.message_id')
        ./foo_ci_restart --pw-project=$PROJ --pw-instance=$INST \
                         --series-id=$SERIES --sha=$SHA --token=$FOO_TOKEN
        ./recheck_tool --pw-project=$PROJ --pw-instance=$INST --msgid=$MSG \
                       --series-id=$SERIES --filter=$FILTER \
                       --update --state=0 --new-state=1
    done

From the users' perspective, in order to request a retest on your patch
series, send an email reply to one of your series’s patch or cover letter
emails with email content of the format used below::

  Recheck-request: <test names>

The valid delimiter is a comma optionally followed by a space: “,” “, “

Valid examples::

  Recheck-request: foo, bar, baz

  Recheck-request:   foo,bar,baz

  Recheck-request: foo,bar,baz,

Individual projects will have their own policies around who may request a
recheck, how many recheck requests may be sent, etc.  This should be
documented by the individual projects.
