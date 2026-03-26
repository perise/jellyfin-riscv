# Jellyfin on Linux RISC-V 64-bit (linux-riscv64)

This branch adds support for running Jellyfin on RISC-V 64-bit Linux systems,
tested on the SpacemiT K1 SoC (Bianbu OS 2.2.1, kernel 6.6.x).

## Status

| Component | Status | Notes |
|-----------|--------|-------|
| Server core | ✅ Working | Full media server, API, database |
| Web UI | ✅ Working | Install `jellyfin-web` separately (see below) |
| SQLite | ✅ Working | Uses system `libsqlite3` via symlink shim |
| HarfBuzz | ✅ Working | Native binary bundled in package |
| SkiaSharp / image processing | ⚠️ Fallback | No riscv64 binary; falls back to `NullImageEncoder` |
| ffmpeg hardware acceleration | 🔧 Optional | Use [ffmpeg-spacemit](https://github.com/perise/ffmpeg-spacemit) |

## What changed from upstream

- `Jellyfin.Server/CoreAppHost.cs`: Wrap `SkiaEncoder.IsNativeLibAvailable()` call in
  try-catch to handle `TypeInitializationException` on platforms where `libSkiaSharp`
  is missing (the static constructor throws before the method's own catch can fire).

## Prerequisites on the RISC-V board

1. **libsqlite3** (system package):
   ```
   sudo apt install libsqlite3-0
   ```

2. **.NET 9 runtime for RISC-V** — use the community build by
   [dkurt/dotnet_riscv](https://github.com/dkurt/dotnet_riscv/releases/tag/v9.0.100):
   ```bash
   mkdir -p ~/dotnet9
   wget https://github.com/dkurt/dotnet_riscv/releases/download/v9.0.100/dotnet-sdk-9.0.100-linux-riscv64-gcc-ubuntu-24.04.tar.gz
   tar -xzf dotnet-sdk-9.0.100-linux-riscv64-gcc-ubuntu-24.04.tar.gz -C ~/dotnet9
   # Keep only the runtime (saves ~370 MB)
   rm -rf ~/dotnet9/sdk ~/dotnet9/packs
   ```

3. **Symlink system SQLite** as `libe_sqlite3.so` in the jellyfin runtimes dir:

   `SQLitePCLRaw` (used by Jellyfin's EF Core layer) looks for a bundled library
   called `libe_sqlite3.so` under `runtimes/linux-riscv64/native/`. No pre-built copy
   exists for riscv64, but the system `libsqlite3` works as a drop-in replacement:
   ```bash
   mkdir -p jellyfin-server/runtimes/linux-riscv64/native
   ln -sf /lib/riscv64-linux-gnu/libsqlite3.so.0 \
     jellyfin-server/runtimes/linux-riscv64/native/libe_sqlite3.so
   ```
   Without this symlink the server crashes on startup with
   `DllNotFoundException: Unable to load shared library 'e_sqlite3'`.

4. **Web client** (`jellyfin-web`) — the server binary does **not** bundle the web UI.
   Download the pre-built Debian package (arch-independent) and extract the static files:
   ```bash
   wget https://lon1.mirror.jellyfin.org/files/server/debian/stable/v10.11.6/amd64/jellyfin-web_10.11.6+deb12_all.deb
   dpkg-deb -x jellyfin-web_10.11.6+deb12_all.deb /tmp/jf-web
   # Place the static files where the server expects them
   mv /tmp/jf-web/usr/share/jellyfin/web ~/jellyfin-server/jellyfin-web
   ```
   The server looks for web assets at `<app-dir>/jellyfin-web/`. Without this directory
   the server starts in API-only mode (`--nowebclient`) and `http://<ip>:8096` will only
   serve the Swagger docs at `/api-docs/swagger/index.html`.

## Build (on any x86/arm machine with .NET 9 SDK)

```bash
dotnet publish Jellyfin.Server/Jellyfin.Server.csproj \
  --configuration Release \
  --no-self-contained \
  --output jellyfin-server
```

## Deploy & Run

```bash
# Transfer jellyfin-server/ to the board, then:
DOTNET_ROOT=~/dotnet9 ~/dotnet9/dotnet ~/jellyfin-server/jellyfin.dll \
  --datadir ~/jellyfin-data
```

The server listens on `0.0.0.0:8096`. Open `http://<board-ip>:8096` in a browser —
it redirects to the setup wizard at `/web/index.html`.

> **Note:** If `jellyfin-web/` is missing, the server falls back to API-only mode and
> the root URL will only serve the Swagger docs. Install the web client (step 4 above)
> to get the full UI.

## One-shot setup script

See `deployment/linux-riscv64/setup.sh` for a complete installation script.
