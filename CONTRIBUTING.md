# Contributing

Thank you for your interest in contributing to OSDU SPI Infrastructure.

## Prerequisites

See the [Prerequisites](https://danielscholl-osdu.github.io/osdu-spi-infra/getting-started/prerequisites/) documentation for required tools.

## Development Workflow

1. **Fork** the repository (or create a feature branch if you have write access)
2. **Make changes** in a topic branch
3. **Validate locally** before pushing:

   ```bash
   # Terraform formatting (must pass CI)
   terraform fmt -check -recursive

   # Terraform validation per layer
   cd infra && terraform init -backend=false && terraform validate && cd ..
   cd infra-access && terraform init -backend=false && terraform validate && cd ..
   cd software/foundation && terraform init -backend=false && terraform validate && cd ../..
   cd software/stack && terraform init -backend=false && terraform validate && cd ../..

   # Docs build
   cd docs && npm ci && npm run build && cd ..
   ```

4. **Open a pull request** against `main`

## PR Requirements

All pull requests must pass the following CI checks before merging:

| Check | What it validates |
|---|---|
| `terraform-fmt` | All `.tf` files are formatted with `terraform fmt` |
| `terraform-validate` | Each Terraform layer initializes and validates successfully |
| `docs-build` | The Starlight documentation site builds without errors |

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
feat(infra): add new storage account for partition data
fix(stack): correct health probe port for unit service
docs: update deployment model documentation
ci: add scheduled smoke test workflow
chore(deps): bump azurerm provider to 4.1.0
```

## Dependency Updates

Dependencies are managed by Dependabot with weekly update checks:

- **Terraform providers** — grouped by provider family (Azure, HashiCorp utilities, Helm)
- **npm packages** — for the documentation site
- **GitHub Actions** — workflow action versions

After merging dependency updates, regenerate third-party notices if npm packages changed:

```bash
npm run notice
git add THIRD-PARTY-NOTICES.txt
```

## Architecture Decisions

Significant design changes should be documented as ADRs in `docs/src/content/docs/decisions/`. Use the template at `docs/decisions/adr-template.md` and number sequentially.

## Smoke Tests

A weekly smoke test deploys the full stack (`azd up`) and tears it down to catch regressions from provider updates, Azure API changes, or image breakage. Failures automatically create a GitHub issue labeled `smoke-test-failed` and `human-required`.

## License

By contributing, you agree that your contributions will be licensed under the [Apache License 2.0](LICENSE).
