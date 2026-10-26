#!/bin/sh
## The stub for every host command the install fragments call. It is installed under the command's own name, logs its
## argv to $RIG_LOG, and answers by name: it fails when RIG_FAIL lists the name, or when RIG_ALLFAIL=1 and RIG_OK does not
## list the name; otherwise it does what the command would, only as much as the fragments need.
rigName="${0##*/}"
echo "$rigName $*" >> "$RIG_LOG"
rigFail=
case " ${RIG_FAIL:-} " in *" $rigName "*) rigFail=1 ;; esac
if [ "${RIG_ALLFAIL:-}" = 1 ] ; then
	case " ${RIG_OK:-} " in *" $rigName "*) ;; *) rigFail=1 ;; esac
fi
[ -z "$rigFail" ] || exit 1
case "$rigName" in
	sudo)
		while [ $# -gt 0 ] ; do
			case "$1" in
				-u) shift 2 ;;
				-H|-s|-i) shift ;;
				*) break ;;
			esac
		done
		exec "$@"
	;;
	mkdir) exec /bin/mkdir "$@" ;;
	git) case "$*" in *"remote get-url origin"*) [ -z "${RIG_GIT_ORIGIN:-}" ] || echo "$RIG_GIT_ORIGIN" ;; esac ;;
	id) case "$*" in -u) echo "${RIG_UID:-0}" ;; -Gn) echo "${RIG_GROUPS:-}" ;; -un) echo "${RIG_USERNAME:-}" ;; esac ;;
	sysrc) case "$*" in "-n mdcid_user") [ -z "${RIG_RC_USER:-}" ] || echo "$RIG_RC_USER" ;; "-n mdcid_enable") [ -n "${RIG_RC_ENABLE:-}" ] || exit 1 ; echo "$RIG_RC_ENABLE" ;; esac ;;
	service) case "$*" in *status) [ -z "${RIG_STATUS_FAIL:-}" ] || exit 1 ;; esac ;;
	bash) exec /bin/bash "$@" ;;
	fetch) printf '%s' "${RIG_FETCH_OUT:-}" ;;
	rsync)
		## The last two operands are the source and the destination, each with a trailing slash.
		for rigLast ; do rigDst="${rigSrc:-}" ; rigSrc="$rigLast" ; done
		rigDst="${rigDst%/}" ; rigSrc="${rigSrc%/}"
		/bin/mkdir -p "$rigSrc" 2> /dev/null
		cp -R "$rigDst/." "$rigSrc/" 2> /dev/null
	;;
	ssh-keygen)
		rigOut= rigDerive=
		while [ $# -gt 0 ] ; do
			case "$1" in
				-f) rigOut="$2" ; shift ;;
				-y) rigDerive=1 ;;
			esac
			shift
		done
		if [ -n "$rigDerive" ] ; then
			echo "ssh-ed25519 DERIVED-KEY rig"
		elif [ -n "$rigOut" ] ; then
			: > "$rigOut"
			echo "ssh-ed25519 GENERATED-KEY rig" > "$rigOut.pub"
		fi
	;;
esac
exit 0
