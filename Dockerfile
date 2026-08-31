# syntax=docker/dockerfile:1.7

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
# 4. Our files, inlined. Heredocs need the dockerfile:1.7 frontend declared on
#    line 1 above — without it the older builtin frontend treats `<<'EOF'` as a
#    literal filename. Keeping them here rather than in a `root/` tree means the
#    repo is two files and there is no build context to forget to commit.
# ---------------------------------------------------------------------------
RUN mkdir -p /defaults/skel/.config/alacritty /custom-cont-init.d /usr/local/bin

COPY <<'DOCKERFILE_EOF' /defaults/autostart
#!/bin/bash
# Runs inside the Openbox session started by the Selkies baseimage.
# We do NOT override startwm.sh — the base already gives us Openbox, and
# replacing it means re-implementing session handling for no benefit.

xset s off
xset -dpms

freecad &
alacritty -e /usr/local/bin/claude-session &

# Keeps the split correct, including when you resize the browser window.
/usr/local/bin/tile-windows &

wait
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.tmux.conf
set -g mouse on
set -g status off
set -g default-terminal "tmux-256color"
set -g history-limit 50000
set -sg escape-time 10
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.config/alacritty/alacritty.toml
[window]
decorations = "None"
padding = { x = 8, y = 8 }

[font]
size = 11.0

[font.normal]
family = "DejaVu Sans Mono"

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[scrolling]
history = 50000
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /opt/freecad-userdir.py
# Ask FreeCAD itself where its user data directory is. The addon path moved
# between FreeCAD 0.19 (~/.FreeCAD), 1.0 (~/.local/share/FreeCAD) and 1.1
# (~/.local/share/FreeCAD/v1-1), so hardcoding one is a guess that silently
# leaves the addon undiscovered.
import sys

import FreeCAD  # noqa: E402

sys.__stdout__.write("FCUSERDIR=" + FreeCAD.getUserAppDataDir() + "\n")
sys.__stdout__.flush()
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /custom-cont-init.d/10-freecad-claude
#!/usr/bin/with-contenv bash
# Runs as root on every container start, before the desktop services.
# Everything that has to land in /config belongs here rather than in the
# Dockerfile: /config is a volume, so build-time writes there are shadowed.

as_abc() { s6-setuidgid abc env HOME=/config PATH="$PATH" "$@"; }

# --- 1. seed user config, never clobbering edits the user has made ----------
mkdir -p /config/workspace /config/.config/alacritty
[ -f /config/.tmux.conf ] || cp /defaults/skel/.tmux.conf /config/.tmux.conf
[ -f /config/.config/alacritty/alacritty.toml ] \
    || cp /defaults/skel/.config/alacritty/alacritty.toml /config/.config/alacritty/alacritty.toml

# --- 2. install the FreeCAD MCP addon into the right Mod directory ----------
FC_BIN=""
for c in freecadcmd FreeCADCmd; do
    command -v "$c" >/dev/null 2>&1 && { FC_BIN="$c"; break; }
done

FC_USER_DIR=""
if [ -n "$FC_BIN" ]; then
    FC_USER_DIR=$(as_abc "$FC_BIN" /opt/freecad-userdir.py 2>/dev/null \
                  | sed -n 's/^FCUSERDIR=//p' | tail -n1)
fi
[ -n "$FC_USER_DIR" ] || FC_USER_DIR="/config/.local/share/FreeCAD"

MOD_DIR="${FC_USER_DIR%/}/Mod"
mkdir -p "$MOD_DIR"

if ! cmp -s /opt/freecad-mcp/.git-rev "$MOD_DIR/FreeCADMCP/.installed-rev"; then
    echo "[freecad-claude] installing FreeCADMCP addon into $MOD_DIR"
    rm -rf "$MOD_DIR/FreeCADMCP"
    cp -r /opt/freecad-mcp/addon/FreeCADMCP "$MOD_DIR/FreeCADMCP"
    cp /opt/freecad-mcp/.git-rev "$MOD_DIR/FreeCADMCP/.installed-rev"
fi

# --- 3. register the MCP server with Claude Code (user scope) ---------------
# User scope lives in ~/.claude.json and needs no per-project approval prompt,
# unlike a committed .mcp.json. `freecad-mcp` is already on PATH from the
# build, so there is no uvx resolve on every start.
if ! as_abc claude mcp get freecad >/dev/null 2>&1; then
    echo "[freecad-claude] registering freecad MCP server"
    as_abc claude mcp add --scope user freecad -- freecad-mcp || true
fi

# --- 4. ownership ----------------------------------------------------------
lsiown -R abc:abc /config/workspace /config/.config "${FC_USER_DIR%/}" 2>/dev/null || true
lsiown abc:abc /config/.tmux.conf 2>/dev/null || true
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /usr/local/bin/claude-session
#!/bin/bash
# Claude Code inside tmux. `new-session -A` attaches to an existing session
# instead of erroring, so closing the terminal never loses your context.
# Falling back to a shell means a failed launch shows you the error rather
# than silently killing the window.
cd "${CLAUDE_WORKDIR:-/config/workspace}" || cd /config
exec tmux new-session -A -s claude "claude; echo; echo '[claude exited — press enter for a shell]'; read -r; exec bash"
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /usr/local/bin/tile-windows
#!/bin/bash
# Splits the screen between the terminal and FreeCAD.
#
# The original version hardcoded 1920x1080 and slept for a fixed 2s. Selkies
# resizes the X display to whatever the browser viewport is and can resize it
# again at any moment, so both assumptions break. This reads the real geometry
# and re-tiles whenever it changes.

SPLIT=${SPLIT_PERCENT:-38}          # width of the terminal pane, in percent
TERM_CLASS=${TERM_CLASS:-Alacritty}
CAD_CLASS=${CAD_CLASS:-FreeCAD}

win_id() { xdotool search --class "^$1$" 2>/dev/null | tail -n1; }

# Wait for both windows instead of guessing at a sleep duration.
for _ in $(seq 1 120); do
    [ -n "$(win_id "$TERM_CLASS")" ] && [ -n "$(win_id "$CAD_CLASS")" ] && break
    sleep 0.5
done

tile() {
    local sw=$1 sh=$2
    local left=$(( sw * SPLIT / 100 ))
    local right=$(( sw - left ))
    local t c
    t=$(win_id "$TERM_CLASS")
    c=$(win_id "$CAD_CLASS")

    for w in $t $c; do
        wmctrl -i -r "$w" -b remove,maximized_horz,maximized_vert
    done

    [ -n "$t" ] && wmctrl -i -r "$t" -e "0,0,0,$left,$sh"
    [ -n "$c" ] && wmctrl -i -r "$c" -e "0,$left,0,$right,$sh"
}

last=""
while true; do
    geo=$(xdotool getdisplaygeometry 2>/dev/null)
    if [ -n "$geo" ] && [ "$geo" != "$last" ]; then
        last="$geo"
        sleep 0.4                      # let the WM settle after a resize
        tile "${geo%% *}" "${geo##* }"
    fi
    sleep 2
done
DOCKERFILE_EOF

RUN chmod +x /defaults/autostart \
             /custom-cont-init.d/10-freecad-claude \
             /usr/local/bin/claude-session \
             /usr/local/bin/tile-windows

EXPOSE 3000 3001
VOLUME /config
