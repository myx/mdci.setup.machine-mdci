# MAGIC.md — setup.machine-mdci

Team-owned rules for `mdci`, the universal team rig installer: it gives a FreeBSD host a configured main workspace, the installed `myx.distro-agents`, and a daemon running the unattended main loop. It sits on the `setup.machine-freebsd` floor. Nothing in this package names a host or a client. Users read `README.md`; how the packages compose is in `../MAGIC.md`.

## What the machine is

- A host gets one configurable main workspace, the installed `myx.distro-agents`, and `mdcid`, a daemon running `--intern-main-loop --run`.
- The account home `MDCI_HOME` is the account home only: its keys, credentials, user settings, machine registries and the service files of `mdcid`. The main workspace is `workspace.mdci` inside it, found at that path and never by a setting; the home itself is never a workspace. Further workspaces, when a rig has any, live beside it in `Workspaces/<name>`.
- The machine carries no build farm: no actions, no settings catalogue, no sh-lib of its own on the host.
- The machine names no source of its own. A dependent project names its roots in `MDCI_SOURCE_ROOTS` and its repositories in `MDCI_SOURCE_REPOS`, and `3.sources` syncs them; with neither the workspace stays empty. The team reaches the rig through the `skillset/` directory inside the installed `myx.distro-agents`.
- The installer installs `myx.common`, so the fragments call it without a check.

## The machine holds the machine; the dependent project holds the identity

- Everything a second rig also needs is here. Everything true of one machine — its team-data remote, Slack channel ids, deploy key, spawn credential, source repositories — belongs to the project that requires this one.
- Defaults here use `create`, so a dependent project's own `define` wins in either merge order.
- The machine declares nothing for a per-host secret: no `define:`, no `create:`, no placeholder. A credential inlined in a shared machine is one credential for every host, and rotating it edits shared code.
- No default here is one customer's identity: no email address, Slack domain or channel id.

## Fragments

`project.inf` lists eleven `exec-update-before` fragments in `host/install/`, numbered in the order they run. The number in a file name is the position in `project.inf`. Each fragment holds either server-floor work (the account, the home, the workspace, its consoles, ownership) or team work (the agents tooling, team and member settings, team data, Slack, the daemon), never both.

| # | step | does | stops the deploy |
|---|---|---|---|
| 0 | `prepare` | packages, `setup/server`, the shell setup of root, the account, the `workspace.mdci` folder, `MMDAPP` retired from `/etc/profile`, the shell setup and the console line of the account and each `USER_LIST` user, the authorised key, ownership, group passage through the home, the github https rewrite | every step |
| 1 | `deploy-keys` | second hop of the deploy key, the git ssh command, and the managed block of the account's ssh config that gives a plain ssh the same key for `github.com` and `bitbucket.org` | never |
| 2 | `install` | the workspace installer on every deploy, reinstalling the console idempotently: installed where missing, brought up to date where present | download or installer failure, missing source artifacts |
| 3 | `sources` | source roots, repository sync, prepare and pull | never |
| 4 | `agents` | the workspace installer again on every deploy, reinstalling the agents tooling idempotently: installed where missing, brought up to date where present | download failure, an installer failure with no agents tooling after it, missing agents artifact (an installer that ends late with the tooling in place is a warning) |
| 5 | `team-config` | team and member settings into the config scopes | never |
| 6 | `workspace` | claude settings seed, workspace integrations and restrictions | never |
| 7 | `spawn` | the presets of `MDCI_SPAWN_PRESETS` (base presets first, then the extending ones), each base preset's `MDCI_PRESET_<NAME>_<KEY>` credentials moved into it and out of `magic-team`, the three `MDCI_SPAWN_TIER_*`, and the workspace integrations; no `SPAWN_CLI_SERVICE` | never |
| 8 | `ownership` | ownership of the home, the group-shared mode of the workspace | `chown`, `chmod` |
| 9 | `team-data` | team data storage, Slack | never |
| 10 | `daemon` | `sysrc` for `mdcid_user`/`mdcid_group` always, and for `mdcid_enable` only where no state is stored yet; `service mdcid restart` and its status, skipped where the stored state is disabled | toolchain missing, `sysrc`, `service restart` |

