FROM ubuntu:24.04

ARG RUNNER_VERSION=2.321.0
ARG DEBIAN_FRONTEND=noninteractive

# System packages
RUN apt-get update && apt-get install -y \
    apt-utils \
    ca-certificates \
    curl \
    git \
    iputils-ping \
    jq \
    lsb-release \
    gpg \
    gnupg \
    nodejs \
    npm \
    openssl \
    wget \
    unzip \
    dos2unix \
    software-properties-common \
    pipx \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Azure CLI + Bicep
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && az bicep install

# .NET SDK 8.0
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y dotnet-sdk-8.0 \
    && rm -rf /var/lib/apt/lists/*

# Terraform & Packer (HashiCorp)
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null \
    && apt-get update && apt-get install -y terraform packer \
    && rm -rf /var/lib/apt/lists/*

# Helm
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubectl
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
      | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
      | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null \
    && apt-get update && apt-get install -y kubectl \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (no daemon)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# ORAS CLI
RUN ORAS_VERSION=$(curl -fsSL https://api.github.com/repos/oras-project/oras/releases/latest | jq -r '.tag_name' | sed 's/^v//') \
    && curl -fsSL https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz \
         -o oras.tar.gz \
    && tar xzf oras.tar.gz -C /usr/local/bin oras \
    && rm oras.tar.gz

# Terraform security tools — tfsec
RUN TFSEC_VERSION=$(curl -fsSL https://api.github.com/repos/aquasecurity/tfsec/releases/latest | jq -r '.tag_name') \
    && curl -fsSL https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec-linux-amd64 \
         -o /usr/local/bin/tfsec \
    && chmod +x /usr/local/bin/tfsec

# Terraform security tools — trivy
RUN TRIVY_VERSION=$(curl -fsSL https://api.github.com/repos/aquasecurity/trivy/releases/latest | jq -r '.tag_name' | sed 's/^v//') \
    && curl -fsSL https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz \
         -o trivy.tar.gz \
    && tar xzf trivy.tar.gz -C /usr/local/bin trivy \
    && rm trivy.tar.gz

# Terraform security tools — checkov
RUN pipx install checkov

# Runner user and GitHub Actions Runner
RUN useradd -m runner
WORKDIR /home/runner/actions-runner

RUN curl -fsSL https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
      -o actions-runner.tar.gz \
    && tar xzf actions-runner.tar.gz \
    && rm actions-runner.tar.gz \
    && ./bin/installdependencies.sh \
    && chown -R runner:runner /home/runner/actions-runner

COPY linux/start.sh /home/runner/actions-runner/start.sh
RUN dos2unix /home/runner/actions-runner/start.sh \
    && chmod +x /home/runner/actions-runner/start.sh

USER runner
ENTRYPOINT ["/home/runner/actions-runner/start.sh"]
