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

# 6. Configure Tmux to host Claude without any status bars
RUN mkdir -p /config
COPY <<-'EOF' /config/.tmux.conf
set -g mouse on
set -g status off
new-session -d 'claude'
EOF

# 7. Custom Openbox autostart script that bypasses single-app fullscreen enforcement 
# and explicitly coordinates dual-window side-by-side geometry placement.
RUN mkdir -p /config/.config/openbox
COPY <<-'EOF' /config/.config/openbox/autostart
# Kill any lingering defaults if applicable
pkill openbox-window-wrapper || true

# Launch Alacritty running Tmux on the left half (X: 0, Y: 0, Width: 50%, Height: 100%)
alacritty --class "AlacrittyCustom" -e tmux &

# Launch FreeCAD on the right half (X: 50%, Y: 0, Width: 50%, Height: 100%)
freecad &
EOF

# Override Openbox app rules to force borderless tiling layout for both apps
COPY <<-'EOF' /config/.config/openbox/rc.xml
<openbox_config>
  <applications>
    <application class="Alacritty">
      <decor>no</decor>
      <position force="yes"><x>0</x><y>0</y></position>
      <size force="yes"><width>50%</width><height>100%</height></size>
    </application>
    <application class="FreeCAD">
      <decor>no</decor>
      <position force="yes"><x>50%</x><y>0</y></position>
      <size force="yes"><width>50%</width><height>100%</height></size>
    </application>
  </applications>
</openbox_config>
EOF

RUN chmod +x /config/.config/openbox/autostart