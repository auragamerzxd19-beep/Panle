# AuraPanel installer

## Any VPS
Host install.sh on your own domain / GitHub raw, then:
    curl -fsSL https://YOUR-DOMAIN/install | bash

Or run locally:
    bash install.sh

## Railway
Push these files to a GitHub repo -> Railway -> Deploy from GitHub.

## Options (env vars)
APP_NAME, REPO_URL, BRANCH, INSTALL_DIR, PORT, NODE_MAJOR

Based on Airlink panel (MIT). Keep the original LICENSE and credit.
