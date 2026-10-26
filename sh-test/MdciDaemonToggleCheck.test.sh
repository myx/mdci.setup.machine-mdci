#!/usr/bin/env bash
## 156 and MAGIC.md:152: setup.machine-mdci's os-commands mdci-daemon-disable and
## mdci-daemon-enable, run against logging stubs of monit, sysrc and service. Disable:
## unmonitor mdcid, unmonitor mdcid-progress, sysrc NO, onestop, in that order, and a
## failed unmonitor of either does not block the stop. Enable: sysrc YES, start, monitor
## mdcid, monitor mdcid-progress; a failing start ends it with the start's status and no
## monitor call. The monit names equal monitrc-mdci.conf's check names, and that file opens the monit control
## socket the CLI needs (without it every monit call fails and monit keeps restarting a disabled
## daemon). A failed unmonitor is said on stderr, once, naming the check. Each run is one
## `env -i` whose child refuses (99) unless all three commands resolve to the stubs; PATH
## is the stubs and /bin only. RIG_OSCMD points at another copy of the two files (the
## fail-first). Temp tree only; never a real monit, sysrc or service.
set -u
rigHere="$( cd "$( dirname "$0" )" && pwd -P )" || exit 1
rigFeature="${RIG_FEATURE:-${rigHere%/sh-test}}"
rigOsCmd="${RIG_OSCMD:-$rigFeature/data/os-commands}"
rigMonitrc="$rigFeature/data/monit/monitrc-mdci.conf"

rigRefuse(){
	echo "⛔ ERROR: $1 -- refusing to report a result" >&2 ; exit 1
}
for rigFile in "$rigOsCmd/mdci-daemon-disable" "$rigOsCmd/mdci-daemon-enable" "$rigMonitrc" ; do
	[ -f "$rigFile" ] || rigRefuse "missing: $rigFile"
done
rigTmp="$( mktemp -d "${TMPDIR:-/tmp}/AgentsMdciDaemonToggleCheck.XXXXXX" )" || exit 1
rigTmp="$( cd "$rigTmp" && pwd -P )" || exit 1
trap 'rm -rf -- "$rigTmp"' EXIT

rigPassCount=0
rigFailCount=0
rigAssert(){ ## what is asserted, got, want
	if [ "$2" = "$3" ] ; then
		printf '  PASS  %s\n' "$1" ; rigPassCount=$(( rigPassCount + 1 ))
	else
		printf '  FAIL  %s\n        got:  %s\n        want: %s\n' "$1" "$2" "$3" ; rigFailCount=$(( rigFailCount + 1 ))
	fi
}

## Each stub logs its name and argv, one line per call. `service … start` exits
## $RIG_START_RC; `monit` exits 1 when its argv equals $RIG_MONIT_FAIL.
mkdir -p "$rigTmp/stubs" "$rigTmp/tmp"
for rigTool in monit sysrc service ; do
	printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "$RIG_LOG"\n' "$rigTool" > "$rigTmp/stubs/$rigTool"
