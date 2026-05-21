# Self-Hosted Runner Container (OIDC)

A GitHub Actions self-hosted runner container image pre-loaded with common DevOps tools. Registers itself against a GitHub organization using an Azure user-assigned managed identity — no PAT, no static GitHub credentials in the container.

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
3. `start.sh` pulls those secrets, mints a short-lived GitHub App JWT (RS256, via `openssl`), exchanges it for an installation access token, and uses that token to request a runner registration token from `POST /orgs/{org}/actions/runners/registration-token`.
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

### Environment Variables

| Variable                            | Required | Description                                                                                |
| ----------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| `ORGANIZATION`                      | Yes      | GitHub organization to register the runner under                                           |
| `AZURE_KEY_VAULT_NAME`              | Yes      | Name of the Key Vault holding the GitHub App credentials                                   |
| `AZURE_CLIENT_ID`                   | No       | Client ID of the user-assigned managed identity. Omit to use the system-assigned identity. |
| `GITHUB_APP_ID_SECRET_NAME`         | No       | Key Vault secret name for the App ID (default: `github-app-id`)                            |
| `GITHUB_APP_PRIVATE_KEY_SECRET_NAME`| No       | Key Vault secret name for the PEM private key (default: `github-app-private-key`)          |
| `GITHUB_APP_INSTALLATION_ID`        | No       | Installation ID. If omitted, it is looked up from `/orgs/{org}/installation`.              |
| `RUNNER_NAME`                       | No       | Runner name (defaults to container hostname)                                               |
| `LABELS`                            | No       | Comma-separated labels to apply to the runner                                              |

## Building Locally

```bash
docker build -t self-hosted-runner -f linux/Dockerfile .
```

To pin a specific runner version:

```bash
docker build --build-arg RUNNER_VERSION=2.321.0 -t self-hosted-runner -f linux/Dockerfile .
```

## Publishing

The image is automatically built and pushed to `ghcr.io` when a GitHub release is published. Create a release with a semver tag (e.g., `v1.0.0`) to trigger the workflow.
