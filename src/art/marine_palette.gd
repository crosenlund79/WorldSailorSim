class_name MarinePalette
extends RefCounted
## The shared colours of Operation Real Horizon (Illustrated Mariner x
## Atmospheric Sailing Simulator). Every procedural drawing (sea, harbours,
## chart, props, characters) takes its materials from here, and the Python
## painters in tools/ use the same values (tools/art/marine_palette.py), so
## the world stays one coherent picture. See DEV_GUIDES/ART_DIRECTION.md.
##
## Colours describe materials in neutral daylight; the light of the hour and
## the weather is applied on top (BoatLighting's CanvasModulate, SeaSurface),
## never baked into the material.

# --- Sea ------------------------------------------------------------------------------------------
const DEEP_SEA := Color("#294653")
const OPEN_WATER := Color("#527887")
const COASTAL_WATER := Color("#638C8B")
const HARBOUR_WATER := Color("#4C6F70")
const STORM_SEA := Color("#2C3C44")
const WAVE_LIGHT := Color("#A9C2C6")
const WAVE_SHADOW := Color("#1D333C")
const FOAM := Color("#E6ECEA")

# --- Sky and air ------------------------------------------------------------------------------------
const OVERCAST_SKY := Color("#A4B4BA")
const SEA_HAZE := Color("#CBD3D0")
const STORM_SKY := Color("#5F6E75")
const NIGHT_SKY := Color("#141E27")

# --- Boat materials ---------------------------------------------------------------------------------
const FIBREGLASS := Color("#D8D9D2")
const FIBREGLASS_SHADE := Color("#AEB3AE")
const NON_SKID := Color("#C7C9C1")
const BRUSHED_STEEL := Color("#77888C")
const STEEL_LIGHT := Color("#B4BEC0")
const TEAK := Color("#887663")
const TEAK_DARK := Color("#6E604F")
const MARINE_TIMBER := Color("#665646")
const CANVAS_SPRAYHOOD := Color("#3F4D57")
const SAILCLOTH := Color("#E3E2DA")
const SAILCLOTH_SHADE := Color("#B9BAB3")
const ROPE := Color("#C9C3B2")
const LINE_DARK := Color("#2A3236")
const ANTIFOUL := Color("#30373D")
const BOOTTOP := Color("#2F4F63")

# --- Shore --------------------------------------------------------------------------------------------
const CONCRETE := Color("#9A9C97")
const GRANITE := Color("#7D817F")
const TIMBER_PONTOON := Color("#7E7466")
const COMPOSITE_PONTOON := Color("#8D8F8A")
const ASPHALT := Color("#4E5355")
const GRASS := Color("#6F7D5E")

# --- Electronics ---------------------------------------------------------------------------------------
const PANEL := Color("#202D35")
const PANEL_DEEP := Color("#151E24")
const INSTRUMENT_CYAN := Color("#5AA8B8")
const WARNING_AMBER := Color("#D49A4B")
const DATA_WHITE := Color("#E4EAE8")

# --- Light ----------------------------------------------------------------------------------------------
const LAMP_INTERIOR := Color(1.0, 0.86, 0.68)
const LAMP_QUAY := Color(1.0, 0.84, 0.62)
const LAMP_LED := Color(0.86, 0.93, 1.0)

## The base colour of the sea for a coastal amount (0 open sea .. 1 in harbour)
## and a storm amount (0 .. 1).
static func sea_colour(coastal: float, storm: float) -> Color:
	var c := OPEN_WATER.lerp(COASTAL_WATER, clampf(coastal, 0.0, 1.0))
	return c.lerp(STORM_SEA, clampf(storm, 0.0, 1.0) * 0.8)
