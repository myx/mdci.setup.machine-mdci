#!/usr/bin/env bash
## The deploy-key requirement, checked against the fragment that places the keys:
## `setup.machine-mdci/host/install/common-mdci.1.deploy-keys.txt`, run rather than read, offline.
##
## The requirement: when an instance project's `data/deploy-keys` lacks `mdci`, `mdci.pub` or `known_hosts`, the installer
## creates whichever is missing, and an existing key is never overwritten. The key is `ssh-keygen -t ed25519` with an
## empty passphrase, its comment is `magic-team-board-<ns>`, and it lands at `deploy-keys/mdci`. The forge's host keys are
## pinned into `known_hosts`. The installer prints the public key and says where it must be listed as a deploy key.
##
## Three cases, one per state of the instance's folder: all three absent, one present, all three present. Each run is one
## `env -i` whose PATH is the stubs and /bin only, with the fragment's own external commands stubbed
## (`check-fixtures/mdci-deploy-key-bootstrap-check.command.test.sh`), so nothing here reaches a host, a forge or a key.
## The landing read is `$MDCI_HOME/deploy-keys`, the folder `1.deploy-keys` syncs into: the fragment runs on the host, so
## what it creates is readable there and nowhere else. RIG_FRAGMENT points at another copy of the fragment (the fail-first).
## NOT held: whether the forge accepts the public half. Registering a deploy key is a remote action, so no row here says the
## key works, only that the installer made one and said where to list it. Not measured on FreeBSD or under dash: the
## fragment is `#!/bin/sh` and shell portability is `MdciFragmentsCheck`'s own row.
set -u
rigHere="$( cd "$( dirname "$0" )" && pwd -P )" || exit 1
rigFeature="${RIG_FEATURE:-${rigHere%/sh-test}}"
rigFragment="${RIG_FRAGMENT:-$rigFeature/host/install/common-mdci.1.deploy-keys.txt}"
rigStubSource="$rigHere/check-fixtures/mdci-deploy-key-bootstrap-check.command.test.sh"
rigStubCommands="sudo mkdir chmod chown git hostname id rsync ssh-keygen ssh-keyscan"

rigRefuse(){
	echo "⛔ ERROR: $1 -- refusing to report a result" >&2 ; exit 1
}
[ -f "$rigFragment" ] || rigRefuse "missing fragment: $rigFragment"
[ -f "$rigStubSource" ] || rigRefuse "missing stub: $rigStubSource"
[ -n "${MMDAPP:-}" ] && [ -d "${MMDAPP:-}" ] || rigRefuse "MMDAPP names no workspace, and a rig's files never go in the system temp folder"

rigScratch="$MMDAPP/.local/agents/scratch/sh-test"
mkdir -p "$rigScratch" || exit 1
rigTmp="$( mktemp -d "$rigScratch/MdciDeployKeyBootstrapCheck.XXXXXXXX" )" || exit 1
rigTmp="$( cd "$rigTmp" && pwd -P )" || exit 1
trap 'chmod -R u+rwX -- "$rigTmp" 2> /dev/null ; rm -rf -- "$rigTmp"' EXIT

rigStubs="$rigTmp/stubs"
mkdir -p "$rigStubs" || exit 1
for rigCommand in $rigStubCommands ; do
	cp "$rigStubSource" "$rigStubs/$rigCommand" || exit 1
	chmod +x "$rigStubs/$rigCommand" || exit 1
done
## The run's PATH is a controlled environment. The stubs come first, so a stubbed command can never reach the host's own;
## `/bin` and `/usr/bin` are behind them for the four commands the fragment calls and no row here decides (`awk`, `mv`,
## `cp` inside the rsync stub, and `sh` itself). A stubbed command that does not resolve to its stub is a rig fault.
rigRunPath="$rigStubs:/bin:/usr/bin"
for rigCommand in $rigStubCommands ; do
	rigResolved="$( env -i PATH="$rigRunPath" sh -c "command -v $rigCommand" 2> /dev/null )" || :
	[ "$rigResolved" = "$rigStubs/$rigCommand" ] || rigRefuse "$rigCommand does not resolve to its stub under the run's PATH"
done

