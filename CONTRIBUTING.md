# Contributing to AI Lab Bootstrap

Thank you for your interest in contributing! This is a bootstrap infrastructure project, and we welcome improvements, fixes, and ideas from the community.

## How to Contribute

### 1. Issues

- **Bug reports**: Open an issue with the `bug` label. Include:
  - OS version and environment details
  - The exact command that failed
  - Full error output (sanitize any secrets)
- **Feature requests**: Open an issue with the `enhancement` label. Explain the use case and why it benefits the broader community (not just your setup).

### 2. Pull Requests

1. Fork the repository.
2. Create a branch with a descriptive name: `fix/description`, `feat/description`.
3. Make your changes following the existing code style.
4. Test your changes — ideally on a fresh Ubuntu 24.04 VM or container.
5. Submit a PR against the `main` branch.

### 3. Commit Guidelines

- Use Spanish for commit messages (consistent with existing history).
- Format: `tipo: descripción breve` (e.g., `feat: add ollama module`, `fix: resolve tailscale race on boot`).
- Keep commits focused and atomic.
- **Commits must be authored by a human.** We do not accept commits signed or authored by AI tools, bots, or automated systems. Every contribution must be written, reviewed, and committed by a real person using their personal GitHub identity. This ensures all contributions are human-verified and accountable.

### 4. Code Style

- **Shell scripts**: Use `bash` with `set -euo pipefail`. Follow the patterns in `modules/`.
- **PowerShell**: Follow the patterns in `modules/windows-host/`.
- **Python**: Follow PEP 8. Existing scripts in `knowledge-pipeline/` use Python 3.10+.
- **Config files**: YAML for Dagu DAGs, `.env.example` for secrets templates (never commit real secrets).

### 5. Documentation

If your change adds or modifies behavior, update the relevant documentation:
- Root `README.md` for user-facing changes.
- `docs/` for detailed operational or architectural changes.
- Inline comments in scripts for non-obvious logic.

### 6. Security

- Never commit secrets, API keys, tokens, or credentials.
- Use `.env.example` templates for any new configuration.
- Follow the practices in `docs/SECURITY_GUIDE.md`.

## Code of Conduct

All contributors must follow our [Code of Conduct](CODE_OF_CONDUCT.md).
