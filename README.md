# FreeCAD + Claude Code in the browser

Openbox session streamed by the LinuxServer Selkies baseimage: Claude Code in a
tmux/Alacritty pane on the left, FreeCAD on the right, wired together by the
`neka-nat/freecad-mcp` XML-RPC bridge on `localhost:9875`.

## Run

```bash
cp .env.example .env      # optional: set ANTHROPIC_API_KEY and a web password
docker compose up -d --build
```

Open <http://localhost:3000>.

## First-run checklist

1. **FreeCAD:** workbench dropdown → **MCP Addon** → **FreeCAD MCP** menu →
   tick **Auto-Start Server**. This is a one-time step; the setting is written
   to `freecad_mcp_settings.json` inside the addon directory, which lives on
   the `./config` volume, so it survives restarts. Until it is ticked, the RPC
   server must be started by hand on every FreeCAD launch and Claude's tool
   calls will fail with a connection error.
2. **Claude:** if you did not set `ANTHROPIC_API_KEY`, run `/login` in the
   terminal pane once. The credentials persist in `./config`.
3. Verify with `/mcp` in Claude Code — `freecad` should be connected.

## Layout

| Path | Purpose |
| --- | --- |
| `root/defaults/autostart` | Launch command for the Openbox session |
| `root/defaults/skel/` | Templates copied into `/config` on first start only |
| `root/custom-cont-init.d/10-freecad-claude` | Root-time setup: addon install, MCP registration |
| `root/usr/local/bin/tile-windows` | Resolution-aware side-by-side tiling |
| `root/usr/local/bin/claude-session` | tmux wrapper around `claude` |

## Knobs

- `SPLIT_PERCENT` (default `38`) — terminal pane width, read by `tile-windows`.
- `CLAUDE_WORKDIR` (default `/config/workspace`) — Claude's cwd.
- Uncomment `devices: /dev/dri` in the compose file for GPU-accelerated 3D.