rigPassCount=0
rigFailCount=0
rigAssert(){ ## what, got, want
	if [ "$2" = "$3" ] ; then
		printf '  PASS  %s\n' "$1" ; rigPassCount=$(( rigPassCount + 1 ))
	else
		printf '  FAIL  %s\n        got:  %s\n        want: %s\n' "$1" "$2" "$3" ; rigFailCount=$(( rigFailCount + 1 ))
	fi
}
rigPresent(){ ## path -- present or absent
	[ -e "$1" ] && printf present || printf absent
}
rigIdentical(){ ## file, reference -- identical or differs
	[ -f "$1" ] && cmp -s "$1" "$2" && printf identical || printf differs
}
rigSaid(){ ## case name, text -- lines of that run's output holding it
	LC_ALL=C grep -c -F -- "$2" "$rigTmp/out.$1" 2> /dev/null || :
}
rigPinned(){ ## file -- the hosts it pins, sorted and unique, from its host-key lines only
	[ -f "$1" ] || { printf 'no-file' ; return 0 ; }
	LC_ALL=C awk '$1 !~ /^#/ && $2 ~ /^(ssh-|ecdsa-)/ { print $1 }' "$1" 2> /dev/null | LC_ALL=C sort -u | LC_ALL=C tr '\n' ' ' | LC_ALL=C sed 's/ $//'
}
rigPinnedCount(){ ## file -- how many host-key lines it holds, for the reader's own self-test
	[ -f "$1" ] || { printf 'no-file' ; return 0 ; }
	LC_ALL=C grep -c -E '^[^#[:space:]]+ (ssh-|ecdsa-)' "$1" 2> /dev/null || :
}
rigKeygenAfter(){ ## flag -- the argument that follows it in the ssh-keygen call, empty when that argument is empty
	LC_ALL=C awk -v flag="arg:$1" '$0 == flag { getline ; sub(/^arg:/, "") ; print ; exit }' "$rigKeygenLog" 2> /dev/null
}
rigKeygenEmptyPassphrase(){ ## -- how many -N flags are followed by an empty argument
	LC_ALL=C awk '$0 == "arg:-N" { getline ; if ($0 == "arg:") n++ } END { print n + 0 }' "$rigKeygenLog" 2> /dev/null || :
}
rigCommentNames(){ ## -- `ok` when the comment is magic-team-board- with something after it
	rigCommentValue="$( rigKeygenAfter -C )"
	case "$rigCommentValue" in
		'') printf 'no-comment' ;;
		magic-team-board-) printf 'empty-namespace' ;;
		magic-team-board-*) printf ok ;;
		*) printf 'no-prefix' ;;
	esac
}

rigNewCase(){ ## name -- an empty case folder, its landing and its staging folder
	rigCase="$rigTmp/case.$1"
	rm -rf "$rigCase" || exit 1
	rigHome="$rigCase/home"
	rigStaged="$rigCase/files/mdci-deploy-keys"
	mkdir -p "$rigHome" "$rigStaged" || exit 1
	rigLanding="$rigHome/deploy-keys"
	rigRef="$rigTmp/ref.$1"
}
rigStage(){ ## name, text -- a file of that name in the staging folder
	printf '%s\n' "$2" > "$rigStaged/$1" || exit 1
}
rigRun(){ ## name -- the fragment once, against the case folder just made
	rigLog="$rigTmp/log.$1"
	rigKeygenLog="$rigTmp/keygen.$1"
	: > "$rigLog" ; : > "$rigKeygenLog"
	( cd / && env -i PATH="$rigRunPath" \
		MDCI_HOME="$rigHome" MDCI_ACCOUNT=mdci MDCI_FILES_PATH="$rigCase/files" \
		MDCI_TEAM_DATA_GIT_REMOTE=git@github.com:Meloscope-Limited/magic-team-board.git MDCI_NAMESPACE=mel \
		RIG_LOG="$rigLog" RIG_KEYGEN_LOG="$rigKeygenLog" RIG_UID=0 RIG_USERNAME=mdci \
		sh "$rigFragment" ) > "$rigTmp/out.$1" 2>&1
	rigRc=$?
}

echo "-- 1. all three absent: the installer creates all three --"
rigNewCase absent
rigRun absent
rigAssert "the run does not stop: exit 0"                                 "$rigRc" 0
rigAssert "the private half is created at deploy-keys/mdci"               "$( rigPresent "$rigLanding/mdci" )" present
rigAssert "the public half is created at deploy-keys/mdci.pub"            "$( rigPresent "$rigLanding/mdci.pub" )" present
rigAssert "the host keys are created at deploy-keys/known_hosts"          "$( rigPresent "$rigLanding/known_hosts" )" present
rigAssert "the key is made by ssh-keygen -t ed25519"                      "$( rigKeygenAfter -t )" ed25519
rigAssert "with an empty passphrase: -N followed by an empty argument"    "$( rigKeygenEmptyPassphrase )" 1
rigAssert "written where the fragment syncs from, at the account's own key name" \
	"$( rigKeygenAfter -f )" "$rigStaged/mdci"
rigAssert "its comment is magic-team-board-<ns> with a namespace after the dash" "$( rigCommentNames )" ok
rigAssert "the host keys are pinned: the three hosts known_hosts must reach" \
	"$( rigPinned "$rigLanding/known_hosts" )" "bitbucket.org github.com ssh.bitbucket.org"
rigAssert "the account's ssh config gives the key to the three hosts known_hosts pins" \
	"$( LC_ALL=C awk '/^Host / { $1 = "" ; sub( /^ /, "" ) ; print ; }' "$rigHome/.ssh/config" 2> /dev/null )" "github.com bitbucket.org ssh.bitbucket.org"