done
printf 'case "$*" in *" start") exit "${RIG_START_RC:-0}" ;; esac\n' >> "$rigTmp/stubs/service"
printf '[ "$*" != "${RIG_MONIT_FAIL:-}" ] || exit 1\n' >> "$rigTmp/stubs/monit"
chmod +x "$rigTmp/stubs"/*

rigRun(){ ## script, log name, start rc, failing monit argv -> rc in rigRc, calls in $rigTmp/<log name>
	rigRc=0
	: > "$rigTmp/$2"
	env -i PATH="$rigTmp/stubs:/bin" TMPDIR="$rigTmp/tmp" HOME="$rigTmp" RIG_LOG="$rigTmp/$2" RIG_TMP="$rigTmp" \
		RIG_START_RC="$3" RIG_MONIT_FAIL="$4" \
		/bin/sh -c '
			for t in monit sysrc service ; do case "$( command -v $t )" in "$RIG_TMP"/*) ;; *) exit 99 ;; esac ; done
			exec /bin/sh "$0"
		' "$rigOsCmd/$1" > "$rigTmp/$2.out" 2>&1 || rigRc=$?
}
rigCalls(){ ## log name -> the calls joined with " | "
	LC_ALL=C awk 'NR > 1 { printf " | " ; } { printf "%s", $0 ; } END { print "" ; }' "$rigTmp/$1"
}
rigDisableCalls="monit unmonitor mdcid | monit unmonitor mdcid-progress | sysrc mdcid_enable=NO | service mdcid onestop"

echo "-- the monit names are monitrc-mdci.conf's own check names --"
rigAssert "monitrc checks mdcid and mdcid-progress"      "$( LC_ALL=C awk '$1 == "check" { print $3 ; }' "$rigMonitrc" | LC_ALL=C sort | tr '\n' ' ' )" "mdcid mdcid-progress "
rigAssert "monitrc opens the monit control socket: one set httpd, unixsocket, root-only, one cleartext allow, no TCP port" "$( LC_ALL=C awk '$1 == "set" && $2 == "httpd" { n++ ; sock = $3 ; } $1 == "permission" { perm = $2 ; } $1 == "allow" && $2 ~ /^[^:@]+:[^:]+$/ { a++ ; } $1 == "port" || $3 == "port" { p++ ; } END { print n + 0, sock, perm, a + 0, p + 0 ; }' "$rigMonitrc" )" "1 unixsocket 700 1 0"

echo "-- disable --"
rigRun mdci-daemon-disable disable.log 0 ""
rigAssert "it runs, rc 0"                                 "$rigRc" 0
rigAssert "unmonitor both, then sysrc NO, then onestop, and nothing else" "$( rigCalls disable.log )" "$rigDisableCalls"
rigAssert "and no warning is said"                      "$( LC_ALL=C grep -c -F WARNING "$rigTmp/disable.log.out" )" 0

echo "-- disable, unmonitor mdcid fails --"
rigRun mdci-daemon-disable disable-fail1.log 0 "unmonitor mdcid"
rigAssert "the stop still runs: every call, in order"     "$( rigCalls disable-fail1.log )" "$rigDisableCalls"
rigAssert "and its status is the stop's, rc 0"            "$rigRc" 0
rigAssert "one warning, naming mdcid"                  "$( LC_ALL=C grep -c -F "WARNING: mdci-daemon-disable: monit unmonitor mdcid failed" "$rigTmp/disable-fail1.log.out" ) $( LC_ALL=C grep -c -F WARNING "$rigTmp/disable-fail1.log.out" )" "1 1"

echo "-- disable, unmonitor mdcid-progress fails --"
rigRun mdci-daemon-disable disable-fail2.log 0 "unmonitor mdcid-progress"
rigAssert "the stop still runs: every call, in order"     "$( rigCalls disable-fail2.log )" "$rigDisableCalls"
rigAssert "and its status is the stop's, rc 0"            "$rigRc" 0
rigAssert "one warning, naming mdcid-progress"         "$( LC_ALL=C grep -c -F "WARNING: mdci-daemon-disable: monit unmonitor mdcid-progress failed" "$rigTmp/disable-fail2.log.out" ) $( LC_ALL=C grep -c -F WARNING "$rigTmp/disable-fail2.log.out" )" "1 1"

echo "-- enable --"
rigRun mdci-daemon-enable enable.log 0 ""
rigAssert "it runs, rc 0"                                 "$rigRc" 0
rigAssert "sysrc YES, then start, then monitor both, and nothing else" "$( rigCalls enable.log )" \
	"sysrc mdcid_enable=YES | service mdcid start | monit monitor mdcid | monit monitor mdcid-progress"

echo "-- enable, the start fails --"
rigRun mdci-daemon-enable enable-fail.log 3 ""
rigAssert "it exits with the start's status"              "$rigRc" 3
rigAssert "monit monitor is never called"                 "$( LC_ALL=C grep -c '^monit ' "$rigTmp/enable-fail.log" )" 0
rigAssert "control: the start was reached"                "$( rigCalls enable-fail.log )" "sysrc mdcid_enable=YES | service mdcid start"

if [ "$rigFailCount" -ne 0 ] ; then
	echo "⛔ MDCI DAEMON TOGGLE CHECK FAILED: $rigFailCount of $(( rigPassCount + rigFailCount )) assertion(s)" >&2 ; exit 1
fi
printf 'MDCI_DAEMON_TOGGLE: OK (%d assertions, offline, stubs only)\n' "$rigPassCount"
