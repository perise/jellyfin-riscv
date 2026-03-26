#!/usr/bin/env bash
# setup.sh — Install Jellyfin on a linux-riscv64 board (e.g. SpacemiT K1)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/perise/jellyfin-riscv/linux-riscv64/deployment/linux-riscv64/setup.sh | bash
#
# Or clone the repo and run:
#   bash deployment/linux-riscv64/setup.sh
#
# Environment variables:
#   JELLYFIN_DIR   — where to install jellyfin (default: ~/jellyfin-server)
#   DOTNET_DIR     — where to install .NET runtime (default: ~/dotnet9)
#   DATA_DIR       — jellyfin data directory (default: ~/jellyfin-data)

set -euo pipefail

JELLYFIN_DIR="${JELLYFIN_DIR:-$HOME/jellyfin-server}"
DOTNET_DIR="${DOTNET_DIR:-$HOME/dotnet9}"
DATA_DIR="${DATA_DIR:-$HOME/jellyfin-data}"

JELLYFIN_VERSION="10.11.6"
DOTNET_RISCV_URL="https://github.com/dkurt/dotnet_riscv/releases/download/v9.0.100/dotnet-sdk-9.0.100-linux-riscv64-gcc-ubuntu-24.04.tar.gz"
JELLYFIN_WEB_DEB="https://lon1.mirror.jellyfin.org/files/server/debian/stable/v${JELLYFIN_VERSION}/amd64/jellyfin-web_${JELLYFIN_VERSION}+deb12_all.deb"

log() { echo "[setup] $*"; }

# ---------- 1. System dependencies ----------
log "Installing system dependencies..."
sudo apt-get install -y libsqlite3-0 ffmpeg 2>/dev/null || true

# ---------- 2. .NET 9 runtime ----------
if [ -x "$DOTNET_DIR/dotnet" ]; then
    log ".NET runtime already at $DOTNET_DIR"
else
    log "Downloading .NET 9 runtime for linux-riscv64 (~160 MB)..."
    TMP_SDK=$(mktemp --suffix=.tar.gz)
    wget -q --show-progress -O "$TMP_SDK" "$DOTNET_RISCV_URL"
    mkdir -p "$DOTNET_DIR"
    tar -xzf "$TMP_SDK" -C "$DOTNET_DIR"
    rm "$TMP_SDK"
    # Remove SDK build tools — only the runtime is needed for running Jellyfin
    rm -rf "$DOTNET_DIR/sdk" "$DOTNET_DIR/packs"
    log ".NET runtime installed at $DOTNET_DIR"
fi

# ---------- 3. SQLite native shim ----------
NATIVE_DIR="$JELLYFIN_DIR/runtimes/linux-riscv64/native"
mkdir -p "$NATIVE_DIR"
if [ ! -f "$NATIVE_DIR/libe_sqlite3.so" ]; then
    log "Symlinking system libsqlite3 as libe_sqlite3.so..."
    SQLITE_PATH=$(ldconfig -p 2>/dev/null | awk '/libsqlite3\.so\.0/{print $NF; exit}')
    if [ -z "$SQLITE_PATH" ]; then
        SQLITE_PATH=/lib/riscv64-linux-gnu/libsqlite3.so.0
    fi
    ln -sf "$SQLITE_PATH" "$NATIVE_DIR/libe_sqlite3.so"
    log "Symlinked $SQLITE_PATH -> $NATIVE_DIR/libe_sqlite3.so"
fi

# ---------- 4. Web client ----------
# The server binary does not bundle the web UI. Without it, http://<ip>:8096 only
# serves the Swagger API docs. Download the pre-built arch-independent Debian package
# and extract the static files into the expected location.
WEB_DIR="$JELLYFIN_DIR/jellyfin-web"
if [ -f "$WEB_DIR/index.html" ]; then
    log "Web client already present at $WEB_DIR"
else
    log "Downloading jellyfin-web v${JELLYFIN_VERSION} (~30 MB)..."
    TMP_DEB=$(mktemp --suffix=.deb)
    TMP_WEB=$(mktemp -d)
    wget -q --show-progress -O "$TMP_DEB" "$JELLYFIN_WEB_DEB"
    dpkg-deb -x "$TMP_DEB" "$TMP_WEB"
    mv "$TMP_WEB/usr/share/jellyfin/web" "$WEB_DIR"
    rm -rf "$TMP_DEB" "$TMP_WEB"
    log "Web client installed at $WEB_DIR"
fi

# ---------- 5. systemd service (optional) ----------
SERVICE_FILE=/etc/systemd/system/jellyfin.service
if [ ! -f "$SERVICE_FILE" ] && command -v systemctl &>/dev/null; then
    log "Creating systemd service..."
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Jellyfin Media Server (linux-riscv64)
After=network.target

[Service]
Type=simple
User=$USER
Environment=DOTNET_ROOT=$DOTNET_DIR
ExecStart=$DOTNET_DIR/dotnet $JELLYFIN_DIR/jellyfin.dll --datadir $DATA_DIR
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    log "Service installed. Enable with: sudo systemctl enable --now jellyfin"
fi

log ""
log "Setup complete!"
log ""
log "To start Jellyfin:"
log "  DOTNET_ROOT=$DOTNET_DIR $DOTNET_DIR/dotnet $JELLYFIN_DIR/jellyfin.dll --datadir $DATA_DIR"
log ""
log "Then open: http://$(hostname -I | awk '{print $1}'):8096"
log ""
log "Or with systemd:"
log "  sudo systemctl enable --now jellyfin"
