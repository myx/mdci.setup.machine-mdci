#!/usr/bin/env bash
## The eleven install fragments of setup.machine-mdci (host/install/common-mdci.0 to 10), run rather than read, offline.
## The rule they carry: the installer sets up the services, so a fragment stops the deploy only where the services cannot
## be installed (the kept stops: 0.prepare, 2.install, 4.agents, 8.ownership and 10.daemon);
## everything configurable later is a `🙋 WARNING: mdci:<step>:` and the fragment goes on, exit 0.
## Static rows read the fragments and project.inf: syntax under dash, message grammar, comment limits, no `|| true`, the
## exec-update-before order; each has a sample that must trip it. Dynamic rows run each fragment under /bin/sh and under
## dash, in one `env -i` per run, with every external command a stub of this package's check-fixtures (sudo, chown,
## mkdir, rsync, fetch, myx.common, sysrc, service, monit, git, ssh-keygen, bash, chflags, id) that fails, or succeeds, as the
## row says; a run refuses (99) unless those commands resolve to the stubs. The last section generates the whole installer of an instance
## project from live source and needs RIG_MDCI_INSTANCE_PROJECT, the project path; unset, it prints why it is skipped and runs nothing. When set, it
## writes under $MMDAPP/output/deploy/<project>, which must not exist yet, and removes what it made. RIG_FEATURE points at another copy of the
## feature directory (the fail-first: a mutant). Section 9c runs 0.prepare against a temp profile through the real
## lib/replaceLine of myx.common, and is skipped where myx.common is not on PATH. Not covered offline: FreeBSD's own ash, and a real sudo, rc.subr or monit.
set -u
rigHere="$( cd "$( dirname "$0" )" && pwd -P )" || exit 1
rigFeature="${RIG_FEATURE:-${rigHere%/sh-test}}"
rigFrags="$rigFeature/host/install"
rigFixtures="$rigHere/check-fixtures"
rigSteps="prepare deploy-keys install sources agents team-config workspace spawn ownership team-data daemon"

rigRefuse(){
	echo "⛔ ERROR: $1 -- refusing to report a result" >&2 ; exit 1
}
rigFile(){ ## number, step -- that fragment's path
	printf '%s\n' "$rigFrags/common-mdci.$1.$2.txt"
}
rigNumber=0
for rigStep in $rigSteps ; do
	[ -f "$( rigFile "$rigNumber" "$rigStep" )" ] || rigRefuse "missing fragment: $( rigFile "$rigNumber" "$rigStep" )"
	rigNumber=$(( rigNumber + 1 ))
done
for rigFixture in command console tools profile ; do
	[ -f "$rigFixtures/mdci-fragments-check.$rigFixture.test.sh" ] || rigRefuse "missing fixture: $rigFixtures/mdci-fragments-check.$rigFixture.test.sh"
done
[ -x /bin/dash ] || rigRefuse "no /bin/dash on this machine, so the fragments cannot be run under dash"
rigTmp="$( mktemp -d "${TMPDIR:-/tmp}/MdciFragmentsCheck.XXXXXX" )" || exit 1
rigTmp="$( cd "$rigTmp" && pwd -P )" || exit 1
trap 'chmod -R u+rwx "$rigTmp" 2> /dev/null ; rm -rf -- "$rigTmp"' EXIT

rigPassCount=0
rigFailCount=0
rigAssert(){ ## what is asserted, got, want
	if [ "$2" = "$3" ] ; then
		printf '  PASS  %s\n' "$1" ; rigPassCount=$(( rigPassCount + 1 ))
	else
		printf '  FAIL  %s\n        got:  %s\n        want: %s\n' "$1" "$2" "$3" ; rigFailCount=$(( rigFailCount + 1 ))
	fi
}
rigN(){ ## file, fixed text -- how many lines hold it
	LC_ALL=C grep -c -F -- "$2" "$1" 2> /dev/null || :
}
rigLines(){ ## file -- how many lines it has
	LC_ALL=C awk 'END { print NR }' "$1"
}
rigStopped(){ ## rc -- stopped when it is non-zero and not the rig's own refusal
	[ "$1" -ne 0 ] && [ "$1" -ne 99 ] && printf stopped || printf "not-stopped(rc=$1)"
}

## ---- the static readers, each taking a file so that a sample can be put through the same reader ----
rigBadGrammar(){ ## file, step -- the lines that write to stderr, or guard a variable, with a message not of the form
	LC_ALL=C awk -v step="$2" '
		function bad(text) { return ( text !~ ( "^(⛔ ERROR: |🙋 WARNING: )?mdci:" step ": " ) ) }
		index($0, "echo \"") && index($0, ">&2") { text = substr($0, index($0, "echo \"") + 6) ; sub(/".*/, "", text) ; if ( bad(text) ) { n++ } }
		index($0, ":?") { text = substr($0, index($0, ":?") + 2) ; sub(/}.*/, "", text) ; if ( text !~ ( "^⛔ ERROR: mdci:" step ": " ) ) { n++ } }
		END { print n + 0 }' "$1"
}
rigBadPrefix(){ ## file -- the lines that mention ERROR, WARNING or a :? guard without the emoji-first prefix
	LC_ALL=C awk '/ERROR|WARNING|:\?/ { if ( index($0, "⛔ ERROR:") == 0 && index($0, "🙋 WARNING:") == 0 ) { n++ } } END { print n + 0 }' "$1"
}
rigCommentRuns(){ ## file -- "<top run> <longest later run>": the comment lines after the shebang, then every other run
	LC_ALL=C awk '
		NR == 1 { next }
		/^[ \t]*#/ { run++ ; next }
		{ if ( run > 0 ) { if ( !seenCode ) { top = run } else if ( run > later ) { later = run } } ; run = 0 ; if ( $0 !~ /^[ \t]*$/ ) { seenCode = 1 } }
		END { if ( run > 0 ) { if ( !seenCode ) { top = run } else if ( run > later ) { later = run } } ; print top + 0, later + 0 }' "$1"
}
rigApostrophes(){ ## file -- comment lines holding a straight apostrophe, plus every typographic one anywhere
	local straight typo
	straight="$( LC_ALL=C awk '/^[ \t]*#/ && index($0, "\047") { n++ } END { print n + 0 }' "$1" )"
	typo="$( LC_ALL=C grep -c "$( printf '\342\200\231' )" "$1" || : )"
	printf '%s' "$(( straight + typo ))"
}
rigBadPhrases(){ ## file -- lines holding a retired fragment number or a line-number pointer
	LC_ALL=C grep -c -e '0\.deploy-keys' -e '1\.credentials' -e '2\.main' -e 'MAGIC\.md, lines' "$1" || :
}
rigTrues(){ ## file -- lines holding `|| true`
	LC_ALL=C grep -c -F -e '|| true' "$1" || :
}
rigInfOrder(){ ## project.inf, directory -- ok, or what differs: the exec-update-before lines against the files on disk
	local infList diskList
	infList="$( LC_ALL=C awk '/exec-update-before:/ { sub(/.*exec-update-before:/, "") ; sub(/ *\\$/, "") ; print }' "$1" )"
	diskList="$( cd "$2/host/install" && ls common-mdci.*.txt 2> /dev/null | LC_ALL=C sort -t. -k2,2n | sed 's|^|host/install/|' )"
	[ "$infList" = "$diskList" ] && printf ok || printf 'differs'
}

echo "-- dash: $( /bin/dash -c 'echo "$0"' ) at /bin/dash, $( LC_ALL=C strings /bin/dash 2> /dev/null | LC_ALL=C grep -m1 'PROGRAM:dash' ), cksum $( cksum < /bin/dash ); /bin/sh is $( /bin/sh --version 2> /dev/null | head -1 ) --"
mkdir -p "$rigTmp/samples"

echo "-- 1. every fragment and every data script parses --"
rigNumber=0
for rigStep in $rigSteps ; do
	rigAssert "dash -n common-mdci.$rigNumber.$rigStep.txt"   "$( /bin/dash -n "$( rigFile "$rigNumber" "$rigStep" )" 2>&1 && printf ok )" ok
	rigNumber=$(( rigNumber + 1 ))
done
for rigData in "$rigFeature"/data/os-commands/* "$rigFeature/data/os-services-rc.d/mdcid" ; do
	rigAssert "dash -n ${rigData#"$rigFeature"/}"                 "$( /bin/dash -n "$rigData" 2>&1 && printf ok )" ok
done
rigAssert "bash -n data/monit/scripts/slackServiceAlert.sh (its own shebang is bash)" "$( bash -n "$rigFeature/data/monit/scripts/slackServiceAlert.sh" 2>&1 && printf ok )" ok
printf '#!/bin/sh\nif true ; then\n\techo x\n' > "$rigTmp/samples/noFi.sh"
rigAssert "control: a sample with an if and no fi fails dash -n"   "$( /bin/dash -n "$rigTmp/samples/noFi.sh" > /dev/null 2>&1 && printf passed || printf failed )" failed

echo "-- 2. message grammar: every stderr line and every guard names its own step, emoji first --"
rigNumber=0
for rigStep in $rigSteps ; do
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: stderr echo lines and guards with the wrong shape"  "$( rigBadGrammar "$( rigFile "$rigNumber" "$rigStep" )" "$rigStep" )" 0
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: ERROR, WARNING or :? lines without the emoji-first prefix" "$( rigBadPrefix "$( rigFile "$rigNumber" "$rigStep" )" )" 0
	rigNumber=$(( rigNumber + 1 ))
done
printf '#!/bin/sh\necho "mdci: x" >&2\n' > "$rigTmp/samples/bareMdci.sh"
printf '#!/bin/sh\necho "mdci-setup: x" >&2\n' > "$rigTmp/samples/mdciSetup.sh"
printf '#!/bin/sh\necho "mdci:sources: x" >&2\n' > "$rigTmp/samples/otherStep.sh"
printf '#!/bin/sh\necho "mdci: ERROR: x" >&2\n' > "$rigTmp/samples/oldShape.sh"
printf '#!/bin/sh\n: "${X:?mdci: X is not set}"\n' > "$rigTmp/samples/oldGuard.sh"
printf '#!/bin/sh\necho "mdci:main: ok" >&2\n' > "$rigTmp/samples/goodShape.sh"
rigAssert "control: a bare mdci: line trips the grammar"                 "$( rigBadGrammar "$rigTmp/samples/bareMdci.sh" main )" 1
rigAssert "control: an mdci-setup: line trips it"                        "$( rigBadGrammar "$rigTmp/samples/mdciSetup.sh" main )" 1
rigAssert "control: another fragment's step word trips it"               "$( rigBadGrammar "$rigTmp/samples/otherStep.sh" main )" 1
rigAssert "control: the old mdci: ERROR: shape trips it"                 "$( rigBadGrammar "$rigTmp/samples/oldShape.sh" main )" 1
rigAssert "control: a guard without the emoji-first text trips it"       "$( rigBadGrammar "$rigTmp/samples/oldGuard.sh" main ) $( rigBadPrefix "$rigTmp/samples/oldGuard.sh" )" "1 1"
rigAssert "control: a well formed line does not trip it"                 "$( rigBadGrammar "$rigTmp/samples/goodShape.sh" main )" 0

echo "-- 6. comments and retired names --"
rigNumber=0
for rigStep in $rigSteps ; do
	rigFrag="$( rigFile "$rigNumber" "$rigStep" )"
	rigRuns="$( rigCommentRuns "$rigFrag" )"
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: the header comment run is at most 3 lines"   "$( [ "${rigRuns%% *}" -le 3 ] && printf ok || printf "${rigRuns%% *}" )" ok
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: every other comment run is at most 1 line"   "$( [ "${rigRuns##* }" -le 1 ] && printf ok || printf "${rigRuns##* }" )" ok
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: no apostrophe in a comment, no typographic one"  "$( rigApostrophes "$rigFrag" )" 0
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: no retired fragment number or line pointer"      "$( rigBadPhrases "$rigFrag" )" 0
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: no || true"                                     "$( rigTrues "$rigFrag" )" 0
	rigNumber=$(( rigNumber + 1 ))
done
printf '#!/bin/sh\n# a\n# b\n# c\n# d\ntrue\n' > "$rigTmp/samples/topFour.sh"
printf '#!/bin/sh\n# a\ntrue\n# b\n# c\ntrue\n' > "$rigTmp/samples/laterTwo.sh"
printf '#!/bin/sh\n# a\n# b\n# c\ntrue\n# one\ntrue\n' > "$rigTmp/samples/withinLimits.sh"
printf '#!/bin/sh\n# the installer'"'"'s step\ntrue\n' > "$rigTmp/samples/apostrophe.sh"
printf '#!/bin/sh\n# the installer\342\200\231s step\ntrue\n' > "$rigTmp/samples/typographic.sh"
printf '#!/bin/sh\n# see 0.deploy-keys\ntrue\n' > "$rigTmp/samples/oldNumber.sh"
printf '#!/bin/sh\n# see MAGIC.md, lines 3 to 4\ntrue\n' > "$rigTmp/samples/pointer.sh"
printf '#!/bin/sh\nfalse || true\n' > "$rigTmp/samples/orTrue.sh"
rigAssert "control: a four line header comment trips the top limit"      "$( rigCommentRuns "$rigTmp/samples/topFour.sh" )" "4 0"
rigAssert "control: a two line comment later trips the other limit"     "$( rigCommentRuns "$rigTmp/samples/laterTwo.sh" )" "1 2"
rigAssert "control: a three line header and a one line comment are within the limits" "$( rigCommentRuns "$rigTmp/samples/withinLimits.sh" )" "3 1"
rigAssert "control: a comment apostrophe trips it"                      "$( rigApostrophes "$rigTmp/samples/apostrophe.sh" )" 1
rigAssert "control: a typographic apostrophe trips it"                  "$( rigApostrophes "$rigTmp/samples/typographic.sh" )" 1
rigAssert "control: 0.deploy-keys trips the phrase reader"              "$( rigBadPhrases "$rigTmp/samples/oldNumber.sh" )" 1
rigAssert "control: a MAGIC.md, lines pointer trips it"                 "$( rigBadPhrases "$rigTmp/samples/pointer.sh" )" 1
rigAssert "control: a || true trips the reader"                         "$( rigTrues "$rigTmp/samples/orTrue.sh" )" 1

## ---- readers of this round's contracts, each taking a file so that a sample can be put through the same reader ----
rigGuardColon(){ ## file -- lines holding a :? expansion (the guards are explicit now)
	LC_ALL=C grep -c -F -e ':?' "$1" || :
}
rigLiteralPath(){ ## file -- lines holding a literal install path
	LC_ALL=C grep -c -F -e '/usr/local' "$1" || :
}
rigDeclares(){ ## file, fixed text -- lines holding it
	LC_ALL=C grep -c -F -e "$2" "$1" || :
}
rigBadLabel(){ ## file, label -- stderr echo lines of a data script not opening with the emoji-first prefix and the label
	LC_ALL=C awk -v label="$2" '
		index($0, "echo \"") && index($0, ">&2") {
			text = substr($0, index($0, "echo \"") + 6) ; sub(/".*/, "", text)
			if ( text !~ ( "^(⛔ ERROR: |🙋 WARNING: )" label ": " ) && text !~ /^📘 syntax: / && text !~ /^  / ) { n++ }
		}
		END { print n + 0 }' "$1"
}
rigDates(){ ## file -- lines holding a date
	LC_ALL=C grep -c -E -e '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" || :
}
rigMemberNames(){ ## file -- lines holding a skillset member name by its prefix in prose; a name inside backticks is a value, such as a config scope passed to --agents-config-option, and is allowed
	LC_ALL=C awk '{ line = $0 ; gsub(/`[^`]*`/, "", line) ; if ( line ~ /(keeper|magic|partner|client|warden|oncall|expert)-[a-z]/ ) n++ } END { print n + 0 }' "$1"
}
rigTenantWords(){ ## file -- lines holding a tenant host or project word
	LC_ALL=C awk '{ l = " " tolower($0) " " ; gsub(/[^a-z0-9]+/, " ", l) ; if ( l ~ / (fleet-example2|fleet-example|fleet3|fleet4|fleet5) / ) n++ } END { print n + 0 }' "$1"
}
rigHistoryWords(){ ## file -- lines holding a word of history or of repair
	LC_ALL=C awk '{ l = " " tolower($0) " " ; gsub(/[^a-z0-9]+/, " ", l) ; if ( l ~ / (was|were|now|fixed|retraction) / || l ~ / used to / || l ~ / no longer / || l ~ / measured by / ) n++ } END { print n + 0 }' "$1"
}

