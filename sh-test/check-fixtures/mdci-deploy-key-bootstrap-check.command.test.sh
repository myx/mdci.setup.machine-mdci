#!/bin/sh
## The stub for every host command common-mdci.1.deploy-keys.txt calls, and for the two a fragment must call once it
## creates the missing deploy-key material. It is installed under each command's own name on the rig's PATH.
##
## It logs every call to $RIG_LOG as `<name> <argv joined by spaces>`, for the rows about which command ran.
## It logs the ssh-keygen calls to $RIG_KEYGEN_LOG one line per argument, as `arg:<the argument>`, because an argument
## that is empty or holds a space cannot be read back from the joined form: the passphrase argument of the key is empty.
##
## It makes what the fragments need and nothing more: a real mkdir, a real chmod, a key pair at the `-f` path whose
## comment is the `-C` argument, and three host keys per host asked of ssh-keyscan.
rigName="${0##*/}"
printf '%s\n' "$rigName $*" >> "$RIG_LOG"
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
	chmod) exec /bin/chmod "$@" ;;
	chown) : ;;
	git) : ;;
	hostname) printf 'rig\n' ;;
	id) case "$*" in -u) printf '%s\n' "${RIG_UID:-0}" ;; -un) printf '%s\n' "${RIG_USERNAME:-mdci}" ;; esac ;;
	rsync)
		## The last two operands are the source and the destination, each with a trailing slash.
		rigDst= rigSrc=
		for rigLast ; do rigDst="$rigSrc" ; rigSrc="$rigLast" ; done
		rigDst="${rigDst%/}" ; rigSrc="${rigSrc%/}"
		[ -n "$rigDst" ] && [ -n "$rigSrc" ] || exit 1
		/bin/mkdir -p "$rigSrc" 2> /dev/null
		cp -R "$rigDst/." "$rigSrc/" 2> /dev/null
	;;
	ssh-keygen)
		{ printf 'ssh-keygen\n' ; for rigArg ; do printf 'arg:%s\n' "$rigArg" ; done ; } >> "$RIG_KEYGEN_LOG"
		rigOut= rigDerive= rigComment=
		while [ $# -gt 0 ] ; do
			case "$1" in
				-f) rigOut="$2" ; shift ;;
				-C) rigComment="$2" ; shift ;;
				-y) rigDerive=1 ;;
			esac
			shift
		done
		[ -n "$rigOut" ] || exit 1
		if [ -n "$rigDerive" ] ; then
			printf 'ssh-ed25519 DERIVED-KEY rig\n'
			exit 0
		fi
		printf 'PRIVATE-KEY-MARKER %s\n' "${rigComment:-none}" > "$rigOut"
		if [ -n "$rigComment" ] ; then
			printf 'ssh-ed25519 GENERATED-KEY %s\n' "$rigComment" > "$rigOut.pub"
		else
			printf 'ssh-ed25519 GENERATED-KEY\n' > "$rigOut.pub"
		fi
	;;
	ssh-keyscan)
		for rigHost ; do
			case "$rigHost" in -*) continue ;; esac
			printf '%s ssh-rsa RIGRSA%s\n' "$rigHost" 'AAAA'
			printf '%s ecdsa-sha2-nistp256 RIGECDSA%s\n' "$rigHost" 'AAAA'
			printf '%s ssh-ed25519 RIGED25519%s\n' "$rigHost" 'AAAA'
		done
	;;
esac
exit 0
