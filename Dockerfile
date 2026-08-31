# syntax=docker/dockerfile:1.7
#
# ============================================================================
#  selkies-claude — a GUI application, Claude Code and an MCP bridge between
#  them, in one browser-accessible desktop session.
#
#  Retargeting to another app is the APP DEFINITION block below plus the two
#  hook scripts (/opt/app/build.sh at build time, /opt/app/init.sh at start).
#  Nothing else in this file is FreeCAD-specific.
#
#  Line 1 must stay line 1: the dockerfile:1.7 frontend is what makes the
#  inline `COPY <<'EOF'` heredocs work.
# ============================================================================
FROM lsiobase/selkies:debiantrixie

# ----------------------------------------------------------------------------
#  APP DEFINITION — the part you edit
# ----------------------------------------------------------------------------
ARG APP_NAME="FreeCAD"
ARG APP_PACKAGES="freecad freecad-python3"
ARG APP_EXEC="freecad"
# WM_CLASS drives window placement. Find it for a new app with:
#   xprop WM_CLASS      (then click the window)
ARG APP_WM_CLASS="FreeCAD"
ARG APP_ICON="freecad"
# Leave APP_MCP_NAME empty to ship the desktop without an MCP bridge.
ARG APP_MCP_NAME="freecad"
ARG APP_MCP_COMMAND="freecad-mcp"
ARG SPLIT_PERCENT="38"

ENV APP_NAME="${APP_NAME}" \
    APP_EXEC="${APP_EXEC}" \
    APP_WM_CLASS="${APP_WM_CLASS}" \
    APP_MCP_NAME="${APP_MCP_NAME}" \
    APP_MCP_COMMAND="${APP_MCP_COMMAND}" \
    SPLIT_PERCENT="${SPLIT_PERCENT}" \
    TERM_WM_CLASS="Alacritty" \
    WORKSPACE_DIR="/config/workspace" \
    DESKTOP_BG="#11111b" \
    APP_DESKTOP_FILE="" \
    DEBIAN_FRONTEND=noninteractive \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin

LABEL org.opencontainers.image.title="selkies-claude: ${APP_NAME}"

# ----------------------------------------------------------------------------
#  1. Packages
#     No NodeSource repo needed — the Selkies base already has one, so `nodejs`
#     resolves to NodeSource 22. Do NOT also request `npm`: NodeSource's nodejs
#     bundles npm and Conflicts: with Debian's separate npm package.
#     x11-utils supplies xprop, which the tiler needs to read _NET_WORKAREA.
#     The cosmetic extras are installed one at a time so that a rename in some
#     future Debian release degrades the theme instead of failing the build.
# ----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ${APP_PACKAGES} \
        alacritty \
        tmux \
        git \
        curl \
        ca-certificates \
        nodejs \
        python3-pip \
        python3-venv \
        wmctrl \
        xdotool \
        x11-utils \
        x11-xserver-utils \
        fonts-dejavu-core \
 && for p in tint2 xbindkeys fonts-jetbrains-mono adwaita-icon-theme \
             gnome-themes-extra qt5-gtk-platformtheme qt6-gtk-platformtheme; do \
        apt-get install -y --no-install-recommends "$p" \
            || echo "[build] optional package unavailable: $p"; \
    done \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------------------------------
#  2. Claude Code and uv
# ----------------------------------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code \
 && npm cache clean --force \
 && pip3 install --no-cache-dir --break-system-packages uv

# ----------------------------------------------------------------------------
#  3. Panel launcher for the app
# ----------------------------------------------------------------------------
RUN printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        "Name=${APP_NAME}" \
        "Exec=${APP_EXEC}" \
        "Icon=${APP_ICON}" \
        'Terminal=false' \
        > /usr/share/applications/selkies-app.desktop

# ----------------------------------------------------------------------------
#  4. Session files, inlined.
#     Keeping them here rather than in a `root/` tree means the repository is
#     two files with no build context to lose.
# ----------------------------------------------------------------------------
RUN mkdir -p /etc/fonts /defaults/skel/.config/alacritty \
             /defaults/skel/.config/tint2 /defaults/skel/.config/gtk-3.0 \
             /defaults/skel/.config/gtk-4.0 /custom-cont-init.d \
             /usr/local/bin /usr/share/applications /opt/app

