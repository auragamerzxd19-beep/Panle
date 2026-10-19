#!/usr/bin/env bash
# AuraPanel installer - works on Debian/Ubuntu, RHEL/Alma/Rocky/Fedora, Alpine
# and on container platforms like Railway (no systemd).
#
# Usage:  curl -fsSL https://YOUR-DOMAIN/install | bash
set -euo pipefail

# ---------- config (override with env vars) ----------
APP_NAME="${APP_NAME:-AuraPanel}"
REPO_URL="${REPO_URL:-https://github.com/airlinklabs/panel.git}"   # upstream (MIT)
BRANCH="${BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/aurapanel}"
PORT="${PORT:-3000}"
NODE_MAJOR="${NODE_MAJOR:-20}"

C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_0="\033[0m"
say()  { echo -e "${C_G}[${APP_NAME}]${C_0} $*"; }
warn() { echo -e "${C_Y}[warn]${C_0} $*"; }
die()  { echo -e "${C_R}[error]${C_0} $*" >&2; exit 1; }

# ---------- environment detection ----------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 && SUDO="sudo" || die "Run as root or install sudo."
fi

IS_RAILWAY=0
[ -n "${RAILWAY_ENVIRONMENT:-}" ] || [ -n "${RAILWAY_PROJECT_ID:-}" ] && IS_RAILWAY=1
HAS_SYSTEMD=0
[ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && HAS_SYSTEMD=1

if [ "$IS_RAILWAY" -eq 1 ]; then
  INSTALL_DIR="${INSTALL_DIR_RAILWAY:-/app}"
  say "Railway detected -> container mode (uses \$PORT, no systemd)."
fi

# ---------- package manager ----------
if   command -v apt-get >/dev/null; then PM=apt
elif command -v dnf     >/dev/null; then PM=dnf
elif command -v yum     >/dev/null; then PM=yum
elif command -v apk     >/dev/null; then PM=apk
else die "Unsupported OS (no apt/dnf/yum/apk found)."; fi
say "Package manager: $PM"

install_base() {
  case $PM in
    apt) $SUDO apt-get update -y
         $SUDO apt-get install -y curl git ca-certificates build-essential python3 openssl ;;
    dnf) $SUDO dnf install -y curl git ca-certificates gcc-c++ make python3 openssl ;;
    yum) $SUDO yum install -y curl git ca-certificates gcc-c++ make python3 openssl ;;
    apk) $SUDO apk add --no-cache curl git ca-certificates build-base python3 openssl bash libc6-compat ;;
  esac
}

install_node() {
  if command -v node >/dev/null && [ "$(node -v | tr -d v | cut -d. -f1)" -ge 18 ]; then
    say "Node $(node -v) already installed."; return
  fi
  say "Installing Node.js ${NODE_MAJOR}..."
  case $PM in
    apt) curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | $SUDO -E bash -
         $SUDO apt-get install -y nodejs ;;
    dnf|yum) curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | $SUDO -E bash -
         $SUDO $PM install -y nodejs ;;
    apk) $SUDO apk add --no-cache nodejs npm ;;
  esac
}

# ---------- install ----------
install_base
install_node

say "Fetching source into $INSTALL_DIR ..."
$SUDO mkdir -p "$INSTALL_DIR"
$SUDO chown "$(id -u):$(id -g)" "$INSTALL_DIR"
if [ -d "$INSTALL_DIR/.git" ]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ---------- rebrand (display text only - never touches code identifiers) ----------
say "Applying ${APP_NAME} branding..."
find . -type f \( -name '*.ejs' -o -name '*.html' -o -name '*.md' -o -name '*.json' \) \
  -not -path './node_modules/*' -not -path './.git/*' -not -name 'package-lock.json' \
  -exec sed -i "s/Airlink Panel/${APP_NAME}/g; s/AirLink Panel/${APP_NAME}/g; s/Airlink/${APP_NAME}/g; s/AirLink/${APP_NAME}/g" {} + || true
# NOTE: LICENSE file is intentionally left untouched (MIT requires keeping it).

# ---------- .env ----------
if [ ! -f .env ]; then
  [ -f example.env ] && cp example.env .env || touch .env
fi
set_env() { # key value
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=\"$2\"|" .env; else echo "$1=\"$2\"" >> .env; fi
}
set_env NODE_ENV production
set_env PORT "$PORT"
set_env NAME "$APP_NAME"
grep -q '^SESSION_SECRET=' .env && ! grep -q '^SESSION_SECRET=""' .env \
  || set_env SESSION_SECRET "$(openssl rand -hex 32)"
grep -q '^DATABASE_URL=' .env || set_env DATABASE_URL "file:./dev.db"

# ---------- build ----------
say "Installing dependencies..."
npm install --no-audit --no-fund
say "Preparing database & building..."
npx prisma generate 2>/dev/null || true
(npm run migrate:dev -- --name init 2>/dev/null || npx prisma migrate deploy 2>/dev/null || npx prisma db push 2>/dev/null) || warn "DB migration step skipped - check your package.json scripts."
npm run build

# ---------- run ----------
if [ "$IS_RAILWAY" -eq 1 ]; then
  say "Build done. Railway will run: npm start (listening on \$PORT)."
  exit 0
fi

if [ "$HAS_SYSTEMD" -eq 1 ]; then
  say "Creating systemd service..."
  $SUDO tee /etc/systemd/system/aurapanel.service >/dev/null <<EOF
[Unit]
Description=${APP_NAME}
After=network.target

[Service]
WorkingDirectory=${INSTALL_DIR}
ExecStart=$(command -v npm) start
Restart=always
RestartSec=5
EnvironmentFile=${INSTALL_DIR}/.env
User=$(id -un)

[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now aurapanel
else
  warn "No systemd found -> using pm2 as process manager."
  $SUDO npm install -g pm2
  pm2 start npm --name aurapanel -- start
  pm2 save || true
fi

IP="$(curl -fsS https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
say "Done! Open: http://${IP}:${PORT}"
