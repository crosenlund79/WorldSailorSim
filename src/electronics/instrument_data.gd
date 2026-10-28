class_name InstrumentData
extends RefCounted
## Marine electronics (I026 stage 03): one reading of everything the boat's
## instruments show, taken from the authoritative sources the HUD has always
## read - GameSession (speed, propulsion, voyage, anchor), Simulation (the
## heading of the leg being sailed, the wind and weather at the boat, the
## ETA, the forecast), WorldMap.get_next_turn() (the next course change).
## Nothing is calculated a second time: the instruments only present.
##
## Every package draws from the same reading, so the cheapest one shows the
## same essentials as the dearest. What the game does not simulate is not
## shown: there is no apparent wind (only the true wind and its angle to
## the boat) and no echo sounder underway; the depth appears only at anchor,
## where the anchor's own depth (a GAME ESTIMATE, DepthService) is known.
##
## Taken a few times a second by the HUD's InstrumentCluster and the focused
## InstrumentView, never every frame. The forecasts (the next leg, the
## weather page) are cached per leg and per half hour of game time, as the
## sailing panel did before.
##
## `values` holds the readouts as sentences (the same wording the sailing
## panel used, for tests and the focused view's text lines).

## Hours ahead on the weather page (a forecast made now, an estimate).
const FORECAST_HOURS: Array[int] = [3, 6, 12]

static var _leg_key := ""
static var _leg_text := ""
static var _leg_wind: WeatherSample
static var _forecast_key := ""
static var _forecast: Array[WeatherSample] = []
static var _outlook_key := ""
static var _outlook_text := ""

var active := false
var underway := false
var anchored := false
var holding := false
var motoring := false
var speed_kn := 0.0
var heading_deg := 0.0
## The sustained wind at the boat (where it blows from) and the gusts.
var wind_from_deg := 0.0
var wind_kn := 0.0
var gust_kn := 0.0
## "Gale", "Strong breeze"... when the weather is hazardous, else "".
var weather_label := ""
var hazard := 0
## The true wind's angle to the bow (-180..180, positive starboard).
var wind_angle := 0.0
var destination := ""
var remaining_nm := 0.0
var total_nm := 0.0
var progress := 0.0
var eta := 0.0
## WorldMap.get_next_turn(): {geo, nm, course, next_course} or empty.
var turn := {}
## The next anchorage waypoint ahead ({nm, ...}) or empty.
var anchorage := {}
var anchor_scope := 0
var anchor_depth_m := -1.0
## In harbour: where the boat lies.
var location := ""
## The forecast at the boat (FORECAST_HOURS) and the outlook along the
## course; only filled when asked for (with_weather).
var forecast: Array[WeatherSample] = []
var outlook := ""
var values := {}