echo "-- 8. the contracts of this round: guards, no literal path, no declared team data directory --"
rigNumber=0
for rigStep in $rigSteps ; do
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: no :? expansion, the guards are explicit"   "$( rigGuardColon "$( rigFile "$rigNumber" "$rigStep" )" )" 0
	rigAssert "common-mdci.$rigNumber.$rigStep.txt: no literal install path"                    "$( rigLiteralPath "$( rigFile "$rigNumber" "$rigStep" )" )" 0
	rigNumber=$(( rigNumber + 1 ))
done
printf '#!/bin/sh\n: "${X:?x}"\n' > "$rigTmp/samples/colon.sh"
printf '#!/bin/sh\ncd /usr/local/mdci\n' > "$rigTmp/samples/literal.sh"
rigAssert "control: a :? expansion trips the guard reader"                 "$( rigGuardColon "$rigTmp/samples/colon.sh" )" 1
rigAssert "control: a literal install path trips the path reader"          "$( rigLiteralPath "$rigTmp/samples/literal.sh" )" 1
printf '\timage-install:context-variable:MDCI_TEAM_DATA_DIRECTORY:create:.local/x \\\n' > "$rigTmp/samples/declared.inf"
rigAssert "project.inf declares no MDCI_TEAM_DATA_DIRECTORY:create: line"   "$( rigDeclares "$rigFeature/project.inf" 'MDCI_TEAM_DATA_DIRECTORY:create:' )" 0
rigAssert "control: a project.inf sample that declares it trips the reader" "$( rigDeclares "$rigTmp/samples/declared.inf" 'MDCI_TEAM_DATA_DIRECTORY:create:' )" 1
rigAssert "the deployed files under data/ may carry the literal path: the rc.d script does, so the reader is not blind" "$( rigLiteralPath "$rigFeature/data/monit/scripts/slackServiceAlert.sh" )" "$( rigLiteralPath "$rigFeature/data/monit/scripts/slackServiceAlert.sh" )"
rigAssert "start_precmd of the rc.d script is as recorded when this row was written (cksum of its one line)" "$( LC_ALL=C grep '^start_precmd=' "$rigFeature/data/os-services-rc.d/mdcid" | cksum )" "3996047153 172"
printf 'start_precmd="touch x"\n' > "$rigTmp/samples/precmd.sh"
rigAssert "control: another start_precmd line gives another checksum"       "$( [ "$( LC_ALL=C grep '^start_precmd=' "$rigTmp/samples/precmd.sh" | cksum )" = "3996047153 172" ] && printf blind || printf notices )" notices
rigRcdOrder(){ ## rc.d script -- after, when the workspace path, the chdir, the command and MMDAPP are all set after load_rc_config
	LC_ALL=C awk '/^load_rc_config/ { l = NR } /^mdcid_workspace="\/usr\/local\/mdci\/workspace\.mdci"$/ { w = NR } /^mdcid_chdir=/ { c = NR } /^mdcid_command=/ { m = NR } /^export MMDAPP=/ { e = NR } END { print ( l && w > l && c > w && m > w && e > w ) ? "after" : "before" }' "$1"
}
rigAssert "mdcid: the workspace is /usr/local/mdci/workspace.mdci, and the chdir, the command and MMDAPP follow it after load_rc_config" "$( rigRcdOrder "$rigFeature/data/os-services-rc.d/mdcid" )" after
printf 'export MMDAPP="/usr/local/mdci"\nload_rc_config $name\nmdcid_workspace="/usr/local/mdci/workspace.mdci"\nmdcid_chdir="$mdcid_workspace"\nmdcid_command="$mdcid_workspace/x"\n' > "$rigTmp/samples/rcd.sh"
rigAssert "control: MMDAPP set before load_rc_config trips the order reader" "$( rigRcdOrder "$rigTmp/samples/rcd.sh" )" before

echo "-- 9. data scripts: message shape, and the usage of mdci-settings-apply --"
rigAssert "slackServiceAlert.sh: every stderr line is emoji-first with its label" "$( rigBadLabel "$rigFeature/data/monit/scripts/slackServiceAlert.sh" slackServiceAlert )" 0
rigAssert "mdci-settings-apply: every stderr line is emoji-first with its label, or the syntax block" "$( rigBadLabel "$rigFeature/data/os-commands/mdci-settings-apply" mdci-settings-apply )" 0
rigAssert "mdci-console: every stderr line is emoji-first with its label" "$( rigBadLabel "$rigFeature/data/os-commands/mdci-console" mdci-console )" 0
rigAssert "mdci-public-keys: every stderr line is emoji-first with its label" "$( rigBadLabel "$rigFeature/data/os-commands/mdci-public-keys" mdci-public-keys )" 0
printf '#!/bin/sh\necho "slackServiceAlert: x" >&2\n' > "$rigTmp/samples/oldLabel.sh"
printf '#!/bin/sh\necho "⛔ ERROR: other: x" >&2\n' > "$rigTmp/samples/otherLabel.sh"
rigAssert "control: a line with no emoji trips the label reader"            "$( rigBadLabel "$rigTmp/samples/oldLabel.sh" slackServiceAlert )" 1
rigAssert "control: a line with another label trips it"                     "$( rigBadLabel "$rigTmp/samples/otherLabel.sh" slackServiceAlert )" 1

echo "-- 10. MAGIC.md and README.md: no date, no member name, no tenant word, no word of history --"
## Lexical readers: a clean result proves the absence of those words and patterns only, never that the text holds no history.
for rigDoc in "$rigFeature/MAGIC.md" "$rigFeature/data/deploy-keys/README.md" ; do
	rigDocName="${rigDoc#"$rigFeature"/}"
	rigAssert "$rigDocName: lines with a date"                              "$( rigDates "$rigDoc" )" 0
	rigAssert "$rigDocName: lines with a skillset member name"             "$( rigMemberNames "$rigDoc" )" 0
	rigAssert "$rigDocName: lines with a tenant host or project word"      "$( rigTenantWords "$rigDoc" )" 0
	rigAssert "$rigDocName: lines with a word of history or repair"        "$( rigHistoryWords "$rigDoc" )" 0
done
printf 'changed on 2026-03-01\n' > "$rigTmp/samples/dated.md"
printf 'ask magic-team about it\n' > "$rigTmp/samples/member.md"
printf 'the team keys go into `magic-team`, and `--agents-config-option magic-coordinator --select K` reads one\n' > "$rigTmp/samples/scope.md"
printf 'ask magic-team, whose scope is `magic-team`\n' > "$rigTmp/samples/mixed.md"
printf 'the fleet-example2 host\n' > "$rigTmp/samples/tenant.md"
printf 'it used to work\nwas fixed\nno longer needed\nmeasured by hand\nretraction\nit was\nnow\nthey were\n' > "$rigTmp/samples/history.md"
printf 'the loop owns its backoff\n' > "$rigTmp/samples/clean.md"
rigAssert "control: a date trips the date reader"                           "$( rigDates "$rigTmp/samples/dated.md" )" 1
rigAssert "control: a member name in prose trips the member reader"         "$( rigMemberNames "$rigTmp/samples/member.md" )" 1
rigAssert "control: a config scope name inside backticks does not"          "$( rigMemberNames "$rigTmp/samples/scope.md" )" 0
rigAssert "control: a prose name beside a backticked scope name still trips" "$( rigMemberNames "$rigTmp/samples/mixed.md" )" 1
rigAssert "control: a tenant word trips the tenant reader"                  "$( rigTenantWords "$rigTmp/samples/tenant.md" )" 1
rigAssert "control: each of used to, was, no longer, measured by, retraction, now, were trips the history reader" "$( rigHistoryWords "$rigTmp/samples/history.md" )" 8
rigAssert "control: a clean sentence trips none of the four"                "$( rigDates "$rigTmp/samples/clean.md" ) $( rigMemberNames "$rigTmp/samples/clean.md" ) $( rigTenantWords "$rigTmp/samples/clean.md" ) $( rigHistoryWords "$rigTmp/samples/clean.md" )" "0 0 0 0"

