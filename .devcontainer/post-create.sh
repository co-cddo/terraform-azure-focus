#!/bin/sh
# Runs inside the container as postCreateCommand, after the container is created.
set -e

# Apply the git identity captured from the host by init-git-config.sh
GIT_USER_NAME=$(sed -n '1p' .devcontainer/.git-env)
GIT_USER_EMAIL=$(sed -n '2p' .devcontainer/.git-env)
git config --global user.name  "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

# Required when the repo is bind-mounted and owned by a different UID than the container user.
# Use the actual workspace path (postCreateCommand runs from the workspace folder).
git config --global --add safe.directory "$(pwd)"

# Install the pre-commit git hook and pre-build the hook environments defined
# in .pre-commit-config.yaml, so the first commit doesn't pay the setup cost.
pre-commit install --install-hooks

# Download tflint plugins declared in .tflint.hcl so the tflint hook works
# without requiring a manual "tflint --init" after container creation.
tflint --init
