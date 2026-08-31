FROM linuxserver/baseimage-selkies:debianbookworm

# Environment settings
ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/config

# Install dependencies, FreeCAD, Node.js, and terminal utilities
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

# Install Claude CLI / MCP client dependencies globally (if applicable)
RUN npm install -g @anthropic-ai/claude-code

# Clone and setup FreeCAD MCP server
RUN git clone https://github.com/liblaf/freecad-mcp.git /opt/freecad-mcp \
    && pip3 install --no-cache-dir -e /opt/freecad-mcp --break-system-packages

# Configure Openbox window layout (Left: Terminal, Right: FreeCAD)
# We drop a custom autostart script to arrange windows on container boot
RUN mkdir -p /config/.config/openbox
COPY <<-'EOF' /config/.config/openbox/autostart
# Launch Tilix terminal on the left half of the screen
tilix --geometry=960x1080+0+0 &

# Launch FreeCAD on the right half of the screen
freecad --geometry=960x1080+960+0 &
EOF

RUN chmod +x /config/.config/openbox/autostart