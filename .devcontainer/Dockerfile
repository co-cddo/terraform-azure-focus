# trivy:ignore:DS-0026 HEALTHCHECK not necessary for a dev container
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04@sha256:d94c97dd9cacf183d0a6fd12a8e87b526e9e928307674ae9c94139139c0c6eae

ARG AZURE_CLI_VERSION="2.73.0"
ARG CHECKOV_VERSION="3.2.529"
ARG CHECKOV_SHA256="fb2d5418913343933e0b33442b7cb49b373af75f4f919c094d6c3b6fb3d03d36"
ARG POWERSHELL_VERSION="7.4.6"
ARG PRE_COMMIT_VERSION="3.7.1"
ARG PRE_COMMIT_SHA256="fae36fd1d7ad7d6a5a1c0b0d5adb2ed1a3bda5a21bf6c3e5372073d7a11cd4c5"
ARG SHELLCHECK_VERSION="0.10.0"
ARG SHELLCHECK_SHA256_X86_64="6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87"
ARG SHELLCHECK_SHA256_AARCH64="324a7e89de8fa2aed0d0c28f3dab59cf84c6d74264022c00c22af665ed1a09bb"
ARG TERRAFORM_DOCS_VERSION="0.20.0"
ARG TERRAFORM_VERSION="1.15.5"
ARG TFLINT_VERSION="0.61.0"
ARG TRIVY_VERSION="0.69.3"

HEALTHCHECK --interval=5m --timeout=3s \
  CMD terraform --version || exit 1

