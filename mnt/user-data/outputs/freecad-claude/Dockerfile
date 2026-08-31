# FreeCAD + Claude Code, streamed to the browser via Selkies.
#
# Pin the base image tag deliberately: the LinuxServer Selkies baseimages have
# no :latest and breaking changes land between distro tags. `debiantrixie` is
# the current Debian tag.
#
# Docker Hub rather than ghcr.io: ghcr's token endpoint returns "denied: denied"
# on hosts that have stale credentials cached for it, and this image needs no
# auth anywhere. Equivalent mirrors if you prefer:
#   lscr.io/linuxserver/baseimage-selkies:debiantrixie
#   ghcr.io/linuxserver/baseimage-selkies:debiantrixie
FROM lsiobase/selkies:debiantrixie

ENV DEBIAN_FRONTEND=noninteractive \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin

# ---------------------------------------------------------------------------
# 1. System packages
#    No NodeSource repo needed: the Selkies base already has one configured, so
#    `nodejs` here resolves to NodeSource 22. Do NOT also ask for `npm` —
#    NodeSource's nodejs bundles npm and Conflicts: with Debian's npm package,
#    which makes the two together unsatisfiable.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        freecad \
        freecad-python3 \
        python3-pip \
        python3-venv \
        nodejs \
        alacritty \
        tmux \
        git \
        curl \
        ca-certificates \
        wmctrl \
        xdotool \
        x11-xserver-utils \
        fonts-dejavu-core \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2. Claude Code + uv, and pre-install freecad-mcp so first launch is offline
#    and instant instead of resolving from PyPI on every `uvx` invocation.
# ---------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force \
    && pip3 install --no-cache-dir --break-system-packages uv \
    && uv tool install freecad-mcp \
    && freecad-mcp --help >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 3. Fetch the FreeCAD MCP addon. It is NOT copied into /config here: /config is
#    a runtime volume, so anything written to it at build time is invisible once
#    a volume is mounted. The init script installs it on first start instead.
# ---------------------------------------------------------------------------
RUN git config --global advice.detachedHead false \
    && git clone --depth 1 https://github.com/neka-nat/freecad-mcp.git /opt/freecad-mcp \
    && git -C /opt/freecad-mcp rev-parse HEAD > /opt/freecad-mcp/.git-rev \
    && rm -rf /opt/freecad-mcp/.git

# ---------------------------------------------------------------------------
# 4. Our files: /defaults/autostart, the s6 init hook and the helper scripts.
# ---------------------------------------------------------------------------
COPY root/ /
RUN chmod +x /defaults/autostart \
             /custom-cont-init.d/10-freecad-claude \
             /usr/local/bin/claude-session \
             /usr/local/bin/tile-windows

EXPOSE 3000 3001
VOLUME /config
