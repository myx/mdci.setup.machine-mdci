#!/bin/sh
## The stand-in for DistroAgentsTools.fn.sh. It logs its argv and what arrived on stdin to $RIG_LOG, and fails with an
## error line of its own when its argv holds RIG_FAIL_MATCH, or always when RIG_TOOLS_FAIL=1.
rigValue=
[ -t 0 ] || rigValue="$( cat )"
echo "tools $* value=$rigValue" >> "$RIG_LOG"
[ "${RIG_TOOLS_FAIL:-}" != 1 ] || { echo "⛔ ERROR: rig tools op failed: $1" >&2 ; exit 7 ; }
case "$*" in
	*"${RIG_FAIL_MATCH:-NEVER-MATCHES-ANYTHING}"*) echo "⛔ ERROR: rig tools op failed: $1" >&2 ; exit 7 ;;
esac
exit 0
