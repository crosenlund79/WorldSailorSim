"""Real Horizon's shared palette for the Python painters (RGB tuples).

The same values as src/art/marine_palette.gd; see DEV_GUIDES/ART_DIRECTION.md.
The painters keep their own material names; use these when adding new art.
"""


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


DEEP_SEA = _hex("#294653")
OPEN_WATER = _hex("#527887")
COASTAL_WATER = _hex("#638C8B")
OVERCAST_SKY = _hex("#A4B4BA")
SEA_HAZE = _hex("#CBD3D0")
FIBREGLASS = _hex("#D8D9D2")
BRUSHED_STEEL = _hex("#77888C")
TEAK = _hex("#887663")
MARINE_TIMBER = _hex("#665646")
PANEL = _hex("#202D35")
INSTRUMENT_CYAN = _hex("#5AA8B8")
WARNING_AMBER = _hex("#D49A4B")
LINE = _hex("#2A3236")
