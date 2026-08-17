# Security policy

## Supported versions

No released version exists. This repository has no supported application
version at this revision. Security fixes will be assessed for the active
development branch when an application exists.

## Report a vulnerability

Do not publish an issue for a suspected vulnerability before a maintainer
has assessed it. Use the repository hosting service's private security
advisory function, when it is enabled. Include:

- affected revision or commit ID;
- macOS version and Apple silicon model;
- clear reproduction steps or a minimal proof of concept;
- expected and actual security effect; and
- a safe contact method for follow-up.

No project security email is published yet. If a private advisory channel
is unavailable, do not disclose exploit details in public channels.
Ask a maintainer to publish a private reporting channel first.

## Handling expectations

Maintainers will acknowledge a valid private report when a response
channel exists, investigate it, and coordinate a fix before public
disclosure where practical. No response-time, bounty, CVE, or release
service level is promised at this stage.

## Security boundaries

The planned core is offline-first. Network isolation does not make image
parsers, plug-ins, imported files, exports, local catalogs, or metadata
safe by itself. Treat imported content as untrusted. Do not include
secrets in the client or repository. Follow the dependency policy and
generate an SBOM for release candidates.
