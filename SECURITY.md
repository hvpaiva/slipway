# Security

## Supported versions

Slipway is pre-1.0. Only the latest 0.x release published on RubyGems receives security fixes;
older releases are not patched. Run `slipway version` to see what you have.

| Version | Supported |
| --- | --- |
| Latest 0.x | Yes |
| Anything older | No |

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately through GitHub's
private vulnerability reporting on the repository:

https://github.com/hvpaiva/slipway/security/advisories/new

If that is not an option for you, email contact@hvpaiva.dev with "slipway security" in the
subject.

Include what you can of the following:

- The version (`slipway version` output) and the operating system.
- What the problem is and what an attacker gains from it.
- Steps or a manifest, config file or command line that reproduces it.
- Whether you have already shared it anywhere else.

Slipway reads files under the user's own home directory and runs `git` against directories the
user registered, so the areas worth attention are: a manifest or config file crafted by someone
else and applied with `slipway apply -f`, the way `git` is invoked on a registered path, and
the temporary files `edit` writes.

## What happens next

You will get an acknowledgment, usually within a few days; this is a one-person project, so
there is no guaranteed response time. I will confirm the problem, work out a fix and agree on
a disclosure date with you. Fixes ship as a new version on RubyGems, and the changelog entry for
that version references the advisory. If the vulnerable version has to be pulled, it is yanked
from RubyGems after the fixed one is available. Credit goes to the reporter unless you prefer
otherwise.
