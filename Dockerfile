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

# 7. Configure Openbox to remove window decorations globally and force a tiling layout.
# This replaces the default Openbox config that Selkies provides.
RUN mkdir -p /config/.config/openbox

# This rc.xml instructs Openbox to remove borders/buttons for Alacritty and FreeCAD,
# and force them to specific screen positions and sizes (50% width each).
COPY <<-'EOF' /config/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <underMouse>no</underMouse>
    <desktopMouse>no</desktopMouse>
    <jumpToDesk>yes</jumpToDesk>
    <failOnNewWindow>no</failOnNewWindow>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Active</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>no</keepBorder>
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow">
      <name>Sans</name>
      <size>8</size>
      <weight>bold</weight>
      <slant>normal</slant>
    </font>
    <font place="InactiveWindow">
      <name>Sans</name>
      <size>8</size>
      <weight>normal</weight>
      <slant>normal</slant>
    </font>
    <font place="MenuHeader">
      <name>Sans</name>
      <size>9</size>
      <weight>bold</weight>
      <slant>normal</slant>
    </font>
    <font place="MenuItem">
      <name>Sans</name>
      <size>9</size>
      <weight>normal</weight>
      <slant>normal</slant>
    </font>
    <font place="OnScreenDisplay">
      <name>Sans</name>
      <size>9</size>
      <weight>bold</weight>
      <slant>normal</slant>
    </font>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <desktop>desktop1</desktop>
    </names>
    <popupTime>0</popupTime>
  </desktops>
  <resize>
    <drawContents>yes</drawContents>
    <popup>Always</popup>
    <unit>Pixel</unit>
  </resize>
  <margins>
    <top>0</top>
    <bottom>0</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
  <dock>
    <position>TopLeft</position>
    <floatingX>0</floatingX>
    <floatingY>0</floatingY>
    <noStrut>no</noStrut>
    <stacking>Above</stacking>
    <direction>Vertical</direction>
    <autoHide>no</autoHide>
    <moveButton>Middle</moveButton>
    <cornerRadius>0</cornerRadius>
    <screenEdgeWarp>no</screenEdgeWarp>
  </dock>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
  </keyboard>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarp>no</screenEdgeWarp>
  </mouse>
  <menu>
    <hideOnDelay>500</hideOnDelay>
    <middle>no</middle>
    <submenuShowDelay>100</submenuShowDelay>
    <applicationIcons>yes</applicationIcons>
    <manageDesktops>yes</manageDesktops>
  </menu>
  <applications>
    <!-- TILE ALACRITTY ON THE LEFT AND REMOVE BORDERS -->
    <application class="Alacritty">
      <decor>no</decor>
      <position force="yes">
        <x>0</x>
        <y>0</y>
        <monitor>primary</monitor>
      </position>
      <size force="yes">
        <width>50%</width>
        <height>100%</height>
      </size>
    </application>
    <!-- TILE FREECAD ON THE RIGHT AND REMOVE BORDERS -->
    <application class="FreeCAD">
      <decor>no</decor>
      <position force="yes">
        <x>-0</x>
        <y>0</y>
        <monitor>primary</monitor>
        <head>primary</head>
      </position>
      <size force="yes">
        <width>50%</width>
        <height>100%</height>
      </size>
    </application>
  </applications>
</openbox_config>
EOF

# This autostart script launches the two applications, Openbox will handle positioning based on rc.xml
COPY <<-'EOF' /config/.config/openbox/autostart
# Kill any Openbox wrappers the image might attempt to start
pkill openbox-window-wrapper || true

# Launch Alacritty running Tmux (Claude)
alacritty -e tmux &

# Launch FreeCAD
freecad &
EOF

RUN chmod +x /config/.config/openbox/autostart