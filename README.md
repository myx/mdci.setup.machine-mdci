# setup.machine-mdci

The `mdci` team work-server machine for FreeBSD. It gives the host one main workspace, the installed `myx.distro-agents` (the magic-team), and `mdcid`, a daemon that runs the unattended main loop. The workspace holds the sources the host's own project names, and none by default.

The account home (`MDCI_HOME`, `/usr/local/mdci`) is the account home only: keys, credentials, user settings, machine registries. The main workspace is `$MDCI_HOME/workspace.mdci`, found at that path. The home itself is never a workspace.

Maintainer notes: `MAGIC.md`.

## Requires

- `standard/setup.machine-freebsd` — the FreeBSD floor.
- `standard/setup.feature-myx.common` — `setup.feature-myx.common`, which installs `myx.common`.
- `standard/setup.feature-monit` — monit, which watches `mdcid`.

## What it installs and configures

Eleven install steps, in this order (`host/install/common-mdci.<n>.<step>.txt`):

| # | step | does |
|---|---|---|
| 0 | `prepare` | packages (`git`, `python3`), `myx.common setup/server`, the shell setup of root, the `MDCI_ACCOUNT` account, the `workspace.mdci` folder, no `MMDAPP` export in `/etc/profile`, the shell setup and the console line of the account and each `USER_LIST` user, the authorised key, group passage through the home, the github https rewrite |
| 1 | `deploy-keys` | moves the deploy key to `$MDCI_HOME/deploy-keys` and sets the git ssh command |
| 2 | `install` | runs the workspace installer when the source console is missing |
| 3 | `sources` | registers source roots, syncs repositories, prepares and pulls |
| 4 | `agents` | runs the workspace installer again, adding the agents tooling to the existing workspace when it is missing |
| 5 | `team-config` | writes team and member settings |
| 6 | `workspace` | seeds claude settings, installs workspace integrations and restrictions |
| 7 | `spawn` | sets up the spawn credential for `MDCI_SPAWN_CLI_SERVICE` |
| 8 | `ownership` | ownership of the home, the group-shared mode of the workspace |
| 9 | `team-data` | team data storage, Slack |
| 10 | `daemon` | sets `mdcid_user`/`mdcid_group`; enables and starts `mdcid` where no enable state exists yet, else leaves the enable state as it is and restarts `mdcid` unless it was disabled |

Deployed files:

- `data/os-services-rc.d/mdcid` — the rc.d script of the daemon.
- `data/os-commands/mdci-*` — commands in `/usr/local/sbin` (see below).
- `data/monit/monitrc-mdci.conf` — the root-only monit control socket, which `mdci-daemon-enable` and `mdci-daemon-disable` need, and monit checks `mdcid` and `mdcid-progress`; `slackServiceAlert.sh` sends the alerts.
- `data/deploy-keys/` — the landing place for the deploy key. See `data/deploy-keys/README.md`.

A missing optional value is a `🙋 WARNING: mdci:<step>: …` and the deploy goes on. A deploy stops only where the services cannot be installed.

## Inputs

Defaults declared here (override with `define:`):

| variable | default |
|---|---|
| `MDCI_HOME` | `/usr/local/mdci` |
| `MDCI_ACCOUNT` | `mdci` |
| `MDCI_ACCOUNT_UID` | `181` |
| `MDCI_SPAWN_CLI_SERVICE` | `scaleway` (also `claude`, `copilot`) |
| `MDCI_EMAIL_IMAP_HOST` | `imap.gmail.com` |
| `MDCI_EMAIL_SMTP_HOST` | `smtp.gmail.com` |
| `MDCI_EMAIL_SMTP_PORT` | `587` |

Required, with no default:

- `MDCI_PKEY` — the ssh public key authorised for the account.

Optional:

