class_name HarbourNotes
extends RefCounted
## What the harbour office and the quay's noticeboard tell (I026 stage 02),
## from the data the game already has: the harbour's tier and services
## (HarbourFacilities.describe_services) with their opening hours
## (BusinessHours), its description and why it is special (PortData,
## HarbourLooks), the forecast in words from the one weather model
## (Simulation.get_weather_at, as known now: a forecast, not a promise), and
## a few small pinned notes (data/harbours/notices.json).
##
## Information only: no quests, nothing to earn, and never a replacement for
## the HUD's weather and traffic warnings, which arrive as always.

const NOTICES_PATH := "res://data/harbours/notices.json"
## Hours ahead for the forecast lines.
const FORECAST_STEPS: Array[float] = [0.0, 6.0, 12.0, 24.0]

static var _notices: Array = []


## "Major service harbour: Groceries · Boatyard · …" (the chart's words).
static func services(port_id: StringName) -> String:
	return HarbourFacilities.describe_services(port_id, true)


## One line per business on the quay: "Chandlery  09:00–17:00, closed on
## Sunday  ·  open until 17:00".
static func hours_lines(layout: QuayLayout, time: float) -> Array[String]:
	var lines: Array[String] = []
	for business in layout.get_businesses():
		lines.append("%s  %s  ·  %s" % [HarbourFront.business_name(business), BusinessHours.describe(business, layout.port_id),
			BusinessHours.status_text(business, layout.port_id, time)])
	return lines


## The harbour's own words: its description and why it is special.
static func local_notes(port_id: StringName) -> Array[String]:
	var lines: Array[String] = []
	var port := PortCatalog.get_default().get_port(port_id)
	if port and not port.get_description().is_empty():
		lines.append(port.get_description())
	var special := HarbourLooks.get_default().special_note(port_id)
	if not special.is_empty():
		lines.append(Loc.t("Worth seeing: %s.") % special.trim_suffix("."))
	return lines


## The forecast in words for the harbour: now, and 6, 12 and 24 hours on,
## as the weather model knows it now ("This evening: wind SW 14 kn,
## gusts 22  ·  fair").
static func forecast_lines(port_id: StringName, time: float) -> Array[String]:
	var lines: Array[String] = []
	var port := PortCatalog.get_default().get_port(port_id)
	var geo := port.get_geo_position() if port else GameSession.get_vessel_position()
	for hours in FORECAST_STEPS:
		var at := time + hours * 3600.0
		var sample := Simulation.get_weather_at(geo, at, time)
		lines.append("%s: %s  ·  %s" % [when_words(port_id, time, at), Hud.describe_wind(sample).replace("  ·  %s" % sample.get_label(), ""),
			sample.get_label().to_lower()])
	return lines


## "Now", "This afternoon", "Tonight", "Tomorrow morning" ... (local time).
static func when_words(port_id: StringName, now: float, at: float) -> String:
	if at - now < 1800.0:
		return Loc.t("Now")
	var h := BusinessHours.local_hours(port_id, at)
	var same_day := floori((at + BusinessHours.longitude_of(port_id) / 15.0 * 3600.0) / 86400.0) \
		== floori((now + BusinessHours.longitude_of(port_id) / 15.0 * 3600.0) / 86400.0)
	if h < 5.0 or h >= 22.0:
		return Loc.t("Tonight") if same_day or h < 5.0 else Loc.t("Tomorrow night")
	if h < 12.0:
		return Loc.t("This morning") if same_day else Loc.t("Tomorrow morning")
	if h < 17.0:
		return Loc.t("This afternoon") if same_day else Loc.t("Tomorrow afternoon")
	return Loc.t("This evening") if same_day else Loc.t("Tomorrow evening")


## A few small notes for this harbour this week (the same all week).
static func notices(port_id: StringName, time: float, count := 3) -> Array[String]:
	if _notices.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NOTICES_PATH))
		_notices = (parsed as Dictionary).get("notices", []) if parsed is Dictionary else []
	var out: Array[String] = []
	if _notices.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [port_id, floori(time / (7.0 * 86400.0))])
	var order := range(_notices.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var layout := QuayLayout.build(port_id)
	for i in order:
		var text := String((_notices[i] as Dictionary).get("text", ""))
		if text.contains("travel lift") and layout.lift == Vector2.ZERO:
			continue
		out.append(Loc.t(text))
		if out.size() >= count:
			break
	return out
