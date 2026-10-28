class_name VesselDefinition
extends Resource
## What a boat is: its identity, how it sails, where its scenes are and which
## art it uses. Pure data (a .tres per vessel in data/vessels/); the game asks
## GameSession for the active definition instead of assuming one boat.
##
## Saves store only `id`, which must never change once released.

const HULL_MONOHULL := &"monohull"
const HULL_CATAMARAN := &"catamaran"
const HULL_TRIMARAN := &"trimaran"

## Stable identifier used in saves (never the display name or a path).
@export var id: StringName
@export var display_name := ""
@export_enum("monohull", "catamaran", "trimaran") var hull_type := "monohull"
@export_multiline var description := ""
## What the boat costs at a boatyard, in euros (I022). Every new game is given
## the starter boat; the others are bought once and then kept for good.
@export var price := 0
## Short facts shown in the boatyard, e.g. {"Length": "10.1 m (33 ft)"}.
@export var specs: Dictionary[String, String] = {}
## Sailing polar, engine and propulsion-controller settings.
@export var performance: VesselProfile
## Deck (exterior) and cabin (interior) gameplay scenes.
@export var deck_scene: PackedScene
@export var cabin_scene: PackedScene
## Art-only scenes (instanced by the gameplay scenes; used alone for previews).
@export var deck_visual_scene: PackedScene
## Which art each visual slot uses (sprites with procedural fallback).
@export var visual_profile: VesselVisualProfile
## An illustrated art-direction prototype (Visual Identity V01), shown instead
## of visual_profile while the Artwork setting is "illustrated". Null would fall
## back to visual_profile (every boat has one since 0.100b).
@export var illustrated_visual_profile: VesselVisualProfile
## Days of food and water the boat can stow for a long passage (Iteration 16;
## everyday stores are Provisions.CAPACITY_DAYS). Small boats carry less but
## can still cross an ocean by way of the island harbours.
@export_range(14.0, 60.0, 1.0) var passage_stores_days := 32.0


## The art to show now: the illustrated prototype when the player's Artwork
## setting asks for it and this boat has one, otherwise visual_profile.
func get_active_visual_profile() -> VesselVisualProfile:
	if illustrated_visual_profile and SettingsManager.get_art_style() == SettingsManager.ART_ILLUSTRATED:
		return illustrated_visual_profile
	return visual_profile


## The gameplay scene for a boat area (SessionState.AREA_*).
func get_area_scene(area: StringName) -> PackedScene:
	return cabin_scene if area == SessionState.AREA_INTERIOR else deck_scene


## "Monohull" / "Catamaran" / "Trimaran".
func get_hull_type_name() -> String:
	return hull_type.capitalize()


## Problems that would stop this vessel from working (empty when valid).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append(Loc.t("no id"))
	if performance == null:
		problems.append(Loc.t("no performance profile"))
	if deck_scene == null or cabin_scene == null:
		problems.append(Loc.t("missing deck or cabin scene"))
	return problems