- **The installer sets up the services; everything after is configuration that can change later.** A missing checkout, key, integration, permission, credential or setting is a warning that names the problem, and the deploy goes on. A fragment ending early on a warning exits 0: it stops itself, never the deploy.
- **A fragment stops the deploy only where the services cannot be installed.** The base variables are guarded in every fragment; the stops are the ones in the table.
- Tolerated non-final failures: `chflags -R nouchg ... || :` in `0.prepare` (the flag clear is optional and the `chown -R` after it fails loudly) and `ls ... || :` in `2.install` and `4.agents` (a listing in a path that exits 1 anyway).
- A host-name and root guard that keeps one host's keys from reaching another is not in this package; it belongs to the dependent project.

### Message grammar

- Every message to stderr is emoji first: `⛔ ERROR: mdci:<step>: <what>` or `🙋 WARNING: mdci:<step>: <what>`, with the step name from the table. Progress lines are `mdci:<step>: <what>`.
- A guard states the missing variable and stops: `[ -n "${NAME:-}" ] || { echo "⛔ ERROR: mdci:<step>: NAME is not set" >&2 ; exit 1 ; }`. Every variable a fragment cannot run without is guarded this way, at the top, before any work.
- A warning that follows a failed command carries its exit status: `(exit $?)`.

### Variables, not literals

- Fragments use variables only: `MDCI_HOME`, `MDCI_ACCOUNT` and the rest. No fragment holds a literal install path.
- Deployed files — the rc.d script, the os-commands, `monitrc-mdci.conf` — carry the default path `/usr/local/mdci` literally and know nothing of variables.

### Comments and prose

- A comment states a rule or a fact that holds at any time. It carries no date, no account of a change, no member name and no tenant name.
- A comment holds no apostrophe: a generated installer passes through `bash 3.2` on the operator machine, which mis-parses an odd count inside the wrapped heredoc.

## Secrets are chosen by shape

