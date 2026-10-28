class_name WaterLook
extends RefCounted
## Softer, more translucent water (I022): the colour of the open water
## around the boat, as a plain colour blend - no shader, no transparency, no
## per-frame work.
##
## "Translucent" is suggested by letting a little of a sandy, green-grey
## seabed colour show through the deep blue-green; a touch more in harbour,
## where the water is shallow. The day/night light (BoatLighting) and the
## crests, ripples and glints of WaterLife still lie over it, so dawn, night,
## calm and rough water stay as distinct as before.
##
## Kept apart from the cabin windows' glass: WINDOW glass tint lives in
## CabinWindows and does not change this, and `translucency` here does not
## change the glass. `translucency = 0` gives the water exactly as it was
## before I022 (the before/after screenshots use that).

## The water's own colour until I022 (every deck scene's Surroundings/Water).
const DEEP := Color(0.1137, 0.2745, 0.3216)
## What shows through: a pale sandy green-grey (shallow sea over sand).
const SEABED := Color(0.42, 0.55, 0.5)
## How much of the seabed shows at sea, and how much more in harbour.
const OPEN_SEA := 0.12
const SHALLOW_EXTRA := 0.1

## The overall strength (1 = as designed, 0 = the old solid water).
static var translucency := 1.0


## The water colour around the boat now: at sea, or moored / at anchor in
## shallower water.
static func water_colour(shallow: bool) -> Color:
	var share := (OPEN_SEA + (SHALLOW_EXTRA if shallow else 0.0)) * clampf(translucency, 0.0, 2.0)
	return DEEP.lerp(SEABED, clampf(share, 0.0, 0.6))


## True where the boat floats in shallow water: moored, or at anchor.
static func is_shallow() -> bool:
	return not GameSession.is_underway() or GameSession.is_anchored()