rigAssert "the public half is printed, so it can be listed as a deploy key" \
	"$( rigSaid absent 'GENERATED-KEY magic-team-board-' )" 1
rigAssert "and the output says it must be listed as a deploy key"          "$( rigSaid absent 'deploy key' )" 1

echo "-- 2. one present: it stays byte-identical, and the other two are created --"
rigNewCase one
rigStage mdci 'EXISTING PRIVATE HALF'
printf '%s\n' 'EXISTING PRIVATE HALF' > "$rigRef"
rigRun one
rigAssert "the run does not stop: exit 0"                                 "$rigRc" 0
rigAssert "the existing private half is never overwritten: byte-identical" "$( rigIdentical "$rigLanding/mdci" "$rigRef" )" identical
rigAssert "no second key is generated over it"                            "$( rigKeygenEmptyPassphrase )" 0
rigAssert "the public half is created beside it"                          "$( rigPresent "$rigLanding/mdci.pub" )" present
rigAssert "the host keys are created beside it"                           "$( rigPresent "$rigLanding/known_hosts" )" present
rigAssert "the host keys are pinned: the three hosts known_hosts must reach" \
	"$( rigPinned "$rigLanding/known_hosts" )" "bitbucket.org github.com ssh.bitbucket.org"

echo "-- 3. all three present: nothing is written, and the public half is still printed --"
rigNewCase all
rigStage mdci 'EXISTING PRIVATE HALF'
rigStage known_hosts 'github.com ssh-ed25519 EXISTING-PIN'
printf '%s\n' 'ssh-ed25519 EXISTING-PUBLIC magic-team-board-mel' > "$rigStaged/mdci.pub"
printf '%s\n' 'EXISTING PRIVATE HALF' > "$rigRef.private"
printf '%s\n' 'github.com ssh-ed25519 EXISTING-PIN' > "$rigRef.pinned"
printf '%s\n' 'ssh-ed25519 EXISTING-PUBLIC magic-team-board-mel' > "$rigRef.public"
rigRun all
rigAssert "the run does not stop: exit 0"                                 "$rigRc" 0
rigAssert "the private half is byte-identical"                            "$( rigIdentical "$rigLanding/mdci" "$rigRef.private" )" identical
rigAssert "the pinned host keys are byte-identical"                       "$( rigIdentical "$rigLanding/known_hosts" "$rigRef.pinned" )" identical
rigAssert "the public half is byte-identical"                             "$( rigIdentical "$rigLanding/mdci.pub" "$rigRef.public" )" identical
rigAssert "no key is generated at all"                                    "$( rigKeygenEmptyPassphrase )" 0
rigAssert "the existing public half is printed, so it can be listed as a deploy key" \
	"$( rigSaid all 'ssh-ed25519 EXISTING-PUBLIC magic-team-board-mel' )" 1

echo "-- 4. the readers themselves: each row that reads a file or a print can pass and can fail --"
rigNewCase control
mkdir -p "$rigLanding" || exit 1
printf '%s\n' 'A' > "$rigLanding/mdci" ; printf '%s\n' 'A' > "$rigRef.same" ; printf '%s\n' 'B' > "$rigRef.other"
printf '%s\n' 'github.com ssh-ed25519 X' 'github.com ssh-rsa Y' 'github.com ecdsa-sha2-nistp256 Z' > "$rigLanding/known_hosts"
rigAssert "control: the presence reader reports each of the three by its own name" \
	"$( rigPresent "$rigLanding/mdci" ) $( rigPresent "$rigLanding/mdci.pub" ) $( rigPresent "$rigLanding/known_hosts" )" "present absent present"
rigAssert "control: the identical reader says identical for equal bytes"   "$( rigIdentical "$rigLanding/mdci" "$rigRef.same" )" identical
rigAssert "control: and differs for different bytes"                      "$( rigIdentical "$rigLanding/mdci" "$rigRef.other" )" differs
rigAssert "control: the pin reader counts the three host-key lines of a sample" "$( rigPinnedCount "$rigLanding/known_hosts" )" 3
rigAssert "control: and names the hosts of those lines"                   "$( rigPinned "$rigLanding/known_hosts" )" github.com
printf '%s\n' 'GENERATED-KEY magic-team-board-' > "$rigTmp/out.control"
printf '%s\n' 'list it as a deploy key' >> "$rigTmp/out.control"
rigAssert "control: the print reader finds a line that a run did write"    "$( rigSaid control 'GENERATED-KEY magic-team-board-' )" 1
rigAssert "control: and reports none for a line it did not write"          "$( rigSaid control 'NOT-PRINTED' )" 0

if [ "$rigFailCount" -ne 0 ] ; then
	echo "⛔ DEPLOY KEY BOOTSTRAP CHECK FAILED: $rigFailCount of $(( rigPassCount + rigFailCount )) assertion(s)" >&2 ; exit 1
fi
printf 'MDCI_DEPLOY_KEY_BOOTSTRAP: OK (%d assertions, offline, stubs only, no host and no forge reached)\n' "$rigPassCount"
