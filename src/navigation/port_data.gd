class_name PortData
extends Resource
## A port or anchorage the player can select on the world map.
##
## Coordinates are geographic (WGS84 degrees). They are never screen or map
## pixels; MapProjection converts them for display.

## Stable identifier used in saves and routes. Never rename once shipped.
@export var id: StringName
## Shown in the current language (I019): the catalogue's English name is the
## message key; most harbours keep their own name.
@export var display_name := "":
	get:
		return Loc.t(display_name, "place")
@export var country := ""
@export_range(-90.0, 90.0, 0.0001) var latitude := 0.0
@export_range(-180.0, 180.0, 0.0001) var longitude := 0.0
@export_multiline var description := ""
## How prominent the harbour is on the chart: 1 = major (shown at every zoom
## level), 2 = shown from a regional zoom, 3 = shown only when zoomed in.
## Selection, search, routing and saves treat all harbours the same.
@export_range(1, 3) var importance := 1
## Sea area for coverage reports (e.g. "baltic", "adriatic"; see
## tools/navigation/harbours.csv).
@export var region := ""
@export var island := false
## Where the coordinates come from (e.g. a UN/LOCODE entry).
@export var source := ""


## The one-sentence description in the current language (the English text is
## the message key).
func get_description() -> String:
	return Loc.t(description) if description != "" else ""


## Geographic position as Vector2(longitude, latitude) in degrees.
func get_geo_position() -> Vector2:
	return Vector2(longitude, latitude)