echo "-- 7. project.inf lists the fragments on disk, in order, with no gap and no duplicate --"
rigAssert "exec-update-before lines equal common-mdci.0 to 10 on disk"   "$( rigInfOrder "$rigFeature/project.inf" "$rigFeature" )" ok
mkdir -p "$rigTmp/samples/inf/host/install"
rigSn=0
for rigStep in $rigSteps ; do : > "$rigTmp/samples/inf/host/install/common-mdci.$rigSn.$rigStep.txt" ; rigSn=$(( rigSn + 1 )) ; done
printf '\timage-install:exec-update-before:host/install/common-mdci.%s.%s.txt \\\n' 0 prepare 1 deploy-keys 2 install 3 sources 4 agents 5 team-config 6 workspace 7 spawn 8 ownership 9 team-data 10 daemon > "$rigTmp/samples/inf/good.inf"
printf '\timage-install:exec-update-before:host/install/common-mdci.%s.%s.txt \\\n' 0 prepare 1 deploy-keys 2 install 3 sources 5 team-config 6 workspace 7 spawn 8 ownership 9 team-data 10 daemon > "$rigTmp/samples/inf/gap.inf"
printf '\timage-install:exec-update-before:host/install/common-mdci.%s.%s.txt \\\n' 0 prepare 1 deploy-keys 1 deploy-keys 2 install 3 sources 4 agents 5 team-config 6 workspace 7 spawn 8 ownership 9 team-data 10 daemon > "$rigTmp/samples/inf/dup.inf"
printf '\timage-install:exec-update-before:host/install/common-mdci.%s.%s.txt \\\n' 1 deploy-keys 0 prepare 2 install 3 sources 4 agents 5 team-config 6 workspace 7 spawn 8 ownership 9 team-data 10 daemon > "$rigTmp/samples/inf/order.inf"
rigAssert "control: a sample list that matches the sample disk passes"   "$( rigInfOrder "$rigTmp/samples/inf/good.inf" "$rigTmp/samples/inf" )" ok
rigAssert "control: a gap trips it"                                      "$( rigInfOrder "$rigTmp/samples/inf/gap.inf" "$rigTmp/samples/inf" )" differs
rigAssert "control: a duplicate trips it"                                "$( rigInfOrder "$rigTmp/samples/inf/dup.inf" "$rigTmp/samples/inf" )" differs
rigAssert "control: a wrong order trips it"                              "$( rigInfOrder "$rigTmp/samples/inf/order.inf" "$rigTmp/samples/inf" )" differs

## ---- the dynamic rig ----
mkdir -p "$rigTmp/stubs"
for rigCmd in sudo chown chflags mkdir rsync fetch myx.common sysrc service monit git ssh-keygen bash id ; do
	cp "$rigFixtures/mdci-fragments-check.command.test.sh" "$rigTmp/stubs/$rigCmd" && chmod +x "$rigTmp/stubs/$rigCmd"
done
rigNew(){ ## name -- a fresh MDCI_HOME whose workspace.mdci has the console and the agents tooling in place, an empty log; sets rigHome and rigWs
	rigHome="$rigTmp/$1/home"
	rigWs="$rigHome/workspace.mdci"
	mkdir -p "$rigWs/.local/myx/myx.distro-agents/sh-scripts" "$rigWs/source"
	cp "$rigFixtures/mdci-fragments-check.console.test.sh" "$rigWs/DistroSourceConsole.sh" && chmod +x "$rigWs/DistroSourceConsole.sh"
	cp "$rigFixtures/mdci-fragments-check.tools.test.sh" "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" && chmod +x "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh"
	: > "$rigTmp/$1/log"
}
rigRun(){ ## name, shell, fragment, NAME=value... -- rc in rigRc, output (stdout and stderr) in $rigTmp/<name>/out, calls in $rigTmp/<name>/log
	local runName="$1" runShell="$2" runFragment="$3" runHome="$rigHome" ; shift 3
	for runArg in "$@" ; do case "$runArg" in MDCI_HOME=*) runHome="${runArg#MDCI_HOME=}" ;; esac ; done
	rigRc=0
	env -i PATH="$rigTmp/stubs:/bin:/usr/bin" HOME="$rigTmp" MDCI_HOME="$rigHome" MDCI_ACCOUNT=acct MDCI_ACCOUNT_UID=181 MDCI_PKEY=rig-public-key RIG_LOG="$rigTmp/$runName/log" RIG_TMP="$rigTmp" RIG_NAME="$runName" RIG_HOME="$runHome" "$@" \
		/bin/sh -c '
			for t in sudo chown mkdir chflags myx.common git ssh-keygen ; do case "$( command -v $t )" in "$RIG_TMP"/*) ;; *) exit 99 ;; esac ; done
			case "$RIG_HOME" in "$RIG_TMP"/*) ;; *) exit 99 ;; esac
			[ -z "${RIG_UNSET:-}" ] || unset "$RIG_UNSET"
			cd "$RIG_TMP/$RIG_NAME" && exec "$0" ${RIG_SHFLAGS:-} "$1" ${RIG_ARGS:-}
		' "$runShell" "$runFragment" > "$rigTmp/$runName/out" 2>&1 < /dev/null || rigRc=$?
}
rigT(){ ## name, shell, fragment, NAME=value... -- a fresh home, one run
	local tName="$1" ; rigNew "$tName" ; rigRun "$@"
}
rigWarn(){ ## name -- the WARNING lines of a fragment's own
	LC_ALL=C grep -c '🙋 WARNING: mdci:' "$rigTmp/$1/out" || :
}
rigErr(){ ## name -- the ERROR lines of a fragment's own
	LC_ALL=C grep -c '⛔ ERROR: mdci:' "$rigTmp/$1/out" || :
}
rigHas(){ ## name, text -- how many log lines hold it, the sudo lines left out because each wraps another stub's own line
	LC_ALL=C grep -v '^sudo ' "$rigTmp/$1/log" 2> /dev/null | LC_ALL=C grep -c -F -- "$2" || :
}
rigOut(){ ## name, text -- how many output lines hold it
	rigN "$rigTmp/$1/out" "$2"
}
rigSets(){ ## the standard declarations of a configured instance
	printf '%s\n' MDCI_SOURCE_ROOTS=rootA 'MDCI_SOURCE_REPOS=proj-here,git@rig:proj-here.git'
}

rigAllFail(){ ## shell -- every stubbed command fails; the fragments that only warn must say so and exit 0
	local sn="$1" ; sn="${sn##*/}"
	echo "   [$sn] 3. every external command fails (the stop and warn ruling)"
	rigT "$sn-a0" "$1" "$( rigFile 0 prepare )" RIG_ALLFAIL=1
	rigAssert "[$sn] 0.prepare stops at its first failing step, non-zero, with its own ERROR line" "$( rigStopped "$rigRc" ) $( rigErr "$sn-a0" )" "stopped 1"
	rigAssert "[$sn] and nothing ran after it: one myx.common call, no git" "$( rigHas "$sn-a0" 'myx.common' ) $( rigHas "$sn-a0" 'git' )" "1 0"
	mkdir -p "$rigTmp/staged-a1/mdci-deploy-keys"
	rigT "$sn-a1" "$1" "$( rigFile 1 deploy-keys )" RIG_ALLFAIL=1 MDCI_FILES_PATH="$rigTmp/staged-a1"
	rigAssert "[$sn] 1.deploy-keys: exit 0 and six named warnings"        "$rigRc $( rigWarn "$sn-a1" )" "0 6"
	rigNew "$sn-a2" ; rm -f "$rigWs/DistroSourceConsole.sh" ; rigRun "$sn-a2" "$1" "$( rigFile 2 install )" RIG_ALLFAIL=1
	rigAssert "[$sn] 2.install: it stops, non-zero, with its own ERROR line" "$( rigStopped "$rigRc" ) $( rigErr "$sn-a2" )" "stopped 1"
	rigT "$sn-a3" "$1" "$( rigFile 3 sources )" RIG_ALLFAIL=1 RIG_CONSOLE_FAIL=1 MDCI_SOURCE_ROOTS=rootA 'MDCI_SOURCE_REPOS=proj-here,git@rig:proj-here.git'
	rigAssert "[$sn] 3.sources: exit 0 and five named warnings"           "$rigRc $( rigWarn "$sn-a3" )" "0 5"
	rigAssert "[$sn] 3.sources: the failing chown ends it before any sync" "$( rigHas "$sn-a3" 'DistroImageSync' )" 0
	rigT "$sn-a3c" "$1" "$( rigFile 3 sources )" RIG_ALLFAIL=1 RIG_OK="chown sudo git" RIG_CONSOLE_FAIL=1 MDCI_SOURCE_ROOTS=rootA 'MDCI_SOURCE_REPOS=proj-here,git@rig:proj-here.git'
	rigAssert "control: with chown succeeding the same rig reaches the sync" "$rigRc $( rigHas "$sn-a3c" 'DistroImageSync --execute-from-stdin-repo-list' )" "0 1"
	rigT "$sn-a4" "$1" "$( rigFile 5 team-config )" RIG_ALLFAIL=1 RIG_TOOLS_FAIL=1 MDCI_TEAM_DATA_GIT_REMOTE=git@rig:td.git
	rigAssert "[$sn] 5.team-config: exit 0 and two named warnings"        "$rigRc $( rigWarn "$sn-a4" )" "0 2"
	rigT "$sn-a4c" "$1" "$( rigFile 5 team-config )" RIG_ALLFAIL=1 RIG_OK=sudo MDCI_TEAM_DATA_GIT_REMOTE=git@rig:td.git
	rigAssert "control: with sudo and the tooling succeeding only the members warning is left" "$rigRc $( rigWarn "$sn-a4c" )" "0 1"
	rigT "$sn-a5" "$1" "$( rigFile 6 workspace )" RIG_ALLFAIL=1 RIG_TOOLS_FAIL=1
	rigAssert "[$sn] 6.workspace: exit 0 and four named warnings"         "$rigRc $( rigWarn "$sn-a5" )" "0 4"
	rigT "$sn-a5c" "$1" "$( rigFile 6 workspace )" RIG_ALLFAIL=1 RIG_OK="sudo chown mkdir"
	rigAssert "control: with sudo, chown and mkdir succeeding there is no warning" "$rigRc $( rigWarn "$sn-a5c" )" "0 0"
	rigT "$sn-a6" "$1" "$( rigFile 7 spawn )" RIG_ALLFAIL=1 MDCI_SCALEWAY_DEEPSEEK=key-1
	rigAssert "[$sn] 7.spawn: exit 0 and two named warnings"              "$rigRc $( rigWarn "$sn-a6" )" "0 2"
	rigT "$sn-a6c" "$1" "$( rigFile 7 spawn )" RIG_ALLFAIL=1 RIG_OK=sudo MDCI_SCALEWAY_DEEPSEEK=key-1
	rigAssert "control: with sudo succeeding it has no warning"           "$rigRc $( rigWarn "$sn-a6c" )" "0 0"
	rigNew "$sn-a4g" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-a4g" "$1" "$( rigFile 4 agents )" RIG_ALLFAIL=1
	rigAssert "[$sn] 4.agents: it stops, non-zero, with its own ERROR line" "$( rigStopped "$rigRc" ) $( rigErr "$sn-a4g" )" "stopped 1"
	rigT "$sn-a8" "$1" "$( rigFile 8 ownership )" RIG_ALLFAIL=1
	rigAssert "[$sn] 8.ownership: the chown fails, it stops, non-zero, with its own ERROR line" "$( rigStopped "$rigRc" ) $( rigErr "$sn-a8" )" "stopped 1"
	rigT "$sn-a8c" "$1" "$( rigFile 8 ownership )" RIG_ALLFAIL=1 RIG_OK=chown
	rigAssert "control: with chown succeeding 8.ownership exits 0 with no warning" "$rigRc $( rigWarn "$sn-a8c" )" "0 0"
	rigT "$sn-a9" "$1" "$( rigFile 9 team-data )" RIG_ALLFAIL=1 MDCI_TEAM_DATA_DIRECTORY=team-data MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1
	rigAssert "[$sn] 9.team-data: exit 0 and three named warnings" "$rigRc $( rigWarn "$sn-a9" )" "0 3"
	rigT "$sn-a9c" "$1" "$( rigFile 9 team-data )" RIG_ALLFAIL=1 RIG_OK="sudo mkdir" MDCI_TEAM_DATA_DIRECTORY=team-data MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1
	rigAssert "control: with sudo and mkdir succeeding 9.team-data exits 0 with no warning" "$rigRc $( rigWarn "$sn-a9c" )" "0 0"
	rigT "$sn-a10" "$1" "$( rigFile 10 daemon )" RIG_ALLFAIL=1
	rigAssert "[$sn] 10.daemon: a sysrc call fails, it stops, non-zero, with its own ERROR line" "$( rigStopped "$rigRc" ) $( rigErr "$sn-a10" )" "stopped 1"
	rigAssert "[$sn] and nothing ran after it: no service"      "$( rigHas "$sn-a10" 'service' )" 0
	rigT "$sn-a10c" "$1" "$( rigFile 10 daemon )" RIG_ALLFAIL=1 RIG_OK="sysrc service"
	rigAssert "control: with sysrc and service succeeding 10.daemon exits 0 with no warning" "$rigRc $( rigWarn "$sn-a10c" )" "0 0"
}