# Base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl unzip xz-utils python3 python3-venv gnupg \
    && rm -rf /var/lib/apt/lists/*

# azure-cli via Microsoft apt repo (GPG-verified, pinned version)
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] \
        https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends azure-cli=${AZURE_CLI_VERSION}-1~$(lsb_release -cs) \
    && rm -rf /var/lib/apt/lists/*

# powershell with SHA256 verification (deb for amd64, tar.gz for arm64)
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/hashes.sha256" \
        -o /tmp/powershell_hashes.sha256 \
    && if [ "${ARCH}" = "amd64" ]; then \
        curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell_${POWERSHELL_VERSION}-1.deb_amd64.deb" \
            -o "/tmp/powershell_${POWERSHELL_VERSION}-1.deb_amd64.deb" \
        && (cd /tmp && grep "powershell_${POWERSHELL_VERSION}-1.deb_amd64.deb" powershell_hashes.sha256 | sha256sum -c) \
        && apt-get update && apt-get install -y --no-install-recommends "/tmp/powershell_${POWERSHELL_VERSION}-1.deb_amd64.deb" \
        && rm "/tmp/powershell_${POWERSHELL_VERSION}-1.deb_amd64.deb" \
        && rm -rf /var/lib/apt/lists/*; \
    else \
        curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-arm64.tar.gz" \
            -o "/tmp/powershell-${POWERSHELL_VERSION}-linux-arm64.tar.gz" \
        && (cd /tmp && grep "powershell-${POWERSHELL_VERSION}-linux-arm64.tar.gz" powershell_hashes.sha256 | sha256sum -c) \
        && mkdir -p /opt/microsoft/powershell/7 \
        && tar -xzf "/tmp/powershell-${POWERSHELL_VERSION}-linux-arm64.tar.gz" -C /opt/microsoft/powershell/7/ \
        && chmod +x /opt/microsoft/powershell/7/pwsh \
        && ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
        && rm "/tmp/powershell-${POWERSHELL_VERSION}-linux-arm64.tar.gz"; \
    fi \
    && rm /tmp/powershell_hashes.sha256

# terraform with SHA256 verification
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" \
        -o "/tmp/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" \
        -o /tmp/terraform_SHA256SUMS \
    && (cd /tmp && grep "terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" terraform_SHA256SUMS | sha256sum -c) \
    && unzip "/tmp/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" terraform -d /usr/local/bin \
    && rm "/tmp/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" /tmp/terraform_SHA256SUMS

# checkov + pre-commit in isolated Python venv (top-level wheels SHA256-verified before install)
RUN python3 -m venv /opt/checkov \
    && /opt/checkov/bin/pip download --no-deps --no-cache-dir --dest /tmp/pip-pkgs \
        "checkov==${CHECKOV_VERSION}" "pre-commit==${PRE_COMMIT_VERSION}" \
    && echo "${CHECKOV_SHA256}  /tmp/pip-pkgs/checkov-${CHECKOV_VERSION}-py3-none-any.whl" | sha256sum -c \
    && echo "${PRE_COMMIT_SHA256}  /tmp/pip-pkgs/pre_commit-${PRE_COMMIT_VERSION}-py2.py3-none-any.whl" | sha256sum -c \
    && /opt/checkov/bin/pip install --no-cache-dir \
        "/tmp/pip-pkgs/checkov-${CHECKOV_VERSION}-py3-none-any.whl" \
        "/tmp/pip-pkgs/pre_commit-${PRE_COMMIT_VERSION}-py2.py3-none-any.whl" \
    && rm -rf /tmp/pip-pkgs

ENV PATH="/opt/checkov/bin:${PATH}"

# shellcheck with hardcoded SHA256 (upstream publishes no checksum file)
RUN ARCH=$(uname -m) \
    && if [ "${ARCH}" = "x86_64" ]; then SC_SHA256="${SHELLCHECK_SHA256_X86_64}"; else SC_SHA256="${SHELLCHECK_SHA256_AARCH64}"; fi \
    && curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${ARCH}.tar.xz" \
        -o /tmp/shellcheck.tar.xz \
    && echo "${SC_SHA256}  /tmp/shellcheck.tar.xz" | sha256sum -c \
    && tar -xJ -C /tmp -f /tmp/shellcheck.tar.xz \
    && mv "/tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/ \
    && rm -rf "/tmp/shellcheck-v${SHELLCHECK_VERSION}" /tmp/shellcheck.tar.xz

# tflint with SHA256 verification
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${ARCH}.zip" \
        -o "/tmp/tflint_linux_${ARCH}.zip" \
    && curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/checksums.txt" \
        -o /tmp/tflint_checksums.txt \
    && (cd /tmp && grep "tflint_linux_${ARCH}.zip" tflint_checksums.txt | sha256sum -c) \
    && unzip "/tmp/tflint_linux_${ARCH}.zip" tflint -d /usr/local/bin \
    && rm "/tmp/tflint_linux_${ARCH}.zip" /tmp/tflint_checksums.txt

# trivy with SHA256 verification
RUN ARCH=$(uname -m) \
    && TRIVY_ARCH=$([ "${ARCH}" = "x86_64" ] && echo "64bit" || echo "ARM64") \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" \
        -o "/tmp/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_checksums.txt" \
        -o /tmp/trivy_checksums.txt \
    && (cd /tmp && grep "trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" trivy_checksums.txt | sha256sum -c) \
    && tar -xz -C /usr/local/bin -f "/tmp/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" trivy \
    && rm "/tmp/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" /tmp/trivy_checksums.txt

# terraform-docs with SHA256 verification
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${ARCH}.tar.gz" \
        -o "/tmp/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${ARCH}.tar.gz" \
    && curl -fsSL "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}.sha256sum" \
        -o /tmp/terraform-docs_sha256sum \
    && (cd /tmp && grep "terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${ARCH}.tar.gz" terraform-docs_sha256sum | sha256sum -c) \
    && tar -xz -C /usr/local/bin -f "/tmp/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${ARCH}.tar.gz" terraform-docs \
    && chmod +x /usr/local/bin/terraform-docs \
    && rm "/tmp/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-${ARCH}.tar.gz" /tmp/terraform-docs_sha256sum

USER vscode
