class_name GeoMath
extends RefCounted
## Geographic calculations on Vector2(longitude, latitude) degree pairs.
##
## Route legs are rhumb lines (loxodromes): lines of constant compass bearing.
## They are straight on the Mercator chart and in the Mercator navigation
## raster, so what the chart draws, what land validation checks and where the
## vessel actually sails are the same line. Distances along routes are rhumb
## distances; great-circle distance is only used for "as the crow flies" info.

const EARTH_RADIUS_NM := 3440.065

## Worldwide chart (Iteration 16): longitudes are normally kept in
## [-180, 180). A route's path may run past ±180 (e.g. 185 = 175° W) so that
## it is continuous across the Date Line; every difference of longitudes here
## is taken the short way round (wrap_delta), so both forms give the same
## distances and bearings.


## `lon` in [-180, 180).
static func normalize_lon(lon: float) -> float:
	return fposmod(lon + 180.0, 360.0) - 180.0


static func normalize(geo: Vector2) -> Vector2:
	return Vector2(normalize_lon(geo.x), geo.y)


## The difference `to_lon - from_lon` taken the short way round (-180..180).
static func wrap_delta(from_lon: float, to_lon: float) -> float:
	return fposmod(to_lon - from_lon + 180.0, 360.0) - 180.0


## True when two positions are the same place (longitudes compared round the globe).
static func same_position(a: Vector2, b: Vector2, tolerance := 1e-5) -> bool:
	return absf(a.y - b.y) <= tolerance and absf(wrap_delta(a.x, b.x)) <= tolerance


## A copy of `path` whose longitudes change continuously (each point the short
## way round from the one before), starting from the first point as it is.
static func unwrap_path(path: PackedVector2Array) -> PackedVector2Array:
	var result := path.duplicate()
	for i in range(1, result.size()):
		result[i].x = result[i - 1].x + wrap_delta(result[i - 1].x, result[i].x)
	return result


## Great-circle distance in nautical miles (haversine formula).
static func distance_nm(from: Vector2, to: Vector2) -> float:
	var lat1 := deg_to_rad(from.y)
	var lat2 := deg_to_rad(to.y)
	var d_lat := lat2 - lat1
	var d_lon := deg_to_rad(wrap_delta(from.x, to.x))
	var a := sin(d_lat / 2.0) ** 2 + cos(lat1) * cos(lat2) * sin(d_lon / 2.0) ** 2
	return 2.0 * EARTH_RADIUS_NM * asin(sqrt(a))


