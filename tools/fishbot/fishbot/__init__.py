"""fishbot - client-side automation for the qs-fisher fishing loop.

The tool drives the mouse and keyboard of the local FiveM client and reads the
resource's own NUI HUD from the screen to close the loop.  It never talks to the
server, never edits the resource and never needs a bridge: everything it knows
about the game state comes from the pixels the HUD already draws.
"""

__version__ = "1.0.0"