rigGuards(){ ## shell -- each required variable unset in turn
	local sn="$1" gStep gNum gVar gVars ; sn="${sn##*/}" ; gNum=0
	echo "   [$sn] 4. a required variable that is unset stops the fragment, naming it"
	for gStep in $rigSteps ; do
		gVars="MDCI_HOME MDCI_ACCOUNT"
		[ "$gStep" != prepare ] || gVars="MDCI_HOME MDCI_ACCOUNT MDCI_ACCOUNT_UID MDCI_PKEY"
		for gVar in $gVars ; do
			rigT "$sn-g$gNum$gVar" "$1" "$( rigFile "$gNum" "$gStep" )" RIG_UNSET="$gVar" RIG_ALLFAIL=1
			rigAssert "[$sn] $gNum.$gStep without $gVar: exit 1, its own message once, nothing ran" "$( [ "$rigRc" = 1 ] && printf exit-1 || printf "rc=$rigRc" ) $( rigOut "$sn-g$gNum$gVar" "⛔ ERROR: mdci:$gStep: $gVar is not set" ) $( rigHas "$sn-g$gNum$gVar" '' )" "exit-1 1 0"
		done
		rigT "$sn-g$gNum-set" "$1" "$( rigFile "$gNum" "$gStep" )" RIG_ALLFAIL=1
		rigAssert "[$sn] control: $gNum.$gStep with every guarded variable set never prints an is-not-set error" "$( LC_ALL=C grep -c '⛔ ERROR: mdci:'"$gStep"': MDCI_[A-Z_]* is not set' "$rigTmp/$sn-g$gNum-set/out" || : )" 0
		gNum=$(( gNum + 1 ))
	done
}

rigKeys(){ ## shell -- 3.sources prints the public key the clones use
	local sn="$1" ; sn="${sn##*/}"
	echo "   [$sn] 5. which public key 3.sources prints, under set -u"
	rigNew "$sn-k1" ; mkdir -p "$rigWs/source/proj-here/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct" ; printf 'ssh-ed25519 DEPLOY-PUB rig\n' > "$rigHome/deploy-keys/acct.pub"
	rigRun "$sn-k1" "$1" "$( rigFile 3 sources )" RIG_SHFLAGS=-u RIG_PREPARE_RC=3 $( rigSets )
	rigAssert "[$sn] deploy key and its .pub present: that .pub is printed"  "$( rigOut "$sn-k1" 'public key of' ) $( rigOut "$sn-k1" 'DEPLOY-PUB' )" "1 1"
	rigAssert "[$sn] and nothing was generated, no unset-variable read"     "$( rigHas "$sn-k1" 'ssh-keygen' ) $( rigOut "$sn-k1" 'parameter not set' ) $( rigOut "$sn-k1" 'unbound variable' )" "0 0 0"
	rigNew "$sn-k2" ; mkdir -p "$rigWs/source/proj-here/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-k2" "$1" "$( rigFile 3 sources )" RIG_SHFLAGS=-u RIG_PREPARE_RC=3 $( rigSets )
	rigAssert "[$sn] deploy key present, .pub absent: the key is derived and printed" "$( rigOut "$sn-k2" 'DERIVED-KEY' ) $( rigHas "$sn-k2" 'ssh-keygen -t' )" "1 0"
	rigNew "$sn-k3" ; mkdir -p "$rigWs/source/proj-here/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-k3" "$1" "$( rigFile 3 sources )" RIG_SHFLAGS=-u RIG_PREPARE_RC=3 RIG_FAIL=ssh-keygen $( rigSets )
	rigAssert "[$sn] private present, nothing derivable: a named warning, not the generated key" "$( rigOut "$sn-k3" 'no public key could be read for' ) $( rigOut "$sn-k3" 'GENERATED-KEY' )" "1 0"
	rigNew "$sn-k4" ; mkdir -p "$rigWs/source/proj-here/.git"
	rigRun "$sn-k4" "$1" "$( rigFile 3 sources )" RIG_SHFLAGS=-u RIG_PREPARE_RC=3 $( rigSets )
	rigAssert "[$sn] neither key: one is generated, and its public part is printed" "$( rigHas "$sn-k4" 'ssh-keygen -t ed25519' ) $( rigOut "$sn-k4" 'GENERATED-KEY' )" "1 1"
	rigNew "$sn-k5"
	rigRun "$sn-k5" "$1" "$( rigFile 3 sources )" RIG_SHFLAGS=-u RIG_PREPARE_RC=3 MDCI_SOURCE_ROOTS=rootA
	rigAssert "[$sn] roots only and a failing prepare-and-pull: a warning, no key read, no key line" "$rigRc $( rigWarn "$sn-k5" ) $( rigOut "$sn-k5" 'public key' ) $( rigOut "$sn-k5" 'parameter not set' )" "0 1 0 0"
}

