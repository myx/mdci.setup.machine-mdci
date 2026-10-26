#!/usr/bin/env bash

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

if [ -z "$1" ] ; then
	echo "⛔ ERROR: slackServiceAlert: the process name is required as the first argument" >&2
	exit 1
fi

if ! service "$1" enabled ; then
	echo "🙋 WARNING: slackServiceAlert: service $1 is not enabled, no alert was sent" >&2
	exit 1
fi

. /usr/local/etc/.mdci-monit-env

if [ -n "${SLACK_ALERT}" ]; then
	export SERVICE=$1 && /bin/echo $SERVICE
	export HOST=$(hostname)
	export SLACK_CHANNEL=${SLACK_ALERT}

	MESSAGE=$(
		/usr/local/bin/envsubst <<- "EOF"
			{"text": "${SERVICE} service HAS BEEN STOPPED on ${HOST} ",  "channel": "${SLACK_CHANNEL}", "username": "${HOST}", "icon_emoji": ":meow_fire:"}
		EOF
	)

	echo "${MESSAGE}" | curl -sk 'https://slack.com/api/chat.postMessage' -H "Authorization: Bearer ${SLACK_TOKEN}" -H'content-type: application/json' --data-binary @- -o /dev/null
fi