COPY <<'DOCKERFILE_EOF' /etc/fonts/local.conf
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrains Mono</family>
      <family>DejaVu Sans Mono</family>
    </prefer>
  </alias>
</fontconfig>
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/autostart
#!/bin/bash
# Openbox session contents. The Selkies baseimage starts Openbox and execs this;
# we deliberately do not replace startwm.sh, which would mean reimplementing
# session handling for no gain.
set -u

WORKSPACE="${WORKSPACE_DIR:-/config/workspace}"
export XDG_CONFIG_HOME=/config/.config
export XDG_DATA_HOME=/config/.local/share
# GTK apps and GTK-backed Qt dialogs. Qt widget styling is left to the app
# layer: forcing QT_STYLE_OVERRIDE globally fights apps that ship their own
# stylesheet (FreeCAD, KiCad, Blender all do).
export GTK_THEME="${GTK_THEME:-Adwaita:dark}"

xset s off
xset -dpms
xsetroot -solid "${DESKTOP_BG:-#11111b}"

mkdir -p "$WORKSPACE"
cd "$WORKSPACE" 2>/dev/null || cd /config

# Panel and keybindings are optional: a missing package degrades the session
# rather than killing it.
command -v tint2     >/dev/null 2>&1 && tint2 &
command -v xbindkeys >/dev/null 2>&1 && xbindkeys &

alacritty -e /usr/local/bin/claude-session &

if [ -n "${APP_EXEC:-}" ]; then
    # Launched from the workspace so the app's open/save dialogs default to the
    # same directory Claude is working in.
    $APP_EXEC &
fi

/usr/local/bin/tile-windows &

wait
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.tmux.conf
set -g mouse on
set -g status off
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
set -g history-limit 50000
set -sg escape-time 10
set -g focus-events on
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.xbindkeysrc
# Session keybindings. Handled by xbindkeys rather than Openbox's rc.xml,
# because the baseimage manages that file (NO_DECOR, Ctrl+Shift+d) and
# overwriting it would break those.

"alacritty"
  Mod4 + Return

"retile"
  Mod4 + t

"wmctrl -r :ACTIVE: -b toggle,maximized_vert,maximized_horz"
  Mod4 + f

"wmctrl -c :ACTIVE:"
  Mod4 + q
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.gtkrc-2.0
gtk-theme-name="Adwaita-dark"
gtk-icon-theme-name="Adwaita"
gtk-font-name="Sans 10"
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.config/alacritty/alacritty.toml
# Catppuccin Mocha — the single source of truth for this session's palette.
# The panel, the desktop root and the app's stylesheet are all matched to it.

[window]
decorations = "None"
padding = { x = 10, y = 8 }
dynamic_padding = true

[font]
size = 11.0
# "monospace" rather than a literal family: /etc/fonts/local.conf points it at
# JetBrains Mono, and fontconfig falls back on its own if that font is missing.
[font.normal]
family = "monospace"
style = "Regular"
[font.bold]
family = "monospace"
style = "Bold"

[scrolling]
history = 50000

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"
dim_foreground = "#a6adc8"
bright_foreground = "#cdd6f4"

[colors.cursor]
text = "#1e1e2e"
cursor = "#f5e0dc"

[colors.selection]
text = "#1e1e2e"
background = "#f5e0dc"

[colors.normal]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#bac2de"

[colors.bright]
black = "#585b70"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#a6adc8"
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.config/tint2/tint2rc
# Panel for the Selkies desktop session. Colours match the terminal palette.
# strut_policy = follow_size publishes _NET_WORKAREA, which tile-windows reads,
# so the panel and the tiling stay consistent without hardcoded offsets.

# background 1 — panel
rounded = 0
border_width = 0
background_color = #11111b 100
border_color = #11111b 100

# background 2 — inactive task
rounded = 4
border_width = 0
background_color = #313244 100
border_color = #313244 100

# background 3 — active task
rounded = 4
border_width = 0
background_color = #89b4fa 100
border_color = #89b4fa 100

panel_monitor = all
panel_position = bottom center horizontal
panel_size = 100% 34
panel_margin = 0 0
panel_padding = 6 4 8
panel_background_id = 1
panel_layer = top
panel_dock = 0
wm_menu = 1
strut_policy = follow_size

launcher_padding = 2 0 8
launcher_background_id = 0
launcher_icon_size = 22
launcher_tooltip = 1
launcher_item_app = /usr/share/applications/claude-terminal.desktop
launcher_item_app = /usr/share/applications/selkies-app.desktop