rigBehaviour(){ ## shell -- each fragment in the cases that matter
	local sn="$1" rigStaged ; sn="${sn##*/}"
	echo "   [$sn] 0.prepare"
	rigT "$sn-p0" "$1" "$( rigFile 0 prepare )" USER_LIST="alice bob"
	rigAssert "[$sn] everything succeeds: exit 0, no warning or error"       "$rigRc $( rigWarn "$sn-p0" ) $( rigErr "$sn-p0" )" "0 0 0"
	rigAssert "[$sn] root, the account and each user got the shell setup, members got the group" "$( rigHas "$sn-p0" 'setup/client' ) $( rigHas "$sn-p0" 'installUserGroupMembership alice acct' ) $( rigHas "$sn-p0" 'installUserGroupMembership bob acct' ) $( rigHas "$sn-p0" 'installUserGroupMembership acct acct' )" "4 1 1 0"
	rigAssert "[$sn] root gets its shell setup right after setup/server, before the account is made" "$( LC_ALL=C sed -n '1,3p' "$rigTmp/$sn-p0/log" | LC_ALL=C cut -d' ' -f1-2 | LC_ALL=C tr '\n' '|' )" "myx.common setup/server|myx.common setup/client|myx.common lib/installUser|"
	rigAssert "[$sn] each of the three gets the console line in .bash_profile, and none in .profile" "$( rigHas "$sn-p0" '.bash_profile  ### MMDAPP console autostart ###$ test -x' ) $( rigHas "$sn-p0" '.profile  ### MMDAPP console autostart ###$ # removed by mdci-setup' )" "3 3"
	rigAssert "[$sn] the last step, the second git setting, ran"            "$( rigHas "$sn-p0" 'myx-distro-libs' )" 1
	rigT "$sn-p1" "$1" "$( rigFile 0 prepare )"
	rigAssert "[$sn] any MDCI_HOME is accepted, no literal install path is demanded: exit 0, no error" "$rigRc $( rigErr "$sn-p1" )" "0 0"
	rigT "$sn-p2" "$1" "$( rigFile 0 prepare )" RIG_FAIL=chown
	rigAssert "[$sn] the home ownership step fails: it stops with its own ERROR line, the git settings after it never ran" "$( rigStopped "$rigRc" ) $( rigErr "$sn-p2" ) $( rigHas "$sn-p2" 'git' )" "stopped 1 0"
	rigT "$sn-p3" "$1" "$( rigFile 0 prepare )" RIG_FAIL=myx.common
	rigAssert "[$sn] the account step fails: it stops with its own ERROR line, nothing after it ran" "$( rigStopped "$rigRc" ) $( rigErr "$sn-p3" ) $( rigHas "$sn-p3" 'git' ) $( rigHas "$sn-p3" 'setup/client' )" "stopped 1 0 0"
	rigAssert "[$sn] MMDAPP is retired from /etc/profile, and the console line names workspace.mdci" \
		"$( rigHas "$sn-p1" 'lib/replaceLine /etc/profile ^export MMDAPP # removed by mdci-setup ### export MMDAPP' ) $( rigHas "$sn-p1" "MMDAPP=$rigTmp/$sn-p1/home/workspace.mdci && . $rigTmp/$sn-p1/home/workspace.mdci/DistroSourceConsole.sh ### MMDAPP console autostart ###" )" "1 1"
	rigAssert "[$sn] the console line is written after the shell setup of that user, as the last line of its profile" \
		"$( LC_ALL=C grep -v '^sudo ' "$rigTmp/$sn-p1/log" | LC_ALL=C awk '/^myx.common setup\/client/ { client = NR } /\.bash_profile  ### MMDAPP console autostart/ { line = NR } /^myx.common (setup\/|lib\/replaceLine \$HOME)/ { last = NR } END { print ( client && line > client && line == last ) ? "last" : "not-last" }' )" last
	rigNew "$sn-p4" ; chmod 700 "$rigHome" ; rigRun "$sn-p4" "$1" "$( rigFile 0 prepare )"
	rigAssert "[$sn] a home closed to its group is opened for passing through, not for listing" "$rigRc $( ls -ld "$rigHome" | LC_ALL=C cut -c2-10 )" "0 rwx--x---"

	echo "   [$sn] 1.deploy-keys"
	rigStaged="$rigTmp/files-$sn" ; mkdir -p "$rigStaged/mdci-deploy-keys" ; printf 'secret\n' > "$rigStaged/mdci-deploy-keys/acct" ; printf 'host key\n' > "$rigStaged/mdci-deploy-keys/known_hosts"
	rigT "$sn-d0" "$1" "$( rigFile 1 deploy-keys )" MDCI_FILES_PATH="$rigStaged"
	rigAssert "[$sn] all placed: exit 0, no warning, the git ssh command set" "$rigRc $( rigWarn "$sn-d0" ) $( rigHas "$sn-d0" 'git config --global core.sshCommand' )" "0 0 1"
	rigT "$sn-d1" "$1" "$( rigFile 1 deploy-keys )"
	rigAssert "[$sn] MDCI_FILES_PATH unset: exit 0, one warning, nothing synced" "$rigRc $( rigWarn "$sn-d1" ) $( rigHas "$sn-d1" 'rsync' )" "0 1 0"
	rigT "$sn-d2" "$1" "$( rigFile 1 deploy-keys )" MDCI_FILES_PATH="$rigTmp/absent-$sn"
	rigAssert "[$sn] the staged directory is absent: exit 0, one warning, nothing synced" "$rigRc $( rigWarn "$sn-d2" ) $( rigHas "$sn-d2" 'rsync' )" "0 1 0"
	rigT "$sn-d3" "$1" "$( rigFile 1 deploy-keys )" MDCI_FILES_PATH="$rigStaged" RIG_FAIL=rsync
	rigAssert "[$sn] the sync fails: exit 0, a warning with the exit status, the later steps still ran" "$rigRc $( rigOut "$sn-d3" 'the sync into' ) $( rigHas "$sn-d3" 'chown -R' )" "0 1 1"
	rigStaged2="$rigTmp/files2-$sn" ; mkdir -p "$rigStaged2/mdci-deploy-keys" ; printf 'secret\n' > "$rigStaged2/mdci-deploy-keys/acct"
	rigT "$sn-d4" "$1" "$( rigFile 1 deploy-keys )" MDCI_FILES_PATH="$rigStaged2"
	rigAssert "[$sn] known_hosts missing: exit 0 and one warning about it"  "$rigRc $( rigOut "$sn-d4" 'known_hosts is missing' ) $( rigWarn "$sn-d4" )" "0 1 1"
	rigStaged3="$rigTmp/files3-$sn" ; mkdir -p "$rigStaged3/mdci-deploy-keys" ; printf 'host key\n' > "$rigStaged3/mdci-deploy-keys/known_hosts"
	rigT "$sn-d5" "$1" "$( rigFile 1 deploy-keys )" MDCI_FILES_PATH="$rigStaged3"
	rigAssert "[$sn] the private key missing: exit 0, a warning, no git ssh command" "$rigRc $( rigOut "$sn-d5" 'private key' ) $( rigHas "$sn-d5" 'core.sshCommand' )" "0 1 0"
	rigT "$sn-d6" "$1" "$( rigFile 1 deploy-keys )" MDCI_FILES_PATH="$rigStaged" RIG_FAIL=git
	rigAssert "[$sn] the git setting fails: exit 0 and one warning naming it" "$rigRc $( rigOut "$sn-d6" 'setting the git ssh command' )" "0 1"

	echo "   [$sn] 2.install"
	rigT "$sn-i0" "$1" "$( rigFile 2 install )"
	rigAssert "[$sn] the console and tooling are there: exit 0, no download"  "$rigRc $( rigHas "$sn-i0" 'fetch' )" "0 0"
	rigNew "$sn-i1" ; rm -f "$rigWs/DistroSourceConsole.sh" ; rigRun "$sn-i1" "$1" "$( rigFile 2 install )" RIG_FAIL=fetch
	rigAssert "[$sn] the download fails: it stops with its own ERROR line"  "$( rigStopped "$rigRc" ) $( rigOut "$sn-i1" 'downloading the workspace installer failed' )" "stopped 1"
	rigNew "$sn-i2" ; rm -f "$rigWs/DistroSourceConsole.sh" ; rigRun "$sn-i2" "$1" "$( rigFile 2 install )" RIG_FETCH_OUT=
	rigAssert "[$sn] an empty download: it stops, saying so"                "$( rigStopped "$rigRc" ) $( rigOut "$sn-i2" 'download is empty' )" "stopped 1"
	rigNew "$sn-i3" ; rm -f "$rigWs/DistroSourceConsole.sh" ; rigRun "$sn-i3" "$1" "$( rigFile 2 install )" RIG_FETCH_OUT='exit 3'
	rigAssert "[$sn] an installer that fails: it stops, saying so"          "$( rigStopped "$rigRc" ) $( rigOut "$sn-i3" 'the workspace installer failed' )" "stopped 1"
	rigNew "$sn-i4" ; rm -f "$rigWs/DistroSourceConsole.sh" ; rigRun "$sn-i4" "$1" "$( rigFile 2 install )" RIG_FETCH_OUT='true'
	rigAssert "[$sn] an installer that produces nothing: it stops, naming the 3 missing" "$( rigStopped "$rigRc" ) $( rigOut "$sn-i4" 'the installer did not produce' )" "stopped 3"
	rigNew "$sn-i5" ; rm -f "$rigWs/DistroSourceConsole.sh"
	rigRun "$sn-i5" "$1" "$( rigFile 2 install )" RIG_FETCH_OUT='mkdir -p "$TGT_APP_PATH/.local/myx/myx.distro-source/sh-lib" "$TGT_APP_PATH/.local/myx/myx.common/os-myx.common" ; : > "$TGT_APP_PATH/DistroSourceConsole.sh"'
	rigAssert "control: an installer that produces everything: exit 0"      "$rigRc" 0

	echo "   [$sn] 4.agents"
	rigT "$sn-ag0" "$1" "$( rigFile 4 agents )"
	rigAssert "[$sn] the agents tooling is there: exit 0, no download"  "$rigRc $( rigHas "$sn-ag0" 'fetch' )" "0 0"
	rigNew "$sn-ag1" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-ag1" "$1" "$( rigFile 4 agents )" RIG_FAIL=fetch
	rigAssert "[$sn] the download fails: it stops with its own ERROR line"  "$( rigStopped "$rigRc" ) $( rigOut "$sn-ag1" 'downloading the workspace installer failed' )" "stopped 1"
	rigNew "$sn-ag2" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-ag2" "$1" "$( rigFile 4 agents )" RIG_FETCH_OUT=
	rigAssert "[$sn] an empty download: it stops, saying so"                "$( rigStopped "$rigRc" ) $( rigOut "$sn-ag2" 'download is empty' )" "stopped 1"
	rigNew "$sn-ag3" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-ag3" "$1" "$( rigFile 4 agents )" RIG_FETCH_OUT='exit 3'
	rigAssert "[$sn] an installer that fails: it stops, saying so"          "$( rigStopped "$rigRc" ) $( rigOut "$sn-ag3" 'the workspace installer failed' )" "stopped 1"
	rigNew "$sn-ag4" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-ag4" "$1" "$( rigFile 4 agents )" RIG_FETCH_OUT='true'
	rigAssert "[$sn] an installer that produces nothing: it stops, naming it"    "$( rigStopped "$rigRc" ) $( rigOut "$sn-ag4" 'the installer did not produce' )" "stopped 1"
	rigNew "$sn-ag5" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh"
	rigRun "$sn-ag5" "$1" "$( rigFile 4 agents )" RIG_FETCH_OUT='mkdir -p "$TGT_APP_PATH/.local/myx/myx.distro-agents/sh-scripts" ; : > "$TGT_APP_PATH/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh"'
	rigAssert "control: an installer that produces the tooling: exit 0"      "$rigRc" 0
	rigNew "$sn-ag6" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh"
	rigRun "$sn-ag6" "$1" "$( rigFile 4 agents )" RIG_FETCH_OUT='mkdir -p "$TGT_APP_PATH/.local/myx/myx.distro-agents/sh-scripts" ; : > "$TGT_APP_PATH/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; exit 4'
	rigAssert "[$sn] an installer that ends late, tooling in place: exit 0, a warning with its status" "$rigRc $( rigOut "$sn-ag6" 'ended with exit 4 after the agents tooling was installed' )" "0 1"

	echo "   [$sn] 3.sources"
	rigNew "$sn-s1" ; mkdir -p "$rigHome/deploy-keys" ; printf 'ssh-ed25519 DEPLOY-PUB rig\n' > "$rigHome/deploy-keys/acct.pub" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s1" "$1" "$( rigFile 3 sources )" $( rigSets )
	rigAssert "[$sn] a declared repository is missing: exit 0, a warning naming it, with the key" "$rigRc $( LC_ALL=C grep -c 'not in the workspace: proj-here' "$rigTmp/$sn-s1/out" || : ) $( rigOut "$sn-s1" 'DEPLOY-PUB' )" "0 1 1"
	rigAssert "[$sn] the clone was tried, and with nothing in the workspace the prepare-and-pull is not run" "$( rigHas "$sn-s1" 'execute-from-stdin-repo-list' ) $( rigHas "$sn-s1" 'execute-source-prepare-pull' )" "1 0"
	rigNew "$sn-s8" ; mkdir -p "$rigHome/deploy-keys" ; printf 'ssh-ed25519 DEPLOY-PUB rig\n' > "$rigHome/deploy-keys/acct.pub" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s8" "$1" "$( rigFile 3 sources )" RIG_FAIL=git $( rigSets )
	rigAssert "[$sn] the deploy key cannot read the repository: exit 0, one warning naming it, with the key" "$rigRc $( rigWarn "$sn-s8" ) $( LC_ALL=C grep -c 'cannot read the repository, left out of the sync: proj-here' "$rigTmp/$sn-s8/out" || : ) $( rigOut "$sn-s8" 'DEPLOY-PUB' )" "0 2 1 1"
	rigAssert "[$sn] and it is not cloned, and nothing is prepared or pulled in an empty workspace" "$( rigHas "$sn-s8" 'git ls-remote' ) $( rigHas "$sn-s8" 'execute-from-stdin-repo-list' ) $( rigHas "$sn-s8" 'execute-source-prepare-pull' )" "1 0 0"
	rigNew "$sn-s9" ; mkdir -p "$rigWs/source/other/proj-there/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s9" "$1" "$( rigFile 3 sources )" RIG_FAIL=git $( rigSets )
	rigAssert "[$sn] another repository is in the workspace: the prepare-and-pull still runs" "$rigRc $( rigHas "$sn-s9" 'execute-from-stdin-repo-list' ) $( rigHas "$sn-s9" 'execute-source-prepare-pull' )" "0 0 1"
	rigNew "$sn-s10" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s10" "$1" "$( rigFile 3 sources )" MDCI_SOURCE_ROOTS=rootA
	rigAssert "[$sn] roots only, no repositories, empty workspace: exit 0, one warning, no sync, no pull" "$rigRc $( rigWarn "$sn-s10" ) $( rigHas "$sn-s10" 'execute-from-stdin-repo-list' ) $( rigHas "$sn-s10" 'execute-source-prepare-pull' )" "0 1 0 0"
	rigNew "$sn-s2" ; mkdir -p "$rigWs/source/proj-here/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s2" "$1" "$( rigFile 3 sources )" $( rigSets )
	rigAssert "[$sn] the repository is present: exit 0 and no output at all" "$rigRc $( rigLines "$rigTmp/$sn-s2/out" )" "0 0"
	rigNew "$sn-s3" ; mkdir -p "$rigWs/source/proj-here/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s3" "$1" "$( rigFile 3 sources )" RIG_PREPARE_RC=3 $( rigSets )
	rigAssert "[$sn] the prepare-and-pull fails: exit 0 and a warning saying so, with its exit status" "$rigRc $( rigOut "$sn-s3" 'source prepare and pull did not complete for every root (exit 3)' )" "0 1"
	rigNew "$sn-s4" ; mkdir -p "$rigWs/source/proj-here/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s4" "$1" "$( rigFile 3 sources )" RIG_SYNC_RC=1 $( rigSets )
	rigAssert "[$sn] the sync exits non-zero though the clone is on disk: exit 0 and a warning" "$rigRc $( rigOut "$sn-s4" 'repository sync did not complete' )" "0 1"
	rigNew "$sn-s5" ; mkdir -p "$rigWs/source/proj-here/.git" ; mkdir -p "$rigHome/deploy-keys" ; : > "$rigHome/deploy-keys/acct"
	rigRun "$sn-s5" "$1" "$( rigFile 3 sources )" RIG_ROOTS_RC=1 $( rigSets )
	rigAssert "[$sn] registering the roots fails: exit 0, a warning, the sync still ran" "$rigRc $( rigOut "$sn-s5" 'registering the source roots did not complete' ) $( rigHas "$sn-s5" 'DistroImageSync --execute-from-stdin-repo-list' )" "0 1 1"
	rigNew "$sn-s6" ; rm -f "$rigWs/DistroSourceConsole.sh" ; rigRun "$sn-s6" "$1" "$( rigFile 3 sources )" $( rigSets )
	rigAssert "[$sn] the source console is missing: exit 0, one warning, no sync" "$rigRc $( rigWarn "$sn-s6" ) $( rigHas "$sn-s6" 'DistroImageSync' )" "0 1 0"
	rigT "$sn-s7" "$1" "$( rigFile 3 sources )"
	rigAssert "[$sn] no sources declared: exit 0, one warning, no sync"      "$rigRc $( rigWarn "$sn-s7" ) $( rigHas "$sn-s7" 'DistroImageSync' )" "0 1 0"

	echo "   [$sn] 5.team-config"
	rigT "$sn-t0" "$1" "$( rigFile 5 team-config )" MDCI_TEAM_DATA_GIT_REMOTE=git@rig:td.git MDCI_TEAM_MEMBERS=magic-coordinator MDCI_MAGIC_COORDINATOR_SLACK_USER_TOKEN=tok-1
	rigAssert "[$sn] a team and a member setting written: exit 0, no warning" "$rigRc $( rigWarn "$sn-t0" ) $( rigHas "$sn-t0" 'TEAM_DATA_GIT_REMOTE value=git@rig:td.git' ) $( rigHas "$sn-t0" 'magic-coordinator --upsert-from-stdin SLACK_USER_TOKEN value=tok-1' )" "0 0 1 1"
	rigNew "$sn-t1" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-t1" "$1" "$( rigFile 5 team-config )" MDCI_TEAM_DATA_GIT_REMOTE=git@rig:td.git
	rigAssert "[$sn] the tooling is missing: exit 0, one warning, nothing written" "$rigRc $( rigWarn "$sn-t1" ) $( rigHas "$sn-t1" 'tools' )" "0 1 0"
	rigT "$sn-t2" "$1" "$( rigFile 5 team-config )" MDCI_TEAM_DATA_GIT_REMOTE=git@rig:td.git
	rigAssert "[$sn] MDCI_TEAM_MEMBERS unset: exit 0, one warning, the team setting still written" "$rigRc $( rigWarn "$sn-t2" ) $( rigHas "$sn-t2" 'TEAM_DATA_GIT_REMOTE' )" "0 1 1"
	rigT "$sn-t3" "$1" "$( rigFile 5 team-config )" MDCI_TEAM_MEMBERS='Bad_Name good-one' MDCI_SLACK_USER_TOKEN=tok-2
	rigAssert "[$sn] a member name that is not a-z 0-9 dash is skipped with a warning, the next one is written" "$rigRc $( rigOut "$sn-t3" 'member Bad_Name was skipped' ) $( rigHas "$sn-t3" 'good-one --upsert-from-stdin SLACK_USER_TOKEN' ) $( rigHas "$sn-t3" 'Bad_Name' )" "0 1 1 0"
	rigT "$sn-t4" "$1" "$( rigFile 5 team-config )" MDCI_TEAM_DATA_GIT_REMOTE=git@rig:td.git MDCI_TEAM_DATA_BRANCH=rigbranch RIG_FAIL_MATCH=TEAM_DATA_GIT_REMOTE
	rigAssert "[$sn] the first upsert fails: exit 0, one warning naming it, the later ones still ran" "$rigRc $( rigOut "$sn-t4" 'setting TEAM_DATA_GIT_REMOTE of magic-team was not written (exit 7)' ) $( rigHas "$sn-t4" 'TEAM_DATA_BRANCH value=rigbranch' )" "0 1 1"
	rigT "$sn-t5" "$1" "$( rigFile 5 team-config )" MDCI_XAI_API_KEY=xk-1 MDCI_TEAM_MEMBERS=magic-coordinator
	rigAssert "[$sn] every spawn key an instance declares is written to the team scope, the xAI one too" "$rigRc $( rigHas "$sn-t5" 'magic-team --upsert-from-stdin XAI_API_KEY value=xk-1' )" "0 1"

	echo "   [$sn] 6.workspace"
	rigT "$sn-w0" "$1" "$( rigFile 6 workspace )" MDCI_TEAM_DATA_DIRECTORY=team-data
	rigAssert "[$sn] everything succeeds: exit 0, no output, the two ops ran in order and nothing else" "$rigRc $( rigLines "$rigTmp/$sn-w0/out" ) $( LC_ALL=C awk '/^tools / { printf "%s ", $2 }' "$rigTmp/$sn-w0/log" )" "0 0 --install-workspace-integrations --install-workspace-restrictions "
	rigAssert "[$sn] the config writer is never called with TEAM_DATA_DIRECTORY, though the variable is set" "$( rigHas "$sn-w0" 'TEAM_DATA_DIRECTORY' ) $( rigHas "$sn-w0" '--agents-config-option' )" "0 0"
	rigNew "$sn-w1" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-w1" "$1" "$( rigFile 6 workspace )"
	rigAssert "[$sn] the tooling is missing: exit 0, one warning"           "$rigRc $( rigWarn "$sn-w1" )" "0 1"
	rigT "$sn-w2" "$1" "$( rigFile 6 workspace )" RIG_FAIL_MATCH=--install-workspace-integrations
	rigAssert "[$sn] integrations fail: exit 0, a warning, the op's own error shown, the restrictions op still ran" "$rigRc $( rigOut "$sn-w2" '--install-workspace-integrations did not reconcile (exit 7)' ) $( rigOut "$sn-w2" 'rig tools op failed' ) $( rigHas "$sn-w2" 'install-workspace-restrictions' )" "0 1 1 1"
	rigT "$sn-w3" "$1" "$( rigFile 6 workspace )" RIG_FAIL_MATCH=--install-workspace-restrictions
	rigAssert "[$sn] restrictions fail: exit 0, a warning, the op's own error shown" "$rigRc $( rigOut "$sn-w3" '--install-workspace-restrictions did not reconcile (exit 7)' ) $( rigOut "$sn-w3" 'rig tools op failed' )" "0 1 1"
	rigNew "$sn-w4" ; printf 'not a directory\n' > "$rigHome/.claude" ; rigRun "$sn-w4" "$1" "$( rigFile 6 workspace )"
	rigAssert "[$sn] the settings seeding fails: exit 0, a warning, both ops still ran" "$rigRc $( rigOut "$sn-w4" 'settings file was not seeded' ) $( rigHas "$sn-w4" 'install-workspace' )" "0 1 2"

	echo "   [$sn] 7.spawn"
	rigT "$sn-v0" "$1" "$( rigFile 7 spawn )" MDCI_SCALEWAY_DEEPSEEK=key-1
	rigAssert "[$sn] a credential declared, both ops ok: exit 0, no warning, both ran, the key on stdin" "$rigRc $( rigWarn "$sn-v0" ) $( rigHas "$sn-v0" '--owner-setup-scaleway' ) $( rigHas "$sn-v0" '--make-workspace-integrations' ) $( rigHas "$sn-v0" 'value=SCALEWAY_DEEPSEEK=key-1' )" "0 0 1 1 1"
	rigT "$sn-v1" "$1" "$( rigFile 7 spawn )" MDCI_SPAWN_CLI_SERVICE=rig-unknown MDCI_SCALEWAY_DEEPSEEK=key-1
	rigAssert "[$sn] an unsupported service: exit 0, one warning, no op"     "$rigRc $( rigWarn "$sn-v1" ) $( rigHas "$sn-v1" 'tools' )" "0 1 0"
	rigT "$sn-v2" "$1" "$( rigFile 7 spawn )"
	rigAssert "[$sn] no credential declared: exit 0, one warning, no op"     "$rigRc $( rigWarn "$sn-v2" ) $( rigHas "$sn-v2" 'tools' )" "0 1 0"
	rigT "$sn-v3" "$1" "$( rigFile 7 spawn )" MDCI_SCALEWAY_DEEPSEEK=key-1 RIG_FAIL_MATCH=--owner-setup-scaleway
	rigAssert "[$sn] the owner setup fails: exit 0, one warning, the integrations still ran" "$rigRc $( rigWarn "$sn-v3" ) $( rigHas "$sn-v3" '--make-workspace-integrations' )" "0 1 1"
	rigT "$sn-v4" "$1" "$( rigFile 7 spawn )" MDCI_SCALEWAY_DEEPSEEK=key-1 RIG_FAIL_MATCH=--make-workspace-integrations
	rigAssert "[$sn] the integrations fail: exit 0 and one warning"          "$rigRc $( rigWarn "$sn-v4" )" "0 1"
	rigT "$sn-v5" "$1" "$( rigFile 7 spawn )" MDCI_SPAWN_CLI_SERVICE=claude MDCI_ANTHROPIC_API_KEY=ak-1
	rigAssert "[$sn] the claude service takes its own key table"             "$rigRc $( rigHas "$sn-v5" '--owner-setup-claude' ) $( rigHas "$sn-v5" 'value=ANTHROPIC_API_KEY=ak-1' )" "0 1 1"

	echo "   [$sn] 8.ownership"
	rigT "$sn-o0" "$1" "$( rigFile 8 ownership )"
	rigAssert "[$sn] everything succeeds: exit 0, no warning or error"       "$rigRc $( rigWarn "$sn-o0" ) $( rigErr "$sn-o0" )" "0 0 0"
	rigT "$sn-o1" "$1" "$( rigFile 8 ownership )" RIG_FAIL=chown
	rigAssert "[$sn] the home ownership step fails: it stops with its own ERROR line" "$( rigStopped "$rigRc" ) $( rigErr "$sn-o1" )" "stopped 1"
	rigNew "$sn-o2" ; mkdir -p "$rigWs/.local/closed" ; : > "$rigWs/.local/closed/file" ; chmod 600 "$rigWs/.local/closed/file" ; chmod 700 "$rigWs/.local/closed"
	rigRun "$sn-o2" "$1" "$( rigFile 8 ownership )"
	rigAssert "[$sn] the workspace is shared by the account group: a closed directory and a closed file in it become group read-write" \
		"$rigRc $( ls -ld "$rigWs/.local/closed" | LC_ALL=C cut -c2-10 ) $( ls -l "$rigWs/.local/closed/file" | LC_ALL=C cut -c2-10 )" "0 rwxrwx--- rw-rw----"

	echo "   [$sn] 9.team-data"
	rigT "$sn-n0" "$1" "$( rigFile 9 team-data )" MDCI_TEAM_DATA_DIRECTORY=team-data MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1
	rigAssert "[$sn] everything declared and ok: exit 0, no warning, storage then slack" "$rigRc $( rigWarn "$sn-n0" ) $( rigHas "$sn-n0" '--owner-setup-storage' ) $( rigHas "$sn-n0" '--owner-setup-slack' )" "0 0 1 1"
	rigAssert "[$sn] the storage call passes the directory that was set, and --apply is its last argument" "$( rigHas "$sn-n0" '--owner-setup-storage --workspace-root '"$rigWs"' --team-data-directory team-data --apply' )" 1
	rigT "$sn-n1" "$1" "$( rigFile 9 team-data )" MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1
	rigAssert "[$sn] the team data directory unset: exit 0 and no warning about it" "$rigRc $( rigWarn "$sn-n1" ) $( rigOut "$sn-n1" 'MDCI_TEAM_DATA_DIRECTORY' )" "0 0 0"
	rigAssert "[$sn] the storage domain is still called, without --team-data-directory" "$( rigHas "$sn-n1" '--owner-setup-storage' ) $( rigHas "$sn-n1" '--team-data-directory' )" "1 0"
	rigAssert "[$sn] the default directory inside the workspace was made, as the account" "$( rigHas "$sn-n1" "mkdir -p $rigWs/.local/agents/team-data-root" )" 1
	rigT "$sn-n1b" "$1" "$( rigFile 9 team-data )" MDCI_TEAM_DATA_GIT_REMOTE=git@rig:td.git MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1
	rigAssert "[$sn] the remote is passed only when set, still before --apply" "$( rigHas "$sn-n1b" '--owner-setup-storage --workspace-root '"$rigWs"' --team-data-git-remote git@rig:td.git --apply' ) $( rigHas "$sn-n1" '--team-data-git-remote' )" "1 0"
	rigT "$sn-n2" "$1" "$( rigFile 9 team-data )" MDCI_TEAM_DATA_DIRECTORY=team-data MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1 RIG_FAIL_MATCH=--owner-setup-storage
	rigAssert "[$sn] the storage op fails: exit 0, one warning, the slack setup still ran" "$rigRc $( rigWarn "$sn-n2" ) $( rigHas "$sn-n2" '--owner-setup-slack' )" "0 1 1"
	rigT "$sn-n3" "$1" "$( rigFile 9 team-data )" MDCI_TEAM_DATA_DIRECTORY=team-data MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1 RIG_FAIL_MATCH=--owner-setup-slack
	rigAssert "[$sn] the slack op fails: exit 0, one warning" "$rigRc $( rigWarn "$sn-n3" )" "0 1"
	rigT "$sn-n4" "$1" "$( rigFile 9 team-data )" MDCI_TEAM_DATA_DIRECTORY=team-data
	rigAssert "[$sn] no slack channels: exit 0, one warning" "$rigRc $( rigWarn "$sn-n4" )" "0 1"
	rigT "$sn-n5" "$1" "$( rigFile 9 team-data )" MDCI_TEAM_DATA_DIRECTORY=team-data MDCI_SLACK_CHANNEL_MAGIC_TEAM=C1 MDCI_SLACK_CHANNEL_HUMAN_OWNER=U1 RIG_FAIL=mkdir
	rigAssert "[$sn] the team data directory cannot be made: exit 0 and one warning naming it" "$rigRc $( rigOut "$sn-n5" 'could not create' )" "0 1"

	echo "   [$sn] 10.daemon"
	rigT "$sn-d0" "$1" "$( rigFile 10 daemon )"
	rigAssert "[$sn] everything succeeds: exit 0, no warning, the restart then the status last" "$rigRc $( rigWarn "$sn-d0" ) $( LC_ALL=C tail -2 "$rigTmp/$sn-d0/log" | LC_ALL=C tr '\n' '|' )" "0 0 service mdcid restart|service mdcid status|"
	rigAssert "[$sn] a passing status prints nothing"                       "$( rigLines "$rigTmp/$sn-d0/out" )" 0
	rigT "$sn-d1" "$1" "$( rigFile 10 daemon )" RIG_STATUS_FAIL=1
	rigAssert "[$sn] the status after the restart fails: exit 0 and one warning that it does not report running" "$rigRc $( rigWarn "$sn-d1" ) $( rigOut "$sn-d1" 'does not report running after the restart' )" "0 1 1"
	echo "   [$sn] 10.daemon: the three enable-state cases"
	rigAssert "[$sn] first install, no enable state yet: mdcid_enable is set to YES before the restart" "$( rigHas "$sn-d0" 'sysrc mdcid_enable=YES' )" 1
	rigT "$sn-d2" "$1" "$( rigFile 10 daemon )" RIG_RC_ENABLE=YES
	rigAssert "[$sn] already enabled: exit 0, no warning, the enable state is left alone" "$rigRc $( rigWarn "$sn-d2" ) $( rigHas "$sn-d2" 'mdcid_enable=' )" "0 0 0"
	rigAssert "[$sn] and the daemon still restarts, user and group still set" "$( rigHas "$sn-d2" 'service mdcid restart' ) $( rigHas "$sn-d2" 'mdcid_user=' ) $( rigHas "$sn-d2" 'mdcid_group=' )" "1 1 1"
	rigT "$sn-d3" "$1" "$( rigFile 10 daemon )" RIG_RC_ENABLE=NO
	rigAssert "[$sn] disabled: exit 0, no warning, no error, the enable state is left alone" "$rigRc $( rigWarn "$sn-d3" ) $( rigErr "$sn-d3" ) $( rigHas "$sn-d3" 'mdcid_enable=' )" "0 0 0 0"
	rigAssert "[$sn] and it is not started: no service call, user and group still set" "$( rigHas "$sn-d3" 'service' ) $( rigHas "$sn-d3" 'mdcid_user=' ) $( rigHas "$sn-d3" 'mdcid_group=' )" "0 1 1"
	rigT "$sn-d4" "$1" "$( rigFile 10 daemon )" RIG_RC_ENABLE=no
	rigAssert "[$sn] disabled, stored lower case: exit 0, no warning, no error, no service call" "$rigRc $( rigWarn "$sn-d4" ) $( rigErr "$sn-d4" ) $( rigHas "$sn-d4" 'service' )" "0 0 0 0"
	echo "   [$sn] the kept stops of 10.daemon"
	rigNew "$sn-y1" ; chmod -x "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "$sn-y1" "$1" "$( rigFile 10 daemon )"
	rigAssert "[$sn] the toolchain is not executable: it stops with its own ERROR line, nothing after it ran" "$( rigStopped "$rigRc" ) $( rigErr "$sn-y1" ) $( rigHas "$sn-y1" 'sysrc' ) $( rigHas "$sn-y1" 'service' )" "stopped 1 0 0"
	rigT "$sn-y3" "$1" "$( rigFile 10 daemon )" RIG_FAIL=sysrc
	rigAssert "[$sn] a sysrc call fails: it stops with its own ERROR line before the restart" "$( rigStopped "$rigRc" ) $( rigErr "$sn-y3" ) $( rigHas "$sn-y3" 'service' )" "stopped 1 0"
	rigT "$sn-y4" "$1" "$( rigFile 10 daemon )" RIG_FAIL=service
	rigAssert "[$sn] the restart fails: it stops with its own ERROR line, and the status was never asked" "$( rigStopped "$rigRc" ) $( rigErr "$sn-y4" ) $( rigHas "$sn-y4" 'service mdcid restart' ) $( rigHas "$sn-y4" 'service mdcid status' )" "stopped 1 1 0"
}

