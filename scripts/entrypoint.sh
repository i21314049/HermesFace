#!/bin/bash
set -e

BOOT_START=$(date +%s)

echo "[entrypoint] HermesFace — Hermes Agent + hermes-web-ui on HuggingFace Spaces"
echo "[entrypoint] ================================================================="

HERMES_HOME="/opt/data"
HERMES_WEBUI_HOME="/opt/data/hermes-web-ui"
INSTALL_DIR="/opt/hermes"

# ── DNS pre-resolution (background — non-blocking) ────────────────────────
# Resolves Telegram / WhatsApp / Discord domains via DoH when HF Spaces
# system DNS refuses them. Writes /tmp/dns-resolved.json for dns-fix.cjs
# and appends /etc/hosts for Python processes.
echo "[entrypoint] Starting DNS resolution in background..."
python3 /opt/data/scripts/dns-resolve.py /tmp/dns-resolved.json 2>&1 &
DNS_PID=$!
echo "[entrypoint] DNS resolver PID: $DNS_PID"

# Enable Node.js DNS fix preload for playwright / whatsapp-bridge
export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require /opt/data/scripts/dns-fix.cjs"

# ── HF Space GatewayManager needs /.dockerenv to detect Docker env ────────
# Without this file, GatewayManager tries "gateway start" (systemd) which
# silently fails. This makes it use "gateway run" instead.
if [ ! -f /.dockerenv ]; then
  touch /.dockerenv 2>/dev/null || true
  echo "[entrypoint] Created /.dockerenv for GatewayManager Docker detection"
fi

# ── Activate virtual environment ─────────────────────────────────────────
source "${INSTALL_DIR}/.venv/bin/activate"
echo "[entrypoint] Activated venv: $(which python3)"

# ── Ensure data directories ──────────────────────────────────────────────
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}
mkdir -p "$HERMES_WEBUI_HOME"
touch "$HERMES_HOME/logs/app.log"

export HERMES_HOME

# ── Build artifacts check ────────────────────────────────────────────────
echo "[entrypoint] Build artifacts check:"
command -v hermes >/dev/null 2>&1 && echo "  OK hermes CLI: $(which hermes)" || echo "  WARN: hermes CLI not in PATH"
test -f /app/dist/server/index.js && echo "  OK hermes-web-ui dist" || echo "  WARN: hermes-web-ui dist not found"

ENTRYPOINT_END=$(date +%s)
echo "[TIMER] Entrypoint (before sync_hf.py): $((ENTRYPOINT_END - BOOT_START))s"

# ── Start HermesFace via sync_hf.py (handles persistence + webui launch) ─
echo "[entrypoint] Starting HermesFace via sync_hf.py..."
exec python3 -u /opt/data/scripts/sync_hf.py