taskbar_mode = single_desktop
taskbar_padding = 2 0 6
taskbar_background_id = 0
task_text = 1
task_icon = 1
task_maximum_size = 240 26
task_padding = 8 3 6
task_background_id = 2
task_active_background_id = 3
task_font = sans 9
task_font_color = #cdd6f4 100
task_active_font_color = #11111b 100

systray_padding = 4 0 6
systray_background_id = 0
systray_icon_size = 20

time1_format = %H:%M
time1_font = sans 9
clock_font_color = #cdd6f4 100
clock_padding = 10 0
clock_background_id = 0

tooltip_padding = 6 4
tooltip_background_id = 2
tooltip_font_color = #cdd6f4 100
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.config/gtk-3.0/settings.ini
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
gtk-font-name=Sans 10
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /defaults/skel/.config/gtk-4.0/settings.ini
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
gtk-font-name=Sans 10
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /usr/share/applications/claude-terminal.desktop
[Desktop Entry]
Type=Application
Name=Claude Code
Comment=Claude Code in a tmux session
Exec=alacritty -e /usr/local/bin/claude-session
Icon=utilities-terminal
Terminal=false
Categories=Development;
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /usr/local/bin/claude-session
#!/bin/bash
# Claude Code inside tmux. `new-session -A` attaches to an existing session
# rather than erroring, so closing the terminal never loses context. Dropping to
# a shell on exit means a failed launch shows you the error instead of the
# window vanishing.
cd "${WORKSPACE_DIR:-/config/workspace}" 2>/dev/null || cd /config
exec tmux new-session -A -s claude \
    "claude; echo; echo '[claude exited — enter for a shell, or run: claude]'; read -r; exec bash"
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /usr/local/bin/tile-windows
#!/bin/bash
# Side-by-side layout for the terminal and the app window.
#
# Reads _NET_WORKAREA rather than the raw display size, so the panel's strut is
# respected automatically and windows are never placed underneath it. Selkies
# resizes the X display to the browser viewport at any time, so this watches for
# changes instead of assuming a fixed resolution.
#
#   tile-windows          run as a daemon, re-tiling on geometry change
#   tile-windows --once   tile immediately and exit  (aliased to `retile`)

SPLIT=${SPLIT_PERCENT:-38}
TERM_CLASS=${TERM_WM_CLASS:-Alacritty}
CAD_CLASS=${APP_WM_CLASS:-}

win_id() {
    [ -n "$1" ] || return 1
    xdotool search --onlyvisible --class "^$1$" 2>/dev/null | tail -n1
}

workarea() {
    # _NET_WORKAREA(CARDINAL) = 0, 0, 1920, 1046, ...   (x, y, w, h per desktop)
    local raw
    raw=$(xprop -root _NET_WORKAREA 2>/dev/null | sed 's/.*= *//')
    if [ -n "$raw" ]; then
        echo "$raw" | awk -F'[,[:space:]]+' '{print $1, $2, $3, $4}'
        return
    fi
    local geo
    geo=$(xdotool getdisplaygeometry 2>/dev/null) || return 1
    echo "0 0 ${geo%% *} ${geo##* }"
}

tile() {
    local x=$1 y=$2 w=$3 h=$4
    local left=$(( w * SPLIT / 100 ))
    local right=$(( w - left ))
    local t c
    t=$(win_id "$TERM_CLASS")
    c=$(win_id "$CAD_CLASS")

    for win in $t $c; do
        wmctrl -i -r "$win" -b remove,maximized_horz,maximized_vert
    done

    if [ -n "$t" ] && [ -n "$c" ]; then
        wmctrl -i -r "$t" -e "0,$x,$y,$left,$h"
        wmctrl -i -r "$c" -e "0,$((x + left)),$y,$right,$h"
    elif [ -n "$t" ]; then
        wmctrl -i -r "$t" -e "0,$x,$y,$w,$h"
    elif [ -n "$c" ]; then
        wmctrl -i -r "$c" -e "0,$x,$y,$w,$h"
    fi
}

if [ "${1:-}" = "--once" ]; then
    # shellcheck disable=SC2046
    tile $(workarea)
    exit 0
fi