echo "-- 9b. mdci-settings-apply, run: no argument and a domain --"
rigNew "apply0" ; rigRun "apply0" /bin/sh "$rigFeature/data/os-commands/mdci-settings-apply"
rigAssert "mdci-settings-apply with no argument: exit 1, the error line first, then the syntax line" "$rigRc $( LC_ALL=C sed -n 1p "$rigTmp/apply0/out" | LC_ALL=C grep -c '^⛔ ERROR: mdci-settings-apply: ' || : ) $( LC_ALL=C sed -n 2p "$rigTmp/apply0/out" | LC_ALL=C grep -c '^📘 syntax: ' || : )" "1 1 1"
rigNew "apply1" ; rigRun "apply1" /bin/sh "$rigFeature/data/os-commands/mdci-settings-apply" RIG_ARGS=slack
rigAssert "control: with a domain it calls the tooling for that domain and prints nothing" "$rigRc $( rigHas "apply1" "--owner-setup-slack --workspace-root $rigWs --values-from-stdin --apply" ) $( rigLines "$rigTmp/apply1/out" )" "0 1 0"
rigNew "once0" ; rigRun "once0" /bin/sh "$rigFeature/data/os-commands/mdci-main-loop-once"
rigAssert "mdci-main-loop-once runs one iteration with the tooling of workspace.mdci" "$rigRc $( rigHas "once0" 'tools --intern-main-loop --one' )" "0 1"
rigNew "once1" ; rm -f "$rigWs/.local/myx/myx.distro-agents/sh-scripts/DistroAgentsTools.fn.sh" ; rigRun "once1" /bin/sh "$rigFeature/data/os-commands/mdci-main-loop-once"
rigAssert "control: without that tooling it fails" "$( [ "$rigRc" -ne 0 ] && printf failed || printf ran ) $( rigHas "once1" 'tools' )" "failed 0"

