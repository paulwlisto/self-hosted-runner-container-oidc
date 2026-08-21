# Self-Hosted Runner Container (OIDC)

A GitHub Actions self-hosted runner container image pre-loaded with common DevOps tools. Registers itself against a GitHub organization using an Azure user-assigned managed identity — no PAT, no static GitHub credentials in the container. Targets `github.com` by default, and GitHub Enterprise Cloud with data residency (`customer.ghe.com`) via a single environment variable.

## Included Tools

- GitHub CLI (`gh`)
- Azure CLI (`az`)
- .NET SDK 8.0
- Terraform
- Packer
- Helm
- kubectl
- Python 3 + pip
- Node.js + npm
- Git, curl, wget, jq, unzip, openssl

## How registration works

1. Container starts and runs `az login --identity` using the Azure user-assigned managed identity bound to its host (AKS pod identity / ACI / VM).
2. The managed identity has `get` permission on an Azure Key Vault that stores the GitHub App's `app id` and PEM private key.
3. `start.sh` pulls those secrets, mints a short-lived GitHub App JWT (RS256, via `openssl`), exchanges it for an installation access token, and uses that token to request a runner registration token from `POST /orgs/{org}/actions/runners/registration-token` on the configured API host.
4. `config.sh` registers the runner; on container shutdown it deregisters.

No long-lived GitHub credential is ever stored in the image or environment.

## Prerequisites (one-time setup)

1. **Create a GitHub App** owned by your organization. Grant org permissions: `Self-hosted runners: Read & write`. Install it on the target org.
2. **Store its credentials in Azure Key Vault** as two secrets (names are configurable):
   - `github-app-id` — the numeric App ID
   - `github-app-private-key` — the PEM private key, including `-----BEGIN/END-----` lines
3. **Create a user-assigned managed identity** and grant it `Key Vault Secrets User` on the vault.
4. **Attach the managed identity** to whatever runs the container (AKS workload identity, ACI, VMSS, etc.).

## Usage

```bash
docker run -d \
  -e ORGANIZATION=<your-github-org> \
  -e AZURE_KEY_VAULT_NAME=<your-keyvault-name> \
  -e AZURE_CLIENT_ID=<user-assigned-mi-client-id> \
  -e RUNNER_NAME=my-runner \
  -e LABELS=linux,docker \
  ghcr.io/<owner>/self-hosted-runner-container:latest
```

### GitHub Enterprise Cloud with data residency

Set `GITHUB_HOST` to your tenant subdomain. Everything else is unchanged — the
runner registers at `https://customer.ghe.com/<org>` and all API calls go to
`https://api.customer.ghe.com`.

```bash
docker run -d   -e GITHUB_HOST=customer.ghe.com   -e ORGANIZATION=<your-github-org>   -e AZURE_KEY_VAULT_NAME=<your-keyvault-name>   -e AZURE_CLIENT_ID=<user-assigned-mi-client-id>   ghcr.io/<owner>/self-hosted-runner-container:latest
```

Notes for data residency tenants:

- The GitHub App must be created and installed **on your `ghe.com` tenant**, not
  on github.com. Its App ID and private key go in Key Vault as usual.
- `GH_HOST` is written to the runner's `.env`, so `gh` commands inside your
  workflow steps target the tenant rather than github.com. `GITHUB_SERVER_URL`
  and `GITHUB_API_URL` are set per-job by the runner itself.
- Outbound network access is required to `*.<subdomain>.ghe.com` and
  `*.actions.<subdomain>.ghe.com`, plus `*.githubassets.com`,
  `*.githubusercontent.com`, and `*.blob.core.windows.net`.
- **github.com access is still required**, both at image build time (the runner
  binary is downloaded from `github.com/actions/runner/releases`) and at runtime
  for runner self-updates and pulling actions from the public marketplace. Only
  the registration and API traffic follows `GITHUB_HOST`. See
  [Network details for GHE.com](https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom).

### GitHub Enterprise Server

GHES serves its API under `/api/v3` rather than an `api.` subdomain, so set both
variables explicitly:

```bash
  -e GITHUB_HOST=github.corp.example.com   -e GITHUB_API_URL=https://github.corp.example.com/api/v3
```

### Environment Variables

| Variable                            | Required | Description                                                                                |
| ----------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| `ORGANIZATION`                      | Yes      | GitHub organization to register the runner under                                           |
| `AZURE_KEY_VAULT_NAME`              | Yes      | Name of the Key Vault holding the GitHub App credentials                                   |
| `AZURE_CLIENT_ID`                   | No       | Client ID of the user-assigned managed identity. Omit to use the system-assigned identity. |
| `GITHUB_HOST`                       | No       | GitHub host to register against (default: `github.com`). For data residency set your tenant subdomain, e.g. `customer.ghe.com`. |
| `GITHUB_API_URL`                    | No       | Override the derived REST API base URL. Required only for GitHub Enterprise Server. |
| `GITHUB_SERVER_URL`                 | No       | Override the derived web URL (default: `https://$GITHUB_HOST`).                             |
| `GITHUB_APP_ID_SECRET_NAME`         | No       | Key Vault secret name for the App ID (default: `github-app-id`)                            |
| `GITHUB_APP_PRIVATE_KEY_SECRET_NAME`| No       | Key Vault secret name for the PEM private key (default: `github-app-private-key`)          |
| `GITHUB_APP_INSTALLATION_ID`        | No       | Installation ID. If omitted, it is looked up from `/orgs/{org}/installation`.              |
| `RUNNER_NAME`                       | No       | Runner name (defaults to container hostname)                                               |
| `LABELS`                            | No       | Comma-separated labels to apply to the runner                                              |

## Building Locally

```bash
docker build -t self-hosted-runner -f linux/Dockerfile .
```

### Runner version requirements

GitHub enforces a **minimum runner version of `2.329.0` to register**, and
requires runners to stay within 30 days of the latest release to **execute**
jobs. Enforcement began **31 July 2026** for GitHub Enterprise Cloud with data
residency and **25 September 2026** for GitHub Enterprise Cloud. A runner below
the registration minimum still completes `config.sh` successfully but then
cannot connect — it appears **Offline** in the UI, with no obvious error.

The image therefore tracks a recent runner (`2.336.0`) and relies on the
runner's built-in auto-update to stay current. Auto-update downloads from
`github.com`, so that egress must remain open even on a data residency tenant —
without it the runner will silently drift below the minimum and stop working.
See [the enforcement timeline](https://github.blog/changelog/2026-06-12-github-actions-minimum-version-enforcement-timeline-for-self-hosted-runners/).

To pin a specific runner version:

```bash
docker build --build-arg RUNNER_VERSION=2.336.0 -t self-hosted-runner -f linux/Dockerfile .
```

## Publishing

The image is automatically built and pushed to `ghcr.io` when a GitHub release is published. Create a release with a semver tag (e.g., `v1.0.0`) to trigger the workflow.