# Wait for the windows to appear rather than guessing at a sleep duration.
for _ in $(seq 1 120); do
    [ -n "$(win_id "$TERM_CLASS")" ] && [ -n "$(win_id "$CAD_CLASS")" ] && break
    sleep 0.5
done

last=""
while true; do
    now=$(workarea)
    if [ -n "$now" ] && [ "$now" != "$last" ]; then
        last="$now"
        sleep 0.4          # let the WM settle after a resize
        # shellcheck disable=SC2086
        tile $now
    fi
    sleep 2
done
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /usr/local/bin/retile
#!/bin/sh
exec /usr/local/bin/tile-windows --once
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /custom-cont-init.d/10-selkies-session
#!/usr/bin/with-contenv bash
# Runs as root on every start, before the desktop services.
#
# Everything destined for /config belongs here, not in the Dockerfile: /config
# is the runtime volume, so build-time writes there are shadowed the moment a
# volume is mounted.

WORKSPACE="${WORKSPACE_DIR:-/config/workspace}"
as_abc() { s6-setuidgid abc env HOME=/config PATH="$PATH" "$@"; }

# --- 1. seed user config, never clobbering the user's own edits -------------
if [ -d /defaults/skel ]; then
    find /defaults/skel -type f | while read -r src; do
        dst="/config/${src#/defaults/skel/}"
        if [ ! -e "$dst" ]; then
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
        fi
    done
fi

mkdir -p "$WORKSPACE"

# --- 2. panel launcher for whichever app this image was built around --------
# tint2rc references a fixed path so the panel config stays app-agnostic.
if [ -n "${APP_DESKTOP_FILE:-}" ] && [ -f "$APP_DESKTOP_FILE" ]; then
    ln -sf "$APP_DESKTOP_FILE" /usr/share/applications/selkies-app.desktop
fi

# --- 3. app-specific setup --------------------------------------------------
if [ -x /opt/app/init.sh ]; then
    echo "[session] running app init hook"
    /opt/app/init.sh || echo "[session] app init hook failed (continuing)"
fi

# --- 4. register the MCP server with Claude Code ----------------------------
# User scope lives in ~/.claude.json and needs no per-project approval prompt,
# unlike a committed .mcp.json.
if [ -n "${APP_MCP_NAME:-}" ] && [ -n "${APP_MCP_COMMAND:-}" ]; then
    if ! as_abc claude mcp get "$APP_MCP_NAME" >/dev/null 2>&1; then
        echo "[session] registering MCP server: $APP_MCP_NAME"
        # shellcheck disable=SC2086
        as_abc claude mcp add --scope user "$APP_MCP_NAME" -- $APP_MCP_COMMAND \
            || echo "[session] MCP registration failed (continuing)"
    fi
fi

# --- 5. ownership -----------------------------------------------------------
lsiown -R abc:abc /config/.config /config/.local "$WORKSPACE" 2>/dev/null || true
lsiown abc:abc /config/.tmux.conf /config/.gtkrc-2.0 /config/.xbindkeysrc 2>/dev/null || true
DOCKERFILE_EOF

# ----------------------------------------------------------------------------
#  5. App layer hooks
# ----------------------------------------------------------------------------

COPY <<'DOCKERFILE_EOF' /opt/app/build.sh
#!/bin/bash
# Build-time hook for the FreeCAD layer. Anything app-specific that is not an
# apt package (APP_PACKAGES covers those) goes here.
set -eux

# The MCP bridge, pre-installed so first launch needs no PyPI round trip.
uv tool install freecad-mcp

# The FreeCAD-side half of the bridge. Not copied into /config here — that is a
# runtime volume; the init hook installs it into the real Mod directory.
git config --global advice.detachedHead false
git clone --depth 1 https://github.com/neka-nat/freecad-mcp.git /opt/app/freecad-mcp
git -C /opt/app/freecad-mcp rev-parse HEAD > /opt/app/freecad-mcp/.git-rev
rm -rf /opt/app/freecad-mcp/.git
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /opt/app/init.sh
#!/bin/bash
# Runtime hook for the FreeCAD layer: install the MCP workbench into the correct
# Mod directory and match FreeCAD's UI to the session palette.
set -u
as_abc() { s6-setuidgid abc env HOME=/config PATH="$PATH" "$@"; }

FC_BIN=""
for c in freecadcmd FreeCADCmd; do
    command -v "$c" >/dev/null 2>&1 && { FC_BIN="$c"; break; }
done