## Distance in nautical miles from `point` to the segment a-b, on a local flat
## projection around a (good for the short reaches of a canal or a harbour).
static func distance_to_segment_nm(point: Vector2, a: Vector2, b: Vector2) -> float:
	var k := cos(deg_to_rad(a.y)) * 60.0
	var p := Vector2(wrap_delta(a.x, point.x) * k, (point.y - a.y) * 60.0)
	var q := Vector2(wrap_delta(a.x, b.x) * k, (b.y - a.y) * 60.0)
	var t := clampf(p.dot(q) / maxf(q.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(q * t)


## Length of the rhumb line between two points, in nautical miles.
static func rhumb_distance_nm(from: Vector2, to: Vector2) -> float:
	var lat1 := deg_to_rad(from.y)
	var lat2 := deg_to_rad(to.y)
	var d_lat := lat2 - lat1
	var d_lon := deg_to_rad(wrap_delta(from.x, to.x))
	var d_psi := _psi(lat2) - _psi(lat1)
	# Along a constant-latitude line the stretched Mercator ratio is cos(lat).
	var q := d_lat / d_psi if absf(d_psi) > 1e-12 else cos(lat1)
	return sqrt(d_lat * d_lat + q * q * d_lon * d_lon) * EARTH_RADIUS_NM


## Point at `fraction` (0..1) of the rhumb-line distance from `from` to `to`.
## Distance along a rhumb line is proportional to the change in latitude, so
## latitude is interpolated linearly and longitude follows the constant bearing.
static func rhumb_interpolate(from: Vector2, to: Vector2, fraction: float) -> Vector2:
	var lat1 := deg_to_rad(from.y)
	var lat2 := deg_to_rad(to.y)
	var d_lat := lat2 - lat1
	var d_lon := wrap_delta(from.x, to.x)
	if absf(d_lat) < 1e-12:
		return Vector2(from.x + d_lon * fraction, from.y)
	var lat := lat1 + d_lat * fraction
	var share := (_psi(lat) - _psi(lat1)) / (_psi(lat2) - _psi(lat1))
	return Vector2(from.x + d_lon * share, rad_to_deg(lat))


## Constant compass bearing (degrees true, 0 = north, 90 = east) of the
## rhumb line from `from` to `to`.
static func rhumb_bearing(from: Vector2, to: Vector2) -> float:
	var d_psi := _psi(deg_to_rad(to.y)) - _psi(deg_to_rad(from.y))
	var d_lon := deg_to_rad(wrap_delta(from.x, to.x))
	return fposmod(rad_to_deg(atan2(d_lon, d_psi)), 360.0)


## The point `distance_nm` from `from` on the compass bearing `bearing_deg`
## (a short flat-earth step: for the few miles a boat sails off its line).
static func offset_nm(from: Vector2, bearing_deg: float, distance_nm: float) -> Vector2:
	var b := deg_to_rad(bearing_deg)
	var lat := from.y + distance_nm * cos(b) / 60.0
	var mean_lat := deg_to_rad((from.y + lat) * 0.5)
	return Vector2(from.x + distance_nm * sin(b) / (60.0 * maxf(cos(mean_lat), 0.01)), lat)


## Total rhumb length of a polyline, in nautical miles.
static func path_length_nm(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += rhumb_distance_nm(path[i - 1], path[i])
	return total


## Cumulative rhumb distances: result[i] is the distance from path[0] to path[i].
static func cumulative_distances(path: PackedVector2Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(path.size())
	var total := 0.0
	for i in path.size():
		if i > 0:
			total += rhumb_distance_nm(path[i - 1], path[i])
		result[i] = total
	return result


## Point at `distance` nm along a polyline (clamped to its ends).
static func point_along(path: PackedVector2Array, cumulative: PackedFloat64Array, distance: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if distance <= 0.0:
		return path[0]
	var last := path.size() - 1
	if distance >= cumulative[last]:
		return path[last]
	var i := cumulative.bsearch(distance, false)  # first index with cumulative > distance
	i = clampi(i, 1, last)
	var length := cumulative[i] - cumulative[i - 1]
	var fraction := (distance - cumulative[i - 1]) / length if length > 0.0 else 0.0
	return rhumb_interpolate(path[i - 1], path[i], fraction)


## Index of the segment (1..n-1, its end point) that contains `distance`.
static func segment_index_at(cumulative: PackedFloat64Array, distance: float) -> int:
	return clampi(cumulative.bsearch(distance, false), 1, maxi(cumulative.size() - 1, 1))


static func _psi(lat: float) -> float:
	return log(tan(PI / 4.0 + lat / 2.0))


static func format_position(geo: Vector2) -> String:
	return "%s  %s" % [_format_angle(geo.y, "N", "S"), _format_angle(normalize_lon(geo.x), "E", "W")]


static func _format_angle(value: float, positive: String, negative: String) -> String:
	var hemisphere := positive if value >= 0.0 else negative
	var absolute := absf(value)
	# Round to tenths of a minute first, so 16°59.97′ reads 17°00.0′, not 16°60.0′.
	var tenths := roundi(absolute * 600.0)
	var degrees := tenths / 600
	var minutes := (tenths % 600) / 10.0
	return "%d°%04.1f′%s" % [degrees, minutes, hemisphere]
