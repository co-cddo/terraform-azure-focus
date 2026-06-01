#!/bin/sh
# Runs on the HOST as initializeCommand, before the container is created.
# Reads the git identity from the host's global git config and writes it to
# .devcontainer/.git-env so post-create.sh can apply it inside the container.
set -e

GIT_NAME=$(git config --global user.name 2>/dev/null || true)
GIT_EMAIL=$(git config --global user.email 2>/dev/null || true)

# Fail early with a clear message rather than letting commits fail inside the container
if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    echo ""
    echo "ERROR: Git identity is not configured on your host."
    echo "Run the following, then reopen the container:"
    echo ""
    echo '  git config --global user.name  "Your Name"'
    echo '  git config --global user.email "you@example.com"'
    echo ""
    exit 1
fi

printf '%s\n%s\n' "$GIT_NAME" "$GIT_EMAIL" > .devcontainer/.git-env
