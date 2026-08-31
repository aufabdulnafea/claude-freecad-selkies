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
