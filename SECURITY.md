# Security Policy

## Reporting a Vulnerability

This project handles infrastructure provisioning that involves API keys, secrets, and network configuration. If you discover a security vulnerability, please do **not** open a public issue.

Instead, report it privately via email:

**almacreativa@users.noreply.github.com**

We will acknowledge receipt within 48 hours and provide an estimated timeline for a fix. We ask that you allow us reasonable time to address the issue before any public disclosure.

## Scope

The following are in scope for security reports:

- The bootstrap scripts (`bootstrap.sh`, `bootstrap-macos.sh`, `bootstrap-windows.ps1`, `modules/`)
- Configuration templates (`configs/`, `templates/`)
- Operational scripts (`ops/`, `scripts/`)
- Documentation files that describe security-sensitive practices

## What we expect from reporters

- Provide a clear description of the vulnerability and a reproducible test case
- Do not access or modify production data beyond what is necessary to demonstrate the issue
- Delete any secrets or credentials obtained during research after the report is resolved

## Security Best Practices

For operators of this lab, refer to:

- [`docs/SECURITY_GUIDE.md`](docs/SECURITY_GUIDE.md) — UFW baseline, secrets handling, container security
- [`docs/SECRETS_INVENTORY.md`](docs/SECRETS_INVENTORY.md) — where secrets live, rotation schedule, permissions
- [`ops/runbooks/secrets-management.md`](ops/runbooks/secrets-management.md) — operational runbook for secrets

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | ✅ Yes    |
| Older   | ❌ No     |

We always recommend using the latest commit from the `main` branch.