# Ask FreeCAD where its user directory is rather than hardcoding a path: it moved
# between 0.19 (~/.FreeCAD), 1.0 (~/.local/share/FreeCAD) and 1.1 (.../v1-1).
# The same run applies the theme, so this costs one headless start, not two.
FC_USER_DIR=""
if [ -n "$FC_BIN" ]; then
    FC_USER_DIR=$(as_abc "$FC_BIN" /opt/app/freecad-setup.py 2>/dev/null \
                  | sed -n 's/^FCUSERDIR=//p' | tail -n1)
fi
[ -n "$FC_USER_DIR" ] || FC_USER_DIR="/config/.local/share/FreeCAD"

MOD_DIR="${FC_USER_DIR%/}/Mod"
mkdir -p "$MOD_DIR"

if ! cmp -s /opt/app/freecad-mcp/.git-rev "$MOD_DIR/FreeCADMCP/.installed-rev"; then
    echo "[freecad] installing FreeCADMCP addon into $MOD_DIR"
    rm -rf "$MOD_DIR/FreeCADMCP"
    cp -r /opt/app/freecad-mcp/addon/FreeCADMCP "$MOD_DIR/FreeCADMCP"
    cp /opt/app/freecad-mcp/.git-rev "$MOD_DIR/FreeCADMCP/.installed-rev"
fi

lsiown -R abc:abc "${FC_USER_DIR%/}" 2>/dev/null || true
DOCKERFILE_EOF

COPY <<'DOCKERFILE_EOF' /opt/app/freecad-setup.py
"""Headless FreeCAD pass: report the user directory and apply the dark theme.

Run by the init hook via `freecadcmd`. Every write is guarded, so a user who
picks a different stylesheet in the GUI keeps it across restarts.
"""

import os
import sys

import FreeCAD  # noqa: E402

user_dir = FreeCAD.getUserAppDataDir()
sys.__stdout__.write("FCUSERDIR=" + user_dir + "\n")
sys.__stdout__.flush()


def rgba(hex_color):
    """#rrggbb -> the unsigned int FreeCAD stores colours as (0xRRGGBBAA)."""
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return (r << 24) | (g << 16) | (b << 8) | 0xFF


# --- window stylesheet -----------------------------------------------------
# Pick from what this FreeCAD build actually ships instead of naming a file that
# may have been renamed between releases.
main = FreeCAD.ParamGet("User parameter:BaseApp/Preferences/MainWindow")
if not main.GetString("StyleSheet", ""):
    sheets = []
    for root, _dirs, files in os.walk(
        os.path.join(FreeCAD.getResourceDir(), "Gui", "Stylesheets")
    ):
        sheets += [f for f in files if f.endswith(".qss")]

    preferred = ["FreeCAD Dark.qss", "OpenDark.qss", "Behave-dark.qss", "Dark.qss"]
    chosen = next((p for p in preferred if p in sheets), None)
    if chosen is None:
        chosen = next((s for s in sorted(sheets) if "dark" in s.lower()), None)
    if chosen:
        main.SetString("StyleSheet", chosen)
        sys.__stdout__.write("FCSTYLESHEET=" + chosen + "\n")

# --- 3D viewport background ------------------------------------------------
# Own marker rather than checking the colours: leaves a user's later choice
# alone. If the param names shift in a future release this becomes a harmless
# no-op — set the background from Preferences > Display if so.
view = FreeCAD.ParamGet("User parameter:BaseApp/Preferences/View")
if not view.GetBool("SelkiesThemeApplied", False):
    view.SetUnsigned("BackgroundColor", rgba("#181825"))
    view.SetUnsigned("BackgroundColor2", rgba("#11111b"))
    view.SetUnsigned("BackgroundColor3", rgba("#1e1e2e"))
    view.SetBool("Simple", False)
    view.SetBool("Gradient", True)
    view.SetBool("UseBackgroundColorMid", False)
    view.SetBool("SelkiesThemeApplied", True)

FreeCAD.saveParameter()
DOCKERFILE_EOF

RUN chmod +x /defaults/autostart \
             /custom-cont-init.d/10-selkies-session \
             /usr/local/bin/claude-session \
             /usr/local/bin/tile-windows \
             /usr/local/bin/retile \
             /opt/app/build.sh \
             /opt/app/init.sh \
 && /opt/app/build.sh

EXPOSE 3000 3001
VOLUME /config