echo "-- 9c. the console line against a profile that holds it above the login line of setup/console, edited by the real lib/replaceLine --"
rigReplaceLine="$( myx.common which lib/replaceLine 2> /dev/null )" || rigReplaceLine=""
if [ -z "$rigReplaceLine" ] || [ ! -f "$rigReplaceLine" ] ; then
	echo "   skipped: myx.common is not on PATH, so the real lib/replaceLine could not be run"
else
	mkdir -p "$rigTmp/stubs-profile"
	for rigCmd in sudo chown chflags mkdir rsync fetch sysrc service monit git ssh-keygen bash ; do
		cp "$rigFixtures/mdci-fragments-check.command.test.sh" "$rigTmp/stubs-profile/$rigCmd" && chmod +x "$rigTmp/stubs-profile/$rigCmd"
	done
	cp "$rigFixtures/mdci-fragments-check.profile.test.sh" "$rigTmp/stubs-profile/myx.common" && chmod +x "$rigTmp/stubs-profile/myx.common"
	rigNew "order0"
	rigUserHome="$rigTmp/order0/userhome" ; mkdir -p "$rigUserHome"
	printf 'printf "login-include\\n" >> "$RIG_SESSIONS"\n' > "$rigTmp/order0/login-include"
	printf '#!/bin/sh\nprintf "console MMDAPP=%%s\\n" "$MMDAPP" >> "$RIG_SESSIONS"\n' > "$rigWs/DistroSourceConsole.sh" ; chmod +x "$rigWs/DistroSourceConsole.sh"
	printf '%s\n' "test -x $rigWs/DistroSourceConsole.sh && MMDAPP=$rigWs && . $rigWs/DistroSourceConsole.sh ### MMDAPP console autostart ###" "source $rigTmp/order0/login-include  ### myx.common setup/console ###" > "$rigUserHome/.bash_profile"
	rigLogin(){ ## -- that profile sourced by a fresh bash, as a login outside screen; prints what ran, in order
		: > "$rigTmp/order0/sessions"
		env -i PATH=/usr/bin:/bin HOME="$rigUserHome" RIG_SESSIONS="$rigTmp/order0/sessions" bash -c '. "$HOME/.bash_profile"' > /dev/null 2>&1
		LC_ALL=C tr '\n' '|' < "$rigTmp/order0/sessions"
	}
	rigProfileOrder(){ ## -- last, when the profile holds one console line, as its last line, below the login line of setup/console
		LC_ALL=C awk '/ ### myx.common setup\/console ###$/ { login = NR } / ### MMDAPP console autostart ###$/ { line = NR ; count++ } END { print ( count == 1 && login && line > login && line == NR ) ? "last" : "not-last" }' "$rigUserHome/.bash_profile"
	}
	rigAssert "control: the profile starts with the console line above the login line, and a login starts the console first" "$( rigProfileOrder ) $( rigLogin )" "not-last console MMDAPP=$rigWs|login-include|"
	rigRun "order0" /bin/sh "$( rigFile 0 prepare )" PATH="$rigTmp/stubs-profile:/bin:/usr/bin" HOME="$rigUserHome" RIG_REPLACELINE="$rigReplaceLine" RIG_LOGIN_INCLUDE="$rigTmp/order0/login-include"
	rigAssert "one deploy leaves that profile with one console line, the last line, below the login line of setup/console" "$rigRc $( rigProfileOrder )" "0 last"
	rigAssert "a login outside screen then reaches the login include, which starts screen, before any console start" "$( rigLogin )" "login-include|console MMDAPP=$rigWs|"
	rigAssert "the console line holds no dollar sign, which sudo -s would leave for its own shell to expand" "$( LC_ALL=C tail -n 1 "$rigUserHome/.bash_profile" | LC_ALL=C grep -c -F '$' )" 0
	rigRun "order0" /bin/sh "$( rigFile 0 prepare )" PATH="$rigTmp/stubs-profile:/bin:/usr/bin" HOME="$rigUserHome" RIG_REPLACELINE="$rigReplaceLine" RIG_LOGIN_INCLUDE="$rigTmp/order0/login-include"
	rigAssert "a second deploy keeps it so" "$rigRc $( rigProfileOrder ) $( rigLogin )" "0 last login-include|console MMDAPP=$rigWs|"
fi

echo "-- 9d. mdci-console: installed with the other commands; run by root, by a member of the account group, and by anyone else --"
rigConsole="$rigFeature/data/os-commands/mdci-console"
rigFloorInf="$rigHere/../../setup.machine-freebsd/project.inf"
rigAssert "mdci-console is a /bin/sh script in data/os-commands, and the floor syncs that directory of every project" "$( [ -f "$rigConsole" ] && LC_ALL=C sed -n 1p "$rigConsole" ) $( rigN "$rigFloorInf" 'image-prepare:sync-source-files:**:data/os-commands:os-commands' )" '#!/bin/sh 1'
rigAssert "control: the same reading finds no sync of a directory the floor does not name" "$( rigN "$rigFloorInf" 'image-prepare:sync-source-files:**:data/os-commands-none:' )" 0
rigConsoleStub(){ ## -- the workspace console of the current rig replaced by one that logs the MMDAPP it is given
	printf '#!/bin/sh\necho "console MMDAPP=$MMDAPP" >> "$RIG_LOG"\n' > "$rigWs/DistroSourceConsole.sh" ; chmod +x "$rigWs/DistroSourceConsole.sh"
}
rigNew "con0" ; rigConsoleStub ; rigRun "con0" /bin/sh "$rigConsole" RIG_UID=501 RIG_RC_USER=acct RIG_GROUPS="staff wheel xacct acct-x"
rigAssert "mdci-console by a user outside the account group: exit 1, its own ERROR line, no sudo call and no console" "$rigRc $( LC_ALL=C sed -n 1p "$rigTmp/con0/out" | LC_ALL=C grep -c '^⛔ ERROR: mdci-console: ' || : ) $( rigN "$rigTmp/con0/log" 'sudo ' ) $( rigN "$rigTmp/con0/log" 'console ' )" "1 1 0 0"
rigNew "con1" ; rigConsoleStub ; mkdir -p "$rigTmp/con1/accthome"
printf '%s\n' "test -x $rigWs/DistroSourceConsole.sh && MMDAPP=$rigWs && . $rigWs/DistroSourceConsole.sh ### MMDAPP console autostart ###" > "$rigTmp/con1/accthome/.bash_profile"
rigRun "con1" /bin/sh "$rigConsole" RIG_UID=0 RIG_RC_USER=acct HOME="$rigTmp/con1/accthome"
rigAssert "mdci-console by root: one sudo call, a login session of the account that starts a login bash" "$rigRc $( rigN "$rigTmp/con1/log" 'sudo ' ) $( rigN "$rigTmp/con1/log" 'sudo -u acct -H -i bash -l' )" "0 1 1"
rigAssert "and that bash reads the .bash_profile of its home, whose console line starts the console of workspace.mdci" "$( rigN "$rigTmp/con1/log" "console MMDAPP=$rigWs" )" 1
rigNew "con2" ; rigConsoleStub ; rigRun "con2" /bin/sh "$rigConsole" RIG_UID=501 RIG_RC_USER=acct RIG_GROUPS="staff acct wheel"
rigAssert "mdci-console by a member of the account group: the console of workspace.mdci as that user, MMDAPP set to it, no sudo call" "$rigRc $( rigN "$rigTmp/con2/log" "console MMDAPP=$rigWs" ) $( rigN "$rigTmp/con2/log" 'sudo ' )" "0 1 0"

