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

# 7. Provide a custom startwm.sh script that overrides the single-app wrapper.
# This script starts Openbox, launches both applications, and forces them into a 50/50 tiled layout using wmctrl.
RUN mkdir -p /config/defaults
COPY <<-'EOF' /config/defaults/startwm.sh
#!/bin/bash
# Start Openbox window manager in the background
openbox-session &

# Wait for X server to settle
sleep 1

# Launch Alacritty running Tmux (Left side)
alacritty -e tmux &

# Launch FreeCAD (Right side)
freecad &

# Give windows time to draw, then resize and snap them side-by-side using wmctrl
sleep 2

# Get screen resolution dynamically or assume standard web streaming block
# Snap Alacritty to Left (X=0, Y=0, Width=50% of 1920 -> 960, Height=1080)
wmctrl -r "Alacritty" -e 0,0,0,960,1080
# Snap FreeCAD to Right (X=960, Y=0, Width=960, Height=1080)
wmctrl -r "FreeCAD" -e 0,960,0,960,1080

# Keep script alive to maintain container session
wait
EOF

RUN chmod +x /config/defaults/startwm.sh