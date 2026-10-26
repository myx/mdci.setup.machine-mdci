#!/bin/sh
## The stand-in for DistroSourceConsole.sh. It logs its argv and the commands it is given on stdin to $RIG_LOG and answers
## per the command: the repo sync by RIG_SYNC_RC, the source prepare and pull by RIG_PREPARE_RC, the root registration
## by RIG_ROOTS_RC; RIG_CONSOLE_FAIL=1 makes every call fail.
echo "console $*" >> "$RIG_LOG"
rigIn="$( cat )"
printf '%s\n' "$rigIn" >> "$RIG_LOG"
[ "${RIG_CONSOLE_FAIL:-}" != 1 ] || exit 1
case "$rigIn" in
	*--execute-from-stdin-repo-list*) exit "${RIG_SYNC_RC:-0}" ;;
	*--execute-source-prepare-pull*) exit "${RIG_PREPARE_RC:-0}" ;;
	*--register-repository-roots*) exit "${RIG_ROOTS_RC:-0}" ;;
esac
exit 0
