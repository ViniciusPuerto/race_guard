# Security policy

`race_guard` instruments Ruby and Rails application code (for example by prepending methods and observing transactions). We take reports about vulnerabilities in this gem seriously.

## Supported versions

Security fixes are applied to the latest minor release on the current major version line, as far as practical. Very old releases may not receive backports. Check [`CHANGELOG.md`](CHANGELOG.md) and released tags for current state.

## Reporting a vulnerability

**Please do not** use public GitHub issues to report security problems.

1. **Preferred:** If the repository is hosted on GitHub, use [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) for this repository, if the feature is enabled.
2. **Alternative:** Email maintainers (see the address in [`race_guard.gemspec`](race_guard.gemspec)) with a clear subject line (e.g. `security: race_guard`) and enough detail to reproduce or understand the issue.

Please allow reasonable time for triage and a fix before public disclosure. We will coordinate a release and changelog entry for confirmed issues.

## Scope

Reports should concern **this gem** and its public APIs, extensions, and documented integration points. For vulnerabilities in your application that uses `race_guard`, or in third-party dependencies, use the appropriate channel for that project.

## CoC and conduct reports

For **security vulnerabilities**, use the channels above. For **code of conduct** issues (harassment, abuse of community spaces), read [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) and report to the same maintainer contact as in the gemspec, or use GitHub if the project enables private or moderator reporting there.