## Reads the instruments now. `with_weather` also fills the weather page
## (the forecast at the boat and the outlook along the course).
static func read(with_weather := false) -> InstrumentData:
	var data := InstrumentData.new()
	if not GameSession.is_active():
		return data
	data.active = true
	var here := GameSession.get_vessel_position()
	var wind := Simulation.get_wind_at(here)
	data.wind_from_deg = wind.from_deg
	data.wind_kn = wind.speed_kn
	data.gust_kn = wind.gust_kn
	data.hazard = wind.hazard
	data.weather_label = wind.get_label() if wind.hazard >= WeatherModel.HAZARD_CAUTION else ""
	data.underway = GameSession.is_underway()
	data.values["wind"] = Hud.describe_wind(wind).trim_prefix("Wind ").trim_prefix(Loc.t("Wind") + " ")
	if not data.underway:
		var location := GameSession.get_location()
		data.location = location.display_name if location else ""
		data.values["speed"] = Loc.t("0 kn  ·  moored")
		data.values["status"] = Loc.t("Moored at %s") % data.location
		if with_weather:
			data._read_weather(here)
		return data
	var catalog := PortCatalog.get_default()
	data.anchored = GameSession.is_anchored()
	data.holding = GameSession.is_holding_at_anchorage()
	data.motoring = GameSession.is_motoring()
	data.speed_kn = 0.0 if data.anchored or data.holding else GameSession.get_vessel_speed_kn()
	data.heading_deg = Simulation.get_current_heading()
	data.destination = catalog.get_display_name(GameSession.get_voyage_destination_id())
	data.remaining_nm = GameSession.get_voyage_remaining_nm()
	data.total_nm = GameSession.get_voyage_total_nm()
	data.progress = clampf(1.0 - data.remaining_nm / data.total_nm, 0.0, 1.0) if data.total_nm > 0.0 else 1.0
	data.eta = Simulation.get_eta()
	data.turn = WorldMap.get_next_turn()
	data.anchorage = GameSession.get_next_anchorage()
	var propulsion := GameSession.get_propulsion()
	data.wind_angle = propulsion.true_wind_angle
	data.values["route"] = Loc.t("To %s  ·  %d nm to go") % [data.destination, roundi(data.remaining_nm)]
	data.values["eta"] = Loc.t("ETA about %s (estimate)") % Simulation.format_game_time(data.eta)
	data.values["remaining"] = Loc.t("%d nm  ·  ETA %s (estimate)") % [roundi(data.remaining_nm), short_time(data.eta)]
	if data.anchored:
		var anchor := GameSession.get_anchor()
		data.anchor_scope = anchor.scope
		data.anchor_depth_m = anchor.depth_m
		data.values["speed"] = Loc.t("0 kn  ·  at anchor")
		data.values["anchor"] = Loc.t("%s  ·  %d × the depth of chain") % [Loc.t(AnchorSite.holding_text(anchor.holding)), anchor.scope]
		if anchor.depth_m > 0.0:
			data.values["depth"] = Loc.t("Depth %s (game estimate)") % DepthService.describe_depth(anchor.depth_m)
		data.values["status"] = Loc.t("Raise the anchor at the windlass to sail on")
	elif data.holding:
		data.values["speed"] = Loc.t("0 kn  ·  waiting at the anchorage")
		data.values["status"] = Loc.t("Drop the anchor, or sail on (Q)")
	else:
		data.values["speed"] = Loc.format("%.1f kn  ·  %s", [data.speed_kn, Loc.t("under engine") if data.motoring else Loc.t("under sail")])
		data.values["heading"] = Loc.t("%03d°  ·  on the planned course") % roundi(data.heading_deg)
		var side := PropulsionState.wind_side(data.wind_angle)
		if wind.speed_kn >= 0.5:
			data.values["wind"] += "  ·  %d° %s" % [roundi(absf(data.wind_angle)), side if side else Loc.t("off the bow")]
		data.values["trim"] = describe_trim(propulsion)
		data.values["propulsion"] = propulsion.describe()
		data._describe_turn(catalog)
	if with_weather:
		data._read_weather(here)
	return data


## The next turn, the next leg's forecast, or the anchorage ahead: the same
## words as the sailing panel had (nothing invented on the last leg).
func _describe_turn(_catalog: PortCatalog) -> void:
	if turn.is_empty() or float(turn.next_course) < 0.0:
		var arrive := Loc.t("No more turns: %s ahead") % destination
		if not turn.is_empty():
			arrive += Loc.format(", %.1f nm", float(turn.nm))
		values["turn"] = arrive
	elif not anchorage.is_empty() and float(anchorage.nm) <= float(turn.nm) + 1e-6:
		var nm := float(anchorage.nm)
		values["turn"] = Loc.format("Anchorage in %s, %.1f nm", [Simulation.format_duration(nm / speed_kn * 3600.0), nm]) if speed_kn > 0.3 \
			else Loc.format("Anchorage %.1f nm ahead", nm)
	else:
		values["next_leg"] = _next_leg_text(turn, speed_kn)
		var eta_turn := Loc.format("in %s, %.1f nm", [Simulation.format_duration(float(turn.nm) / speed_kn * 3600.0), float(turn.nm)]) \
			if speed_kn > 0.3 else Loc.format("%.1f nm ahead", float(turn.nm))
		values["turn"] = "%s  →  %03d°" % [eta_turn, roundi(turn.next_course)]


## True when there is a course change ahead (not the last leg, not an
## anchorage first).
func has_next_leg() -> bool:
	return values.has("next_leg")


## The wind forecast at the next turn for when the boat gets there (a
## forecast made now: only weather that has formed by now), or null.
func next_leg_wind() -> WeatherSample:
	return _leg_wind if has_next_leg() else null


func get_value(key: String) -> String:
	return String(values.get(key, ""))


