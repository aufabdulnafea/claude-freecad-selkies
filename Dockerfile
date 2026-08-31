FROM lsiobase/selkies:debiantrixie
ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/config

# 1. Install system dependencies, FreeCAD, Alacritty, Tmux, git, and python tools
RUN apt-get update && apt-get install -y \
    freecad \
    git \
    curl \
    alacritty \
    tmux \
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

# 5. Configure Alacritty for a minimal, beautiful dark aesthetic
RUN mkdir -p /config/.config/alacritty
COPY <<-'EOF' /config/.config/alacritty/alacritty.toml
[window]
decorations = "None"
opacity = 0.95

[font]
size = 11.0
[font.normal]
family = "monospace"

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"
EOF

# 6. Configure Tmux to split horizontally: Left pane runs Claude, Right pane can run tools or logs
RUN mkdir -p /config
COPY <<-'EOF' /config/.tmux.conf
set -g mouse on
set -g status off
# Start a session with Claude on the left
new-session -d 'claude'
EOF

# 7. Configure Openbox to remove window decorations and tile Alacritty + FreeCAD borderlessly
RUN mkdir -p /config/.config/openbox
COPY <<-'EOF' /config/.config/openbox/rc.xml
<openbox_config>
  <applications>
    <application class="Alacritty">
      <decor>no</decor>
    </application>
    <application class="FreeCAD">
      <decor>no</decor>
    </application>
  </applications>
</openbox_config>
EOF

COPY <<-'EOF' /config/.config/openbox/autostart
# Launch Alacritty running Tmux (occupying left side or full screen split)
alacritty --geometry 120x50 -e tmux &

# Launch FreeCAD borderless on the right
freecad &
EOF

RUN chmod +x /config/.config/openbox/autostart