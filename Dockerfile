# HermesFace on Hugging Face Spaces — Source build
# Builds Hermes Agent + hermes-web-ui from source
# Rebuild 2026-04-26: integrate hermes-web-ui via hermes-agent-webui pattern

FROM debian:bookworm-slim
SHELL ["/bin/bash", "-c"]

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# ── System dependencies ──────────────────────────────────────────────────
RUN echo "[build] Installing system deps..." && START=$(date +%s) \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     build-essential libffi-dev libssl-dev \
     python3 python3-venv python3-dev python3-pip \
     ripgrep ffmpeg gcc procps tini \
     git ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
  && pip3 install --no-cache-dir --break-system-packages huggingface_hub requests pyyaml \
  && echo "[build] System deps: $(($(date +%s) - START))s"

# ── Node.js v23 (hermes-web-ui requires node >= 23) ──────────────────────
RUN echo "[build] Installing Node.js v23..." && START=$(date +%s) \
  && ARCH=$(dpkg --print-architecture) \
  && if [ "$ARCH" = "amd64" ]; then NODE_ARCH="x64"; else NODE_ARCH="$ARCH"; fi \
  && curl -fsSL "https://nodejs.org/dist/v23.11.0/node-v23.11.0-linux-${NODE_ARCH}.tar.gz" \
     -o /tmp/node.tar.gz \
  && tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 \
  && rm -f /tmp/node.tar.gz \
  && node --version && npm --version \
  && echo "[build] Node.js: $(($(date +%s) - START))s"

# ── Install uv ────────────────────────────────────────────────────────────
RUN pip3 install --break-system-packages uv && uv --version

# ── Clone and build Hermes Agent ─────────────────────────────────────────
RUN echo "[build] Cloning Hermes Agent..." && START=$(date +%s) \
  && git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /opt/hermes \
  && echo "[build] Clone: $(($(date +%s) - START))s"

WORKDIR /opt/hermes

# ── Python venv + dependencies ───────────────────────────────────────────
RUN echo "[build] Installing Python deps..." && START=$(date +%s) \
  && python3 -m venv .venv \
  && .venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
  && uv pip install --python .venv/bin/python --no-cache-dir -e \
     ".[messaging,cron,cli,pty,mcp,feishu,web,honcho,acp,homeassistant,sms]" \
  && echo "[build] Python deps: $(($(date +%s) - START))s"

# ── Node deps + Playwright ────────────────────────────────────────────────
RUN echo "[build] Installing Node deps + Playwright..." && START=$(date +%s) \
  && npm install --prefer-offline --no-audit \
  && npx playwright install --with-deps chromium --only-shell \
  && if [ -d /opt/hermes/scripts/whatsapp-bridge ]; then \
       cd /opt/hermes/scripts/whatsapp-bridge && npm install --prefer-offline --no-audit; \
     fi \
  && npm cache clean --force \
  && echo "[build] Node deps + Playwright: $(($(date +%s) - START))s"

# ── Clone and build hermes-web-ui ─────────────────────────────────────────
RUN echo "[build] Cloning hermes-web-ui..." && START=$(date +%s) \
  && git clone --depth 1 https://github.com/EKKOLearnAI/hermes-web-ui.git /app \
  && cd /app \
  && npm install \
  && npm run build \
  && npm prune --omit=dev \
  && npm cache clean --force \
  && echo "[build] hermes-web-ui: $(($(date +%s) - START))s"

# ── Prepare runtime dirs ─────────────────────────────────────────────────
RUN mkdir -p /opt/data/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home} \
  && mkdir -p /opt/data/hermes-web-ui

# ── Non-root user (UID 10000 required by HF Spaces) ──────────────────────
RUN useradd -u 10000 -m -d /opt/data hermes \
  && chown -R hermes:hermes /opt/data /app \
  && chmod -R g+rw /opt/data

USER hermes

# ── HermesFace scripts + assets ──────────────────────────────────────────
ARG CACHE_BUST=2026-04-26-webui-v2
RUN echo "Build: ${CACHE_BUST}"
COPY --chown=hermes:hermes scripts /opt/data/scripts
COPY --chown=hermes:hermes assets /opt/data/assets
RUN chmod +x /opt/data/scripts/entrypoint.sh \
             /opt/data/scripts/dns-resolve.py \
             /opt/data/scripts/hermes_persist.py \
             /opt/data/scripts/save_to_dataset.py \
             /opt/data/scripts/save_to_dataset_atomic.py \
             /opt/data/scripts/restore_from_dataset.py \
             /opt/data/scripts/restore_from_dataset_atomic.py

ENV HERMES_HOME=/opt/data
ENV HOME=/opt/data
ENV PATH="/opt/hermes/.venv/bin:${PATH}"
ENV NODE_ENV=production

WORKDIR /opt/data

EXPOSE 7860

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/data/scripts/entrypoint.sh"]
