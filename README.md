# selkies-claude

A GUI application and Claude Code side by side in one browser-accessible
desktop session, with an MCP bridge between them. Currently targeting FreeCAD.

```bash
docker compose up -d --build
```

Then open <http://localhost:3000>.

## What is in the session

A real Openbox desktop rather than two bare windows: a tint2 panel with a
taskbar, clock and launchers along the bottom, a matching root window, and a
tiler that splits the usable area between the terminal and the app. Everything
shares one palette (Catppuccin Mocha) — terminal, panel, GTK apps, and the app's
own Qt stylesheet and 3D viewport background.

Both halves work out of `/config/workspace`. Claude starts there, the app is
launched from there so its open/save dialogs default there, and it maps to
`config/workspace` on the host, so dropping a file in from outside just works.

### Keys

| | |
| --- | --- |
| `Super+Return` | new terminal |
| `Super+t` | re-tile (also `retile` from a shell) |
| `Super+f` | toggle maximise |
| `Super+q` | close window |
| `Ctrl+Shift+d` | toggle window decorations (from the baseimage) |

## First run

1. **FreeCAD:** workbench dropdown → **MCP Addon** → **FreeCAD MCP** menu → tick
   **Auto-Start Server**. One time only; the setting lives on the volume. Until
   it is ticked the RPC server is down and Claude's tool calls fail with a
   connection error.
2. **Claude:** if `ANTHROPIC_API_KEY` is unset, run `/login` in the terminal
   pane once.
3. Check with `/mcp` — `freecad` should show as connected.

## Retargeting to another app

Two places:

1. The **APP DEFINITION** block near the top of the Dockerfile. `APP_WM_CLASS`
   is the one that catches people out — get it with `xprop WM_CLASS` and click
   the window. Set `APP_MCP_NAME` and `APP_MCP_COMMAND` empty for an app with no
   MCP server.
2. The two hook scripts at the bottom: `/opt/app/build.sh` (build time — extra
   installs) and `/opt/app/init.sh` (every start — anything that has to land in
   `/config`, which is a volume and therefore cannot be populated at build
   time). For an app that needs neither, replace both bodies with `exit 0`.

Nothing else in the file is app-specific. `freecad-setup.py` is a third,
FreeCAD-only file that reports FreeCAD's user directory and applies the dark
theme; delete it along with the hooks that call it.

## Layout

The Dockerfile inlines its files as heredocs so the repository is two files with
no build context to lose. If you would rather edit them separately, the same
content maps onto a `root/` tree copied with `COPY root/ /`:

```
root/defaults/autostart                  session contents
root/defaults/skel/                      seeded into /config on first start only
root/custom-cont-init.d/10-selkies-session   root-time setup, app-agnostic
root/usr/local/bin/tile-windows          workarea-aware tiler
root/usr/local/bin/claude-session        tmux wrapper
root/opt/app/{build,init}.sh             the app seam
```

## Notes

- `/defaults/skel/` files are copied into `/config` only when absent, so your
  edits survive rebuilds. Delete a file from `/config` to get the default back.
- The tiler reads `_NET_WORKAREA`, so the panel's strut is respected without
  hardcoded offsets, and it re-tiles when Selkies resizes the display to match
  your browser window.
- Qt widget styling is left to the app layer. Forcing `QT_STYLE_OVERRIDE`
  globally fights apps that ship their own stylesheet, which FreeCAD, KiCad and
  Blender all do.
