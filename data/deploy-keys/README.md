# deploy-keys

The landing directory for a rig's own outbound git identity. Every file here is
synced to the host and then re-synced by `common-mdci.1.deploy-keys.txt` to
`$MDCI_HOME/deploy-keys` at mode `u=rX,go=`. This `README.md` is excluded from
both hops.

**This file is load-bearing: it is not removed when a real key arrives.** The
wildcard lookup warns and fails when no project in the sequence has the declared
path, so the placeholder is what makes `data/deploy-keys` resolve on a rig whose
instance project supplies no key. Every generic project that declares such a
contract ships the same placeholder, and every consuming fragment carries
`--exclude=README.md` to keep it off the host.

This project declares the sync with `**` as its source name, so an instance
project supplying its own `data/deploy-keys/` merges into the same landing
directory. The role declares the mechanism; the instance supplies the key.

Expected contents, none of them created here:

- `mdci` -- the private half, an unencrypted OpenSSH key. The file is named
  after the account `MDCI_ACCOUNT`.
- `mdci.pub` -- the public half. It is listed as a deploy key on the team-data
  repository by whoever owns that remote; the deploy does not do it.
- `known_hosts` -- pinned host keys for the git forge. `StrictHostKeyChecking`
  is on at use time and `GlobalKnownHostsFile` is `/dev/null`, so a host absent
  from this file cannot be reached.
