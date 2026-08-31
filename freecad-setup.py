"""Headless FreeCAD pass: report the user directory and apply the dark theme.

Run by the init hook via `freecadcmd`. Every write is guarded, so a user who
picks a different stylesheet in the GUI keeps it across restarts.
"""

import os
import sys

import FreeCAD  # noqa: E402

user_dir = FreeCAD.getUserAppDataDir()
sys.__stdout__.write("FCUSERDIR=" + user_dir + "\n")
sys.__stdout__.flush()


def rgba(hex_color):
    """#rrggbb -> the unsigned int FreeCAD stores colours as (0xRRGGBBAA)."""
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return (r << 24) | (g << 16) | (b << 8) | 0xFF


# --- window stylesheet -----------------------------------------------------
# Pick from what this FreeCAD build actually ships instead of naming a file that
# may have been renamed between releases.
main = FreeCAD.ParamGet("User parameter:BaseApp/Preferences/MainWindow")
if not main.GetString("StyleSheet", ""):
    sheets = []
    for root, _dirs, files in os.walk(
        os.path.join(FreeCAD.getResourceDir(), "Gui", "Stylesheets")
    ):
        sheets += [f for f in files if f.endswith(".qss")]

    preferred = ["FreeCAD Dark.qss", "OpenDark.qss", "Behave-dark.qss", "Dark.qss"]
    chosen = next((p for p in preferred if p in sheets), None)
    if chosen is None:
        chosen = next((s for s in sorted(sheets) if "dark" in s.lower()), None)
    if chosen:
        main.SetString("StyleSheet", chosen)
        sys.__stdout__.write("FCSTYLESHEET=" + chosen + "\n")

# --- 3D viewport background ------------------------------------------------
# Own marker rather than checking the colours: leaves a user's later choice
# alone. If the param names shift in a future release this becomes a harmless
# no-op — set the background from Preferences > Display if so.
view = FreeCAD.ParamGet("User parameter:BaseApp/Preferences/View")
if not view.GetBool("SelkiesThemeApplied", False):
    view.SetUnsigned("BackgroundColor", rgba("#181825"))
    view.SetUnsigned("BackgroundColor2", rgba("#11111b"))
    view.SetUnsigned("BackgroundColor3", rgba("#1e1e2e"))
    view.SetBool("Simple", False)
    view.SetBool("Gradient", True)
    view.SetBool("UseBackgroundColorMid", False)
    view.SetBool("SelkiesThemeApplied", True)

FreeCAD.saveParameter()
