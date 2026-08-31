FROM lsiobase/selkies:debiantrixie

# Environment settings
FROM linuxserver/baseimage-selkies:debianbookworm

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/config

# 1. Install system dependencies, FreeCAD, Node.js, git, and python tools
RUN apt-get update && apt-get install -y \
    freecad \
    git \
    curl \
    tilix \
    python3-pip \
    python3-full \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Install Claude CLI and uv (required to run neka-nat/freecad-mcp)
RUN npm install -g @anthropic-ai/claude-code \
    && pip3 install --no-cache-dir uv --break-system-packages

# 3. Clone neka-nat/freecad-mcp and install its FreeCAD addon workbench
RUN git config --global advice.detachedHead false \
    && git clone --depth 1 https://github.com/neka-nat/freecad-mcp.git /opt/neka-nat-freecad-mcp \
    && mkdir -p /config/.FreeCAD/Mod \
    && cp -r /opt/neka-nat-freecad-mcp/addon/FreeCADMCP /config/.FreeCAD/Mod/

# 4. Configure Claude MCP settings to hook into the freecad-mcp server
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

# 5. Configure Openbox window layout: Claude Terminal on the Left, FreeCAD on the Right
RUN mkdir -p /config/.config/openbox
COPY <<-'EOF' /config/.config/openbox/autostart
# Launch Tilix terminal on the left half automatically running claude
tilix --geometry=960x1080+0+0 -e "claude" &

# Launch FreeCAD on the right half
freecad --geometry=960x1080+960+0 &
EOF

RUN chmod +x /config/.config/openbox/autostart