- Sources: `MDCI_SOURCE_ROOTS` (space separated), `MDCI_SOURCE_REPOS` (`project,url` entries).
- Team data: `MDCI_TEAM_DATA_GIT_REMOTE`, `MDCI_TEAM_DATA_BRANCH`, `MDCI_TEAM_DATA_DIRECTORY`.
- Slack: `MDCI_SLACK_CHANNEL_MAGIC_TEAM` and `MDCI_SLACK_CHANNEL_HUMAN_OWNER` (both needed for the Slack setup), `MDCI_SLACK_CHANNEL_EVENT_TRACK`, `MDCI_SLACK_CHANNEL_EVENT_ALERT`, `MDCI_SLACK_APP_TOKEN`, `MDCI_SLACK_BOT_TOKEN`, `MDCI_SLACK_WORKSPACE_DOMAIN`.
- Spawn credentials: `MDCI_SCALEWAY_DEEPSEEK`, `MDCI_SCALEWAY_GEMMA` (scaleway); `MDCI_ANTHROPIC_API_KEY`, `MDCI_CLAUDE_CODE_OAUTH_TOKEN` (claude); `MDCI_COPILOT_GITHUB_TOKEN` (copilot). `MDCI_XAI_API_KEY` is stored for the team; no `MDCI_SPAWN_CLI_SERVICE` value selects it.
- Confluence: `MDCI_CONFLUENCE_SPACE`, the key of the team space.
- Members: `MDCI_TEAM_MEMBERS` (names: lower case letters, digits, dashes). Each member key is read from `MDCI_<MEMBER>_<KEY>` (dashes as underscores), else from the flat `MDCI_<KEY>`. Keys: `SLACK_USER_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_WORKSPACE_DOMAIN`, `EMAIL_IMAP_HOST`, `EMAIL_SMTP_HOST`, `EMAIL_SMTP_PORT`, `EMAIL_USER`, `EMAIL_APP_PASSWORD`, `TRELLO_KEY`, `TRELLO_TOKEN`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`, `CONFLUENCE_SITE`, `CONFLUENCE_USER`, `CONFLUENCE_API_TOKEN`. The two Slack bot keys have no flat form. The `human-owner` scope takes its one setting from `MDCI_HUMAN_OWNER_EMAIL_USER`.
- `USER_LIST` — the users of the host, filled by the account projects it requires. Each joins the account group and gets the console line.

Deployed file, not a variable: `data/deploy-keys/mdci` (private key), `mdci.pub`, `known_hosts`, supplied by the project that requires this one.

## Commands

On the host, in `/usr/local/sbin`:

| command | does |
|---|---|
| `mdci-daemon-enable` | enables and starts `mdcid`, then tells monit to watch it |
| `mdci-daemon-disable` | stops monit watching (and warns if monit cannot be told), disables and stops `mdcid` |
| `mdci-status` | `service mdcid status` |
| `mdci-daemon-progress` | fails when the main loop made no progress in 70 minutes (used by monit) |
| `mdci-main-loop-once` | runs one main-loop iteration |
| `mdci-update` | upgrades the installed tooling (deploy, source, remote and agents toolsets, pulled to the latest `master`) in the workspace `.local`; the account runs it itself, root is run as the account, nobody else may |
| `mdci-console` | a console session of the workspace: as the account for root, as themself for a `USER_LIST` user |
| `mdci-settings-apply <domain>` | applies settings from stdin (`KEY=VALUE` lines) on a running host |
| `mdci-public-keys` | prints the public deploy key of the rig with the repositories it is meant for and whether each can be read now, the ssh host keys of the rig for `known_hosts`, and the git servers the account trusts; root runs it as the account |

Use `mdci-daemon-disable` to stop the daemon. A plain `service mdcid stop` is undone by monit.

## Sessions

- The account and each `USER_LIST` user get a console session in each new screen window: the Source console of `workspace.mdci`, started by the last line of their `.bash_profile`. That line sits below the login line of `myx.common`, which starts screen first.
- Root gets the shell setup of `myx.common` and no console line. Root types `mdci-console` to get a console session as the account.
- A `USER_LIST` user may type `mdci-console` too, and gets the same console as that user. Anyone else is refused.
- The workspace has three consoles: `DistroLocalConsole.sh`, `DistroSourceConsole.sh` and `DistroAgentsConsole.sh`.
- The `USER_LIST` users reach the workspace as members of the account group: they pass through the home without listing it, and the workspace is group read-write.

## Checks

`sh-test/MdciFragmentsCheck.test.sh` and `sh-test/MdciDaemonToggleCheck.test.sh` run offline against stub commands. They are not shipped to hosts.
