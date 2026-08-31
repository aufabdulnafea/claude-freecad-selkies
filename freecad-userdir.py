# Ask FreeCAD itself where its user data directory is. The addon path moved
# between FreeCAD 0.19 (~/.FreeCAD), 1.0 (~/.local/share/FreeCAD) and 1.1
# (~/.local/share/FreeCAD/v1-1), so hardcoding one is a guess that silently
# leaves the addon undiscovered.
import sys

import FreeCAD  # noqa: E402

sys.__stdout__.write("FCUSERDIR=" + FreeCAD.getUserAppDataDir() + "\n")
sys.__stdout__.flush()
