FROM lsiobase/selkies:debiantrixie

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/config

# 1. Install system dependencies, FreeCAD, Alacritty, Tmux, window utilities, git, and python tools
RUN apt-get update && apt-get install -y \
    freecad \
    git \
    curl \
    alacritty \
    tmux \
    wmctrl \
    xdotool \
    python3-pip \
    python3-full \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Install Claude CLI and uv (required for neka-nat/freecad-mcp)
RUN npm install -g @anthropic-ai/claude-code \
    && pip3 install --no-cache-dir uv --break-system-packages

# 3. Clone neka-nat/freecad-mcp and install its FreeCAD addon workbench
RUN git config --global advice.detachedHead false \
    && git clone --depth 1 https://github.com/neka-nat/freecad-mcp.git /opt/neka-nat-freecad-mcp \
    && mkdir -p /config/.FreeCAD/Mod \
    && cp -r /opt/neka-nat-freecad-mcp/addon/FreeCADMCP /config/.FreeCAD/Mod/

# 4. Configure Claude MCP settings
RUN mkdir -p /config/.claude
COPY <<-'EOF' /config/.claude/config.json
{
  "mcpServers": {
    "freecad": {
      "command": "uvx",
      "args": [
        "freecad-mcp"
      ]
    }
  }
}
EOF

# 5. Configure Alacritty with zero window borders and sleek dark look
RUN mkdir -p /config/.config/alacritty
COPY <<-'EOF' /config/.config/alacritty/alacritty.toml
[window]
decorations = "None"
opacity = 0.98

[font]
size = 11.0
[font.normal]
family = "monospace"

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"
EOF

# 6. Configure Tmux to host Claude without status bars
RUN mkdir -p /config
COPY <<-'EOF' /config/.tmux.conf
set -g mouse on
set -g status off
new-session -d 'claude'
EOF

# 7. Override the image's single-app entrypoint completely by providing a custom startwm.sh 
# This forces Openbox to run as a clean desktop session, spawning both applications side-by-side borderless.
RUN mkdir -p /config/defaults
COPY <<-'EOF' /config/defaults/startwm.sh
#!/bin/bash

# Disable screen blanking / power saving
xset s off
xset -dpms

# Start Openbox window manager
openbox-session &

# Wait for X display to initialize
sleep 1

# Launch Alacritty running Tmux (Claude)
alacritty -e tmux &

# Launch FreeCAD
freecad &

# Give windows a moment to spawn, then use wmctrl to strip any remaining decorations and snap side-by-side
sleep 2
wmctrl -r "Alacritty" -b remove,maximized_horz,maximized_vert
wmctrl -r "FreeCAD" -b remove,maximized_horz,maximized_vert

# Resize to exact split dimensions (assuming default 1920x1080 stream resolution)
wmctrl -r "Alacritty" -e 0,0,0,960,1080
wmctrl -r "FreeCAD" -e 0,960,0,960,1080

# Keep the session alive
wait
EOF

RUN chmod +x /config/defaults/startwm.sh