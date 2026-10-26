#!/bin/sh
## The stand-in for myx.common that edits a profile for real. It logs its argv to $RIG_LOG. lib/replaceLine runs the
## real ReplaceLine of myx.common, sourced from $RIG_REPLACELINE, on a file under $RIG_TMP only; setup/client writes
## the two .bash_profile lines that setup/console and setup/completion write, the login line naming $RIG_LOGIN_INCLUDE.
## Every other call does nothing and succeeds.
echo "myx.common $*" >> "$RIG_LOG"
. "$RIG_REPLACELINE" || exit 99
rigProfile(){ ## file argument -- the path, a leading $HOME taken from the environment
	case "$1" in
		'$HOME/'*) printf '%s\n' "$HOME/${1#\$HOME/}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}
case "$1" in
	lib/replaceLine)
		rigTarget="$( rigProfile "$2" )"
		case "$rigTarget" in
			"$RIG_TMP"/*) touch "$rigTarget" && ReplaceLine "$rigTarget" "$3" "$4" ;;
		esac
	;;
	setup/client)
		case "$HOME" in "$RIG_TMP"/*) ;; *) exit 99 ;; esac
		touch "$HOME/.profile" "$HOME/.bash_profile"
		ReplaceLine "$HOME/.bash_profile" ' ### myx.common setup/console ###$' "source $RIG_LOGIN_INCLUDE  ### myx.common setup/console ###"
		ReplaceLine "$HOME/.bash_profile" ' ### myx.common completion ###$' "complete -W 'rig' myx.common  ### myx.common completion ###"
	;;
esac
exit 0