- **File-shaped**, a key, travels as deployed material: `data/deploy-keys/` collected by the `**` sync from whichever project supplies it, placed by `1.deploy-keys`.
- **String-shaped**, a bearer token, travels as a context variable of the dependent project: an `:import:` of a file that project holds, or a plain `define:`.
- A context variable is emitted into the generated installer as `export NAME=%q`, so a value is data, never code, and any value may be routed through one. It still reaches the installer on disk, the deploy log, and the environment of every fragment and child.
- Every credential a fragment writes goes in on stdin, never as a flag: `ps` is world readable, so argv leaks to every local account for the life of a call.
- `mdci-settings-apply` inspects or overrides a stored setting on a running rig. No install step calls it and nothing depends on it.
- `mdci-public-keys` prints only public data, read as the account (root is run as the account, anyone else is refused, since the deploy keys directory is the account's alone). It names the key that the git ssh command of the account uses, else the generated default; the repositories that key is for, taken from `$MDCI_HOME/.mdci-source-repos.txt` (the list `3.sources` keeps on every deploy, one `project<TAB>url` per line, so a repository that failed to clone is still named) and from `TEAM_DATA_GIT_REMOTE` in the team settings, each with the host and path to list the key on and the answer of `git ls-remote` for it; the tool repositories that `mdci-update` pulls with the same key, taken from the origin of each clone under `.local/myx` of the workspace, so no list is repeated here; the ssh host keys of the rig as `known_hosts` lines; and the fingerprints of the git servers in the two `known_hosts` files of the account. Secrets in the team settings are never read out. No install step calls it.
- The deploy configures the rig completely. There is no second command and no manual step on the host.

## Deployed secrets arrive in two hops

- The sync lands material in `/usr/local/mdci-files/<name>` with `mkdir -p -m 770` and `--chmod=ug+rwX`. That only adds bits, so a private key can arrive readable by the staging group; the `770` holds only on a directory the run created.
- `1.deploy-keys` is the second hop: it re-syncs to `$MDCI_HOME/deploy-keys` with `--chmod=u=rX,go=` and `--chown`, then asserts both with `chown -R` and `chmod -R`. The staging directory is never a destination.
- The sync excludes dot-named paths, so a key lives under a non-dot path. `README.md` is excluded by every sync contract, which is how `data/<contract>/` carries a placeholder without shipping it.
- The git ssh command is set only when the private key `deploy-keys/$MDCI_ACCOUNT` exists. `known_hosts` is pinned, `StrictHostKeyChecking` is on and `GlobalKnownHostsFile` is `/dev/null`: a forge absent from `known_hosts` cannot be reached.
- `3.sources` clones with that key, else with a key it generates at the ssh default path under `$MDCI_HOME/.ssh`. When a sync or pull fails it prints the public key the clones use. Before the sync each declared repository is probed with `git ls-remote` as the account. One the key cannot read yet is named in a single warning with the public key and is left out of the sync, so the tools print no error of their own for a deploy key that is still to be listed on the repository. Source prepare and pull runs only when a repository is in the workspace, because the tool refuses an empty one; with none, the step ends with a warning (or with the unreadable-repository warning that already says why). The key is a step of the human-owner, and the deploy goes on.

## Data directories are collected by the floor

- The floor declares `image-prepare:sync-source-files:**:data/<dir>:<dir>` for `os-commands`, `os-services-rc.d`, `sudoers.d`, `cron.d` and the rest. `**` matches every project in the host's index sequence, so a file placed in `data/<dir>/` is installed without a declaration here.
- `*` in the same position matches only projects that depend on the declaring project. Reading one as the other makes a file look undeclared when it is collected, or collected when it is not.
- `data/deploy-keys` is the one sync this project declares, because the floor has no such contract. It uses `**` so a dependent project supplying its own `data/deploy-keys/` merges into the same landing directory.

## Settings: two writers

- A key some `--owner-setup-<domain>` declares is written by that domain, one call per domain, values on stdin: `9.team-data` carries Slack and storage, `7.spawn` the spawn service `MDCI_SPAWN_CLI_SERVICE` selects.
- Every other key is written by `5.team-config` through `--agents-config-option <scope> --upsert-from-stdin <KEY>`: the team keys into `magic-team`, each per-member key into that member's scope. An undeclared value writes nothing, because the upsert refuses empty input.
- A member value is `MDCI_<MEMBER>_<KEY>` (dashes as underscores), else the flat `MDCI_<KEY>`; the Slack bot token and workspace domain have no flat form. A member name holds lower case letters, digits and dashes only, because it reaches `eval`.
- `AgentsToolsOwnerSetupOptionSpec` in the agents package is the single definition of every key a domain may declare; the engine refuses a name no domain declared.
- Scopes are not interchangeable. The Slack tokens and channel ids and `TEAM_DATA_GIT_REMOTE` are the team's own and live in `magic-team`; `SLACK_USER_TOKEN`, the `EMAIL_*`, `TRELLO_*` and `GOOGLE_*` keys and `TEAM_DATA_DIRECTORY` are a member's own. A value in the wrong scope is stored and never read.
- `SLACK_WORKSPACE` and `TEAM_ID` are not declared here: they are resolved from a token and persisted by the tooling.
- Every `--owner-setup-*` value is written to `$MMDAPP/.local/.agents/<scope>.agent.env`. Settings do not live in the team-data checkout.
- The sub-operation `--apply` stays last on an `--owner-setup-*` call; a flag after it is an error.
- `--agents-config-option <member> --select <key>` does not fall back to `magic-team`, and a wrong scope and an unset key both return the empty string.

### Team data

- `TEAM_DATA_DIRECTORY` unset is the normal case: the tooling uses `$MMDAPP/.local/agents/team-data-root`. A project that defines `MDCI_TEAM_DATA_DIRECTORY` overrides it; this project declares no default for it.
- `9.team-data` resolves the directory (the variable, relative values against the workspace root, else the tooling default), creates it as the account, and calls `--owner-setup-storage` with `--team-data-directory` only when the variable is set and `--team-data-git-remote` only when `MDCI_TEAM_DATA_GIT_REMOTE` is set. The storage domain accepts a call with neither.
- The installer never clones team data. The tool obtains the checkout, and the main loop maintains and pulls it.

## `OS_PACKAGES`

- Declaring `image-install:context-variable:OS_PACKAGES:insert:<pkg>` puts the name in the installer environment and nothing else. `0.prepare` calls `myx.common lib/installEnsurePackage $OS_PACKAGES` whenever it is non-empty; the call is idempotent.
- `OS_PACKAGES` is emitted with ANSI-C quoting (`$'...'`), which FreeBSD `/bin/sh` supports.
- An entry is a utility name: `installEnsurePackage` skips it when `command -v` finds it, else maps it through `package-name-map.<uname>.txt`, falling back to the name itself.
- `python3` is declared here and only here. `unzip` is not declared: `workspace-install.sh` falls back to `bsdtar`.

## The workspace bootstrap is captured, never piped

- `2.install` and `4.agents` each fetch the workspace installer into a variable, then run `bash -c "$var" -- --force --git-clone --config-stdin` as the account, one with `source exec true` on its stdin and the other with `agents exec true`. A pipeline `fetch | sh` reports the status of its last element, so a failed download would install nothing and report success; the assignment is what `set -e` sees, and an empty capture stops the fragment.
- It is bash, not `sh`: the installer begins `set -euo pipefail`, which FreeBSD `sh` rejects, and capturing the body discards its shebang.
- `--` is not removable: it becomes `$0`, which puts `--force` at `$1`. `env` carries `TGT_APP_PATH` through `sudo`.
- A process substitution `<( )` is not used: stock FreeBSD devfs offers only `/dev/fd/0,1,2` and `fdescfs` is not mounted.

## The github rewrite is narrow

- Every `myx.distro` subsystem clones over `git@github.com:`. `0.prepare` rewrites `git@github.com:myx/` and `git@github.com:myx-distro-libs/` to https in the account's global git config, run from `/` so a global write never walks into a checkout.
- It is not a blanket `git@github.com:` rewrite: the team-data remote is private and reached with the deploy key, and a blanket rewrite would turn a missing key into an anonymous https refusal.

## The home and the workspace

- The home keeps `.ssh`, `deploy-keys`, `.gitconfig`, `.claude.json`, the user `.claude` (`settings.json` of the permissions op, skills links, projects, credentials), `.copilot`, `.agents` (machine registries and user skills links), `.vscode/extensions`, the shell files, `.daemon.pid` and `.daemon.progress`, and the vendor `.local/bin`, `.local/share` and `.local/state`.
- `workspace.mdci` holds the consoles, `source`, the project `.claude` (`settings.json` with the hooks, `hooks`, `rules`, the copilot fragment), `.mcp.json`, `.vscode` without `extensions`, the code-workspace file, and its own `.local`: the tooling, the agents data, the settings stores, scratch and caches.
- `6.workspace` seeds the user settings file in the home, which the permissions op fills; the restrictions op writes the project settings in the workspace, so the home holds no hooks of a workspace.
- The workspace has three consoles: `DistroLocalConsole.sh`, which every workspace has, and `DistroSourceConsole.sh` and `DistroAgentsConsole.sh` of the two subsystems `2.install` asks for.
- The workspace is shared by the account group. `installUser` leaves the home at mode `700`; `0.prepare` adds `g+x`, so a member passes through the home to `workspace.mdci` and cannot list the home, and `8.ownership` sets `ug=rwX` on the whole workspace. A session of the account or of a member runs with umask `002`, which the shell setup of `myx.common` sets.

## A console session in each screen window

- `0.prepare` calls `myx.common setup/server`, which installs `screen`, and `myx.common setup/client` for root, for the account and for each `USER_LIST` user. `setup/client` writes the profile lines of `myx.common` and a `.screenrc` in which every screen window runs a login shell.
- The account and each `USER_LIST` user also get the console line, in `.bash_profile` only: `USER_LIST` is the array the account projects of the host fill, one `ensure` per user. Root gets the shell setup and no console line.
- `mdci-console` gives a console session on demand to root and to the members of the account group, who are the `USER_LIST` users. It refuses everyone else.
- For root it runs `sudo -u <account> -H -i bash -l`, so root gets the session of the account. `lib/installUser` gives the account the shell `/bin/sh`, whose `.profile` has no console line, so the command names a login bash, which reads `.bash_profile`. `sudo -i` keeps `TERM` and drops `SSH_CONNECTION`, and the login line starts screen only over ssh and outside screen, so no second screen starts.
- For a member it starts `DistroSourceConsole.sh` of `workspace.mdci` as that member, with `MMDAPP` set: the console the profile line of the member starts. No sudo rule lets the account group act as the account, and this machine ships no `data/sudoers.d`.
- The login line of `setup/console` in `.bash_profile` starts screen when the login comes over ssh outside screen. A screen window is a login shell again: it reads the same profile, skips the screen start, and goes on to the lines below it.
- The console line starts `DistroSourceConsole.sh` of `workspace.mdci`, and it is the last line of the profile, below that login line. So a login starts screen first, and the console starts in each screen window. A console line above the login line would start the console before screen, or instead of it.
- `0.prepare` holds that order on every deploy. `lib/replaceLine` removes the line it matches and appends the new one, so every writer moves its own line to the end, and `0.prepare` writes the console line after `setup/client` in the same pass.
- The line sets `MMDAPP` to `workspace.mdci` before it sources the console. A console sourced by a login shell takes its folder from `$0`, which is the name of the shell, and ends up in the home; no login exports `MMDAPP`. The `/etc/profile` export is replaced with a `# removed by mdci-setup` marker, so every other tool takes its workspace from its own location.
- The line holds no dollar sign. `sudo -s` escapes every other special character and leaves `$` for its own shell, which would expand it during the deploy.
- A `.profile` console line is replaced with the `# removed by mdci-setup` marker, not deleted, so a host that has it loses it on the next deploy.
- Membership of the account group is for the `USER_LIST` users only.

## The daemon

- `mdcid` runs the loop under `daemon(8)` through `rc.subr`. `mdcid_user` and `mdcid_group` come from `rc.conf`; `10.daemon` sets them with `sysrc`. `rc.subr` starts the whole command as that account; there is no `daemon -u`.
- The workspace, its chdir, the command and `MMDAPP` are set after `load_rc_config` from the path `/usr/local/mdci/workspace.mdci`, so no `rc.conf` value moves them. `mdci-main-loop-once`, `mdci-settings-apply` and `mdci-update` find the workspace the same way.
- `command_args` is `-P <pidfile> -r -f -S -T mdci`, then `DistroAgentsTools.fn.sh --intern-main-loop --run`. `-S -T mdci` sends the loop output to syslog under the tag `mdci`.
- `daemon -r` is crash-only by intent: the loop owns its backoff in-process, 29 seconds doubling to a 1200-second ceiling, and never exits between iterations, so a longer restart delay here would race it. The two delay keys are not in the option catalogue; they change with `--agents-config-option magic-coordinator --upsert`.
- The pidfile and the progress flag live in the service home. `start_precmd` touches both on every start, chowns them to `mdcid_user` and sets 644; a start resets the flag age. The `;`-separated chain reports only its last command's status.
- The script exports `HOME`, `PATH`, `MMDAPP` and `MDAT_MAIN_LOOP_PROGRESS_FILE` itself.
- `mdci-daemon-enable` runs `sysrc mdcid_enable=YES`, `service mdcid start`, then `monit monitor` for `mdcid` and `mdcid-progress`; a failed start ends it before monit is told to watch anything. `mdci-daemon-disable` unmonitors both, then `sysrc mdcid_enable=NO`, then `service mdcid onestop`; a failed unmonitor does not block the stop.
- Monit's `check process mdcid` restarts the daemon whenever it is down, so a plain `service mdcid stop` is undone at the next cycle. Stop with `mdci-daemon-disable`, start with `mdci-daemon-enable`.
- `monit unmonitor` and `monit monitor` reach the running monit through its HTTP interface, and `/usr/local/etc/monitrc`, written by `myx.common install/monit`, has no `set httpd` line. So `monitrc-mdci.conf` opens one: `set httpd unixsocket /var/run/monit.sock`, root-owned, mode 700, no TCP port, and one `allow mdci:mdcimonitcli`. The `allow` line is not optional: monit 6.0.0, the FreeBSD port version, logs "Monit httpd not started since no connections are allowed" and creates no socket without one, and its CLI needs one cleartext `user:password` to connect. The credential is not a secret and guards nothing: the root-only socket is the access control. `monit -t` passes without the `allow`, so it proves syntax only, never that the socket is up. Without the socket every monit call from the two commands fails, `mdci-daemon-disable` still stops the daemon, and monit restarts it at every cycle. The socket is read from the included file by the CLI as well; that is from the monit manual, not measured on a rig.
- `mdci-daemon-disable` says a failed `monit unmonitor` on stderr, one `WARNING` line per check, and still runs the stop. It does not change its exit status.
- While `mdcid` is disabled `slackServiceAlert.sh` exits 1 and sends nothing, so a monit that keeps restarting a disabled daemon raises no alert. The silence is that script's own rule, not a fault in monit.
- Monit keeps the unmonitored state across its own restart through its state file; not measured on a rig. A deploy that adds the socket restarts monit with the check still monitored on a host where the earlier unmonitor failed, so one `mdci-daemon-disable` run after that deploy is what makes the state stick.
- `mdci-main-loop-once` is a work command, not a check: one iteration, its status returned, delegable through `sudoers.d` and invocable by monit. `mdci-update` upgrades the installed tooling as the rig account: `DistroLocalTools.fn.sh --upgrade-installed-tools`, a clone-or-pull of the toolsets to their latest `master`, not a reinstall of the host, written only under the workspace `.local`. It needs no sudo rule: the account runs the tool directly (a `sudo -u` to itself would need a rule that nothing installs), root is run as the account, and anyone else is refused. It starts the tool without `MMDAPP` and `MDLT_ORIGIN`, so a console's variables cannot move it from the rig workspace.

### `HOME` and `PATH`

- `service(8)` sets `HOME=/` and a `PATH` without `/usr/local/bin`, at boot and from an interactive root shell alike. The rig needs both.
- A CLI domain's `--owner-setup-*` writes the workspace integrations under `$HOME`. Every install-side call that writes into the rig home runs `sudo -u "$MDCI_ACCOUNT" -H`, and `mdcid` exports the home itself.
- A hand-run `--intern-main-loop --one` over ssh inherits the caller's `HOME` and can succeed while the daemon cannot start. Monit starts the daemon through `service(8)`, in the environment the daemon gets.

## How the rig is verified

- `service mdcid status` reports the supervisor and passes while the loop crash-loops. `10.daemon` runs it after a restart, as a warning only; a stored disabled state skips the restart and this check alike.
- The monit progress check is the check that reads work done. `--intern-main-loop --run` touches `$MDAT_MAIN_LOOP_PROGRESS_FILE` after each iteration whose spawn succeeded; `--one` never touches it. `check program mdcid-progress` runs `mdci-daemon-progress`, which exits 0 when `mdcid` is not enabled and fails when the flag is missing or older than 70 minutes. On failure monit runs `slackServiceAlert.sh mdcid`, repeating every 240 cycles; it restarts nothing.
- 70 minutes is the loop backoff: each failed pass doubles the delay from 29 s toward 1200 s, and a flag older than the whole backoff means the loop failed through all of it, or a pass hung.
- Whatever touches a liveness flag is the thing that did the work, not a wrapper around it; the action on a stale flag never restarts the loop, since `if ... then exec` fires every cycle the condition holds and would pin the backoff at its floor.
- The flag lives beside the pidfile in the service home: not `/tmp`, which FreeBSD clears at boot, and not `.local/temp`, which is scratch.
- A permanent misconfiguration does not show as a crash: the rig starts, reports ready, fails every iteration and goes quiet at the ceiling. Process liveness reads that as healthy; the progress check reads it as stale.

## `set -e` and AND-OR lists

- The rule, and the wrong short form of it, are in `setup.machine-freebsd/MAGIC.md`.

## The generator

- Each fragment is wrapped `( set -e ; eval "$( cat << 'BLK' ... )" )`, the status is captured on the next line and tested, so a failing fragment stops the deploy. The capture line stays directly against the subshell: an echo between them changes what `$?` reports.
- **Check a generated installer with `dash -n` on the installer for the wrapping, and `dash -n` on each fragment file for its contents.** Neither substitutes for the other: the heredoc body is literal to the installer parse, and `bash -n` reports false failures on an odd apostrophe count.
- Check the form by capturing the status and testing it, not by `sh -n file || echo bad`.
- **`--project` takes the full project path.** A bare name half-resolves into a complete-looking installer with no context variables and the generator still returns 0.
- **Judge a generation by stderr, not by exit status.** `--print-script` returns 0 when a declared fragment file is missing and emits an installer with it absent.
- **The `Deploy` console generates from the cache, not from the files just edited.** `Deploy InstallPrepareScript` resolves fragments from `.local/source-cache/sources/`; the fragment header lines in the generated file name that path, which is the only visible tell. The same cache feeds the file sync, so a new `data/` file is not collected until the cache is refreshed. `Source BuildCachedFromSource` refreshes it; `Source CleanSourceToCached` alone only empties it.
- Generate from live source when checking:

  ```
  export MDSC_NO_INDEX=--no-index
  export MDSC_SOURCE="$MMDAPP/source"
  DistroSystemContext --distro-from-source
  Require ListProjectSequence ; Require InstallPrepareScript
  Distro InstallPrepareScript --project <full/project/path> --print-script
  ```

- A success status can describe a different operation than the one the caller invoked: a pipeline's last element, a wrapper that returns its logger's status, an untested subshell, a cache read reported as a source read. Ask what the mechanism did: which byte it returned, which file it read, which stage the status came from.

## Checks

- The package check lives in `sh-test/` of this project and is not shipped to hosts. It runs the fragments offline against stub commands, under `/bin/sh` and `dash`; FreeBSD `ash`, a real `sudo`, `rc.subr` and monit are out of its reach.
- The check holds no tenant string. The full-installer row takes its project path from `RIG_MDCI_INSTANCE_PROJECT`, and is skipped when it is unset.