## "260°  ·  forecast W 12 kn (estimate)": refreshed per leg and half hour.
static func _next_leg_text(next_turn: Dictionary, speed: float) -> String:
	var voyage := GameSession.get_voyage()
	var key := "%d|%s|%d" % [voyage.revision, next_turn.geo, floori(GameSession.get_game_time() / 1800.0)]
	if key != _leg_key:
		_leg_key = key
		var hours := float(next_turn.nm) / maxf(speed, 1.0)
		var now := GameSession.get_game_time()
		_leg_wind = Simulation.get_weather_at(next_turn.geo, now + hours * 3600.0, now)
		var wind := Loc.t("calm") if _leg_wind.speed_kn < 0.5 else Loc.t("%s %d kn") % [WindField.compass_name(_leg_wind.from_deg), roundi(_leg_wind.speed_kn)]
		_leg_text = Loc.t("%03d°  ·  forecast %s (estimate)") % [roundi(next_turn.next_course), wind]
	return _leg_text


## The weather page: the forecast here for the next hours and the outlook
## along the course (cached per half hour; the outlook also per course).
func _read_weather(here: Vector2) -> void:
	var now := GameSession.get_game_time()
	var slot := floori(now / 1800.0)
	var key := "%d|%.2f|%.2f" % [slot, here.x, here.y] if not underway else "%d" % slot
	if key != _forecast_key:
		_forecast_key = key
		_forecast.clear()
		for hours in FORECAST_HOURS:
			_forecast.append(Simulation.get_weather_at(here, now + hours * 3600.0, now))
	forecast = _forecast
	var lines := PackedStringArray()
	for i in FORECAST_HOURS.size():
		lines.append(Loc.t("+%d h %s") % [FORECAST_HOURS[i], describe_sample(_forecast[i])])
	values["forecast"] = "  ·  ".join(lines)
	if underway:
		var voyage_key := "%d|%d" % [GameSession.get_voyage().revision, slot]
		if voyage_key != _outlook_key:
			_outlook_key = voyage_key
			var hazards := Simulation.get_hazards_ahead()
			if hazards.is_empty():
				_outlook_text = Loc.t("No hazards on the course in the next %d hours") % roundi(Simulation.DISPLAY_HORIZON_HOURS)
			else:
				var first: Dictionary = hazards[0]
				_outlook_text = Loc.t("%s on the course in about %d h") % [String(first.label), maxi(roundi(float(first.hours)), 1)]
		outlook = _outlook_text
	else:
		outlook = ""
	values["outlook"] = outlook


## "W 12 kn" or "calm", with the gusts when they stand out.
static func describe_sample(sample: WeatherSample) -> String:
	if sample.speed_kn < 0.5:
		return Loc.t("calm")
	var text := Loc.t("%s %d kn") % [WindField.compass_name(sample.from_deg), roundi(sample.speed_kn)]
	if sample.gust_kn >= sample.speed_kn + 6.0:
		text += Loc.t(", gusts %d") % roundi(sample.gust_kn)
	return text


## The sail trim (Iteration 18): how the sails are trimmed, the effect,
## and the key that opens the trim.
static func describe_trim(propulsion: PropulsionState) -> String:
	if propulsion.is_motoring():
		return Loc.t("under engine  ·  T to trim")
	var trim := GameSession.get_sail_trim()
	var word := SailTrim.feedback(trim.auto, trim.value, propulsion.true_wind_angle, propulsion.wind_speed_kn)
	if trim.auto:
		return Loc.t("%s  ·  T to trim by hand") % word.to_lower()
	return "%s  ·  %+d %%  ·  T" % [word.to_lower(), SailTrim.percent(trim.auto, trim.value, propulsion.true_wind_angle, propulsion.wind_speed_kn)]


## "Thu 21 May, 07:25" (the year and zone are in the clock bar).
static func short_time(unix_time: float) -> String:
	var text := Simulation.format_game_time(unix_time, false)
	var parts := text.split(" ")
	return "%s %s %s, %s" % [parts[0], parts[1], parts[2], parts[parts.size() - 1]] if parts.size() >= 5 else text


## "Sat 15:03": the ETA on a small display.
static func clock_time(unix_time: float) -> String:
	var text := Simulation.format_game_time(unix_time, false)
	var parts := text.split(" ")
	return "%s %s" % [parts[0], parts[parts.size() - 1]] if parts.size() >= 2 else text