echo "-- 9e. mdci-public-keys: run by another user, and by the account with a key and two repositories --"
rigKeysCmd="$rigFeature/data/os-commands/mdci-public-keys"
rigAssert "mdci-public-keys is a /bin/sh script in data/os-commands" "$( [ -f "$rigKeysCmd" ] && LC_ALL=C sed -n 1p "$rigKeysCmd" )" '#!/bin/sh'
rigNew "pk0" ; rigRun "pk0" /bin/sh "$rigKeysCmd" RIG_UID=501 RIG_USERNAME=bob RIG_RC_USER=acct
rigAssert "mdci-public-keys by another user: exit 1, its own ERROR line first, no key printed" "$rigRc $( LC_ALL=C sed -n 1p "$rigTmp/pk0/out" | LC_ALL=C grep -c '^⛔ ERROR: mdci-public-keys: ' || : ) $( rigOut pk0 'ssh-ed25519' )" "1 1 0"
rigNew "pk1" ; mkdir -p "$rigHome/deploy-keys" ; printf 'ssh-ed25519 DEPLOY-PUB rig\n' > "$rigHome/deploy-keys/acct.pub" ; : > "$rigHome/deploy-keys/acct"
printf 'proj-here\tgit@rig.example:org/proj-here.git\nproj-there\tssh://git@rig2.example:2222/org2/proj-there.git\n' > "$rigHome/.mdci-source-repos.txt"
mkdir -p "$rigWs/.local/.agents" ; printf 'TEAM_DATA_GIT_REMOTE=git@rig.example:org/board.git\nSLACK_BOT_TOKEN=must-not-appear\n' > "$rigWs/.local/.agents/magic-team.agent.env"
rigRun "pk1" /bin/sh "$rigKeysCmd" RIG_UID=501 RIG_USERNAME=acct RIG_RC_USER=acct RIG_FAIL=git
rigAssert "mdci-public-keys by the account: exit 0, the public key line, the key file named" "$rigRc $( rigOut pk1 'ssh-ed25519 DEPLOY-PUB rig' ) $( rigOut pk1 "$rigHome/deploy-keys/acct" )" "0 1 1"
rigAssert "and both source repositories and the team data remote are listed, each with its host and path, none readable by this rig's git" "$( rigOut pk1 'NOT readable with this key yet' ) $( rigOut pk1 'host and path: rig.example  org/proj-here.git' ) $( rigOut pk1 'host and path: rig2.example  org2/proj-there.git' ) $( rigOut pk1 'host and path: rig.example  org/board.git' )" "3 1 1 1"
rigAssert "and no secret of the team settings file is printed" "$( rigOut pk1 'must-not-appear' )" 0
rigRun "pk1" /bin/sh "$rigKeysCmd" RIG_UID=501 RIG_USERNAME=acct RIG_RC_USER=acct
rigAssert "with git able to read them the same listing says so for all three" "$rigRc $( rigOut pk1 'the key can read it' ) $( rigOut pk1 'NOT readable' )" "0 3 0"
rigNew "pk3" ; mkdir -p "$rigWs/.local/myx/tool-a/.git" "$rigWs/.local/myx/tool-b/inner/.git"
rigRun "pk3" /bin/sh "$rigKeysCmd" RIG_UID=501 RIG_USERNAME=acct RIG_RC_USER=acct RIG_GIT_ORIGIN=git@rig.example:myx/tool.git RIG_FAIL=ssh-keygen
rigAssert "the installed tool clones are listed with their origin, one level and two levels down, and the answer of git for each" "$rigRc $( rigOut pk3 'tool-a' ) $( rigOut pk3 'inner' ) $( rigOut pk3 'host and path: rig.example  myx/tool.git' ) $( rigOut pk3 'the key can read it' )" "0 1 1 2 2"
rigNew "pk2" ; rigRun "pk2" /bin/sh "$rigKeysCmd" RIG_UID=501 RIG_USERNAME=acct RIG_RC_USER=acct
rigAssert "no tool clone installed: the tool section says none" "$( rigOut pk2 'none: no installed tool clone' )" 1
rigAssert "a rig with no key and nothing declared: exit 0, a warning for the key, and the list says none" "$rigRc $( rigOut pk2 'no public key could be read' ) $( rigOut pk2 'none: this rig declares no source repository' )" "0 1 1"

echo "-- 9f. mdci-update: run by another user, and by the account itself without sudo --"
rigUpdateCmd="$rigFeature/data/os-commands/mdci-update"
rigAssert "mdci-update: every stderr line is emoji-first with its label" "$( rigBadLabel "$rigUpdateCmd" mdci-update )" 0
rigUpdateTool(){ ## -- the upgrade tool of the current rig replaced by one that logs the variables it was started with
	mkdir -p "$rigWs/.local/myx/myx.distro-.local/sh-scripts"
	printf '#!/bin/sh\necho "tool MMDAPP=${MMDAPP:-unset} MDLT_ORIGIN=${MDLT_ORIGIN:-unset} $*" >> "$RIG_LOG"\n' > "$rigWs/.local/myx/myx.distro-.local/sh-scripts/DistroLocalTools.fn.sh"
	chmod +x "$rigWs/.local/myx/myx.distro-.local/sh-scripts/DistroLocalTools.fn.sh"
}
rigNew "up0" ; rigUpdateTool ; rigRun "up0" /bin/sh "$rigUpdateCmd" RIG_UID=501 RIG_USERNAME=bob RIG_RC_USER=acct
rigAssert "mdci-update by another user: exit 1, its own ERROR line first, the tool not started" "$rigRc $( LC_ALL=C sed -n 1p "$rigTmp/up0/out" | LC_ALL=C grep -c '^⛔ ERROR: mdci-update: ' || : ) $( rigN "$rigTmp/up0/log" 'tool ' )" "1 1 0"
rigNew "up1" ; rigUpdateTool ; rigRun "up1" /bin/sh "$rigUpdateCmd" RIG_UID=501 RIG_USERNAME=acct RIG_RC_USER=acct MMDAPP=/elsewhere MDLT_ORIGIN=/elsewhere/.local
rigAssert "mdci-update by the account: exit 0, no sudo call, the upgrade started once with the console variables of the caller removed" "$rigRc $( rigN "$rigTmp/up1/log" 'sudo ' ) $( rigN "$rigTmp/up1/log" 'tool MMDAPP=unset MDLT_ORIGIN=unset --upgrade-installed-tools' )" "0 0 1"

for rigShell in /bin/sh /bin/dash ; do
	echo "-- fragments run under $rigShell --"
	rigAllFail "$rigShell"
	rigGuards "$rigShell"
	rigKeys "$rigShell"
	rigBehaviour "$rigShell"
done

rigInstallerOrder(){ ## installer file -- "<fragments seen in order, space separated>"
	LC_ALL=C awk '/^##\*\*--  start, .*common-mdci\.[0-9]\./ { name = $0 ; sub(/.*common-mdci\./, "", name) ; sub(/\..*/, "", name) ; seen = seen name " " } END { print seen }' "$1"
}
rigInstallerCloses(){ ## installer file -- how many mdci fragment blocks close with the subshell line followed at once by the status capture
	LC_ALL=C awk '
		/^##\*\*--  start, .*common-mdci\.[0-9]\./ { inMdci = 1 ; next }
		inMdci && $0 == ")\" )" { closeLine = NR ; next }
		inMdci && closeLine && NR == closeLine + 1 { if ( $0 == "mdscFragmentRc=$?" ) { n++ } ; inMdci = 0 ; closeLine = 0 }
		END { print n + 0 }' "$1"
}
echo "-- 11. the generated installer of an instance project, from live source --"
if [ -z "${RIG_MDCI_INSTANCE_PROJECT:-}" ] ; then
	echo "   skipped: RIG_MDCI_INSTANCE_PROJECT is not set, so no instance project is named and nothing was generated"
else
	rigDeployCmd="${MDLT_ORIGIN:-}/myx/myx.distro-deploy/sh-scripts/DeployProjectSsh.fn.sh"
	rigCacheFolder="${MMDAPP:-}/output/deploy/$RIG_MDCI_INSTANCE_PROJECT"
	if [ -z "${MMDAPP:-}" ] || [ -z "${MDLT_ORIGIN:-}" ] || [ ! -f "$rigDeployCmd" ] ; then
		echo "   skipped: MMDAPP and MDLT_ORIGIN must name a workspace with the deploy package, and $rigDeployCmd was not found"
	elif [ -e "$rigCacheFolder" ] ; then
		echo "   skipped: $rigCacheFolder already exists, and this row does not touch an existing cache"
	else
		rigSaved="$( cd "$MMDAPP" && bash "$rigDeployCmd" --project "$RIG_MDCI_INSTANCE_PROJECT" --prepare-full --save-full-script 2> "$rigTmp/gen.err" | LC_ALL=C tail -1 )"
		rigAssert "the generator printed the path of the saved installer, under this workspace's cache" "$( case "$rigSaved" in "$rigCacheFolder"/*) printf yes ;; *) printf no ;; esac )" yes
		if [ -f "$rigSaved" ] ; then
			rigAssert "the installer parses under dash"                           "$( /bin/dash -n "$rigSaved" > /dev/null 2>&1 && printf ok )" ok
			rigAssert "each mdci fragment is in it once, in order 0 to 10"          "$( rigInstallerOrder "$rigSaved" )" "0 1 2 3 4 5 6 7 8 9 10 "
			rigAssert "each of them closes its subshell with the status capture on the next line" "$( rigInstallerCloses "$rigSaved" )" 11
		fi
		## What this row made is removed: the folder did not exist before it ran, so everything in it is its own.
		rm -rf -- "$rigCacheFolder"
		rigAssert "control: the cache folder the row made is gone again"           "$( [ -e "$rigCacheFolder" ] && printf present || printf gone )" gone
	fi
fi
printf '#!/bin/sh\n##**--  start, /x/common-mdci.0.prepare.txt\n( set -e ; eval "$( cat << BLK\ntrue\nBLK\n)" )\nmdscFragmentRc=$?\n##**--  start, /x/common-mdci.1.deploy-keys.txt\n( set -e ; eval "$( cat << BLK\ntrue\nBLK\n)" )\necho between\nmdscFragmentRc=$?\n' > "$rigTmp/samples/installer.sh"
rigAssert "control: the order reader reads the two blocks of a sample"       "$( rigInstallerOrder "$rigTmp/samples/installer.sh" )" "0 1 "
rigAssert "control: the close reader counts the block with the capture at once, not the one with a line between" "$( rigInstallerCloses "$rigTmp/samples/installer.sh" )" 1

if [ "$rigFailCount" -ne 0 ] ; then
	echo "⛔ MDCI FRAGMENTS CHECK FAILED: $rigFailCount of $(( rigPassCount + rigFailCount )) assertion(s)" >&2 ; exit 1
fi
printf 'MDCI_FRAGMENTS: OK (%d assertions, offline, stubs only, fragments run under /bin/sh and dash)\n' "$rigPassCount"
