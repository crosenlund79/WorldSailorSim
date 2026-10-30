class_name NavGrid
extends RefCounted
## The navigability raster: which parts of the chart a vessel may sail through.
##
## Cells are laid out in Mercator space (CELLS_PER_DEGREE per Mercator degree),
## so a rhumb line is a straight line through the grid and can be checked
## exactly, cell by cell. Each cell holds one of three classes:
##   NAVIGABLE (255): no land in any part of the cell. Routes may pass.
##   APPROACH  (128): mostly water. Only usable for bounded harbour approaches.
##   LAND      (0):   everything else, including the area outside the chart.
## The raster is generated from the same coastline polygons the chart draws
## (tools/navigation/build_navigation_data.py).
##
## Regional detail (Iteration 14): a base grid may carry finer regional grids
## (data/navigation/regions.json, built by tools/navigation/build_region.py),
## each covering a rectangle of whole base cells with `factor` x the
## resolution, in the same geographic coordinates and Mercator layout. The
## geographic queries (cell_class_at_geo, is_navigable, is_geo_line_clear,
## grid_at) consult the region wherever it covers and the base elsewhere; a
## line crossing a region's edge is split there and each part is checked in
## its own grid. Cell-index queries (get_class_at, is_line_clear) work on one
## grid; use grid_at() to pick the right one.
##
## The world (Iteration 16): the root grid is the whole planet at 12 cells
## per degree (data/navigation/world/, tools/navigation/build_world.py). Its
## columns wrap at ±180° (`wraps`), so lines may cross the Date Line with
## continuous longitudes. Europe is a region of the world (factor 5) and
## Denmark a region of Europe (factor 6): the lookups recurse through the
## levels. One coordinate system everywhere.

const NAVIGABLE := 255
const APPROACH := 128
const LAND := 0

const DEFAULT_MASK := "res://data/navigation/europe_navmask.png"
const DEFAULT_META := "res://data/navigation/europe_navmask.json"
const REGIONS_INDEX := "res://data/navigation/regions.json"
const WORLD_MASK := "res://data/navigation/world/navmask.png"
const WORLD_META := "res://data/navigation/world/world.json"
## How far (cells) a line's part is nudged off a region edge, so each part
## is checked only in its own grid.
const SEAM_NUDGE := 0.01

var columns := 0
var rows := 0
var cells_per_degree := 60.0
var west := 0.0
var mercator_north := 0.0
var _cells := PackedByteArray()

## Regional detail grids of this base grid (empty for a region itself).
var regions: Array[NavGrid] = []
## For a region grid: its id and name, its first base cell and size in base
## cells, and its resolution factor over the base.
var region_id := ""
var region_name := ""
var base_cell := Vector2i.ZERO
var base_size := Vector2i.ZERO
var factor := 1
## True for the world grid: column -1 is column columns-1 (Date Line).
var wraps := false
## Map units: the world's metadata (bounds etc.) for the chart, if any.
var meta := {}


static func load_from(mask_path: String, meta_path: String) -> NavGrid:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var bytes := FileAccess.get_file_as_bytes(mask_path)
	if not meta is Dictionary or bytes.is_empty():
		push_error("Navigation data missing: %s / %s" % [mask_path, meta_path])
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		push_error("Navigation mask unreadable: %s" % mask_path)
		return null
	image.convert(Image.FORMAT_L8)
	var grid := NavGrid.new()
	grid.columns = image.get_width()
	grid.rows = image.get_height()
	grid.cells_per_degree = float(meta.cells_per_mercator_degree)
	grid.west = float(meta.bounds.west)
	grid.mercator_north = float(meta.mercator_north)
	grid._cells = image.get_data()
	grid.meta = meta
	if grid.columns != int(meta.columns) or grid.rows != int(meta.rows):
		push_error("Navigation mask size does not match its metadata.")
		return null
	return grid


## The whole hierarchy: the world grid, Europe as its first region, Europe's
## own regions (Denmark, Sweden) and the world's (New Zealand). Null when the
## world data is missing.
static func load_world(world_mask := WORLD_MASK, world_meta := WORLD_META, europe_mask := DEFAULT_MASK,
		europe_meta := DEFAULT_META, regions_index := REGIONS_INDEX) -> NavGrid:
	var world := NavGrid.load_from(world_mask, world_meta)
	if world == null:
		return null
	world.wraps = bool(world.meta.get("wraps", false))
	world.region_id = "world"
	# Detail regions of the world chart itself (New Zealand; Regions and Harbours 2026).
	world.load_regions(regions_index, "world")
	var europe := NavGrid.load_from(europe_mask, europe_meta)
	var link: Dictionary = world.meta.get("europe", {})
	if europe and not link.is_empty():
		europe.region_id = "europe"
		europe.region_name = Loc.t("Europe")
		europe.factor = int(link.factor)
		europe.base_cell = Vector2i(int(link.base_cells.column), int(link.base_cells.row))
		europe.base_size = Vector2i(int(link.base_cells.columns), int(link.base_cells.rows))
		europe.load_regions(regions_index)
		world.regions.push_front(europe)
	return world


## Loads the regional grids listed in `index_path` (missing index: none) that
## refine `parent`: "europe" (the European chart; an entry without "parent")
## or "world" (the world chart).
func load_regions(index_path := REGIONS_INDEX, parent := "europe") -> void:
	regions.clear()
	if not FileAccess.file_exists(index_path):
		return
	var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not index is Dictionary:
		return
	for entry: Dictionary in index.get("regions", []):
		if String(entry.get("parent", "europe")) != parent:
			continue
		var folder: String = entry.get("folder", "")
		var region := NavGrid.load_region(folder.path_join("navmask.png"), folder.path_join("region.json"))
		if region:
			regions.append(region)


static func load_region(mask_path: String, meta_path: String) -> NavGrid:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var bytes := FileAccess.get_file_as_bytes(mask_path)
	if not meta is Dictionary or bytes.is_empty():
		push_error("Region data missing: %s / %s" % [mask_path, meta_path])
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		push_error("Region mask unreadable: %s" % mask_path)
		return null
	image.convert(Image.FORMAT_L8)
	var grid := NavGrid.new()
	grid.columns = image.get_width()
	grid.rows = image.get_height()
	grid.cells_per_degree = float(meta.cells_per_mercator_degree)
	grid.west = float(meta.base_west)
	grid.mercator_north = float(meta.mercator_north)
	grid.region_id = String(meta.id)
	grid.region_name = String(meta.get("name", meta.id))
	grid.factor = int(meta.factor)
	grid.base_cell = Vector2i(int(meta.base_cells.column), int(meta.base_cells.row))
	grid.base_size = Vector2i(int(meta.base_cells.columns), int(meta.base_cells.rows))
	grid._cells = image.get_data()
	if grid.columns != int(meta.columns) or grid.rows != int(meta.rows) or grid.columns != grid.base_size.x * grid.factor:
		push_error("Region mask size does not match its metadata: %s" % meta_path)
		return null
	return grid


## The region rectangle in base cell coordinates.
func get_base_rect() -> Rect2:
	return Rect2(Vector2(base_cell), Vector2(base_size))


## The grid that holds the detail at `geo`: the finest region covering it
## (through every level), or this one.
func grid_at(geo: Vector2) -> NavGrid:
	if regions.is_empty():
		return self
	var cell := _wrapped(geo_to_cell(geo))
	for region in regions:
		if region.get_base_rect().has_point(cell):
			return region.grid_at(geo)
	return self


## The region of this grid (one level down) covering `geo`, or this grid.
func child_at(geo: Vector2) -> NavGrid:
	var cell := _wrapped(geo_to_cell(geo))
	for region in regions:
		if region.get_base_rect().has_point(cell):
			return region
	return self


## Every grid of the hierarchy, this one first.
func all_grids() -> Array[NavGrid]:
	var result: Array[NavGrid] = [self]
	for region in regions:
		result.append_array(region.all_grids())
	return result


func _wrapped(cell: Vector2) -> Vector2:
	if wraps:
		cell.x = fposmod(cell.x, columns)
	return cell


## The region (id) covering `geo`, or "" in the base chart.
func region_id_at(geo: Vector2) -> String:
	return grid_at(geo).region_id


# --- Coordinates -----------------------------------------------------------------------

## Geographic Vector2(lon, lat) to continuous cell coordinates (column, row).
func geo_to_cell(geo: Vector2) -> Vector2:
	var lat := deg_to_rad(clampf(geo.y, -85.0, 85.0))
	var mercator_y := rad_to_deg(log(tan(PI / 4.0 + lat / 2.0)))
	return Vector2((geo.x - west) * cells_per_degree, (mercator_north - mercator_y) * cells_per_degree)


func cell_to_geo(cell: Vector2) -> Vector2:
	var mercator_y := deg_to_rad(mercator_north - cell.y / cells_per_degree)
	return Vector2(west + cell.x / cells_per_degree, rad_to_deg(2.0 * atan(exp(mercator_y)) - PI / 2.0))


## Geographic centre of the cell (column, row).
func cell_center_geo(column: int, row: int) -> Vector2:
	return cell_to_geo(Vector2(column + 0.5, row + 0.5))


# --- Queries ------------------------------------------------------------------------------

func get_class_at(column: int, row: int) -> int:
	if wraps:
		column = posmod(column, columns)
	if column < 0 or row < 0 or column >= columns or row >= rows:
		return LAND
	return _cells[row * columns + column]


func cell_class_at_geo(geo: Vector2) -> int:
	var grid := grid_at(geo)
	var cell := grid.geo_to_cell(geo)
	return grid.get_class_at(floori(cell.x), floori(cell.y))


func is_navigable(geo: Vector2) -> bool:
	return cell_class_at_geo(geo) == NAVIGABLE


## True if the straight line between two cell-space points only passes through
## cells of at least `min_class`. Every cell the line touches is checked
## (supercover traversal); when the line passes exactly through a cell corner,
## both side cells must qualify. Mirrors segment_clear() in the data builder.
func is_line_clear(from: Vector2, to: Vector2, min_class := NAVIGABLE) -> bool:
	var ix := floori(from.x)
	var iy := floori(from.y)
	var ex := floori(to.x)
	var ey := floori(to.y)
	if get_class_at(ix, iy) < min_class:
		return false
	var dx := to.x - from.x
	var dy := to.y - from.y
	var step_x := 1 if dx > 0.0 else (-1 if dx < 0.0 else 0)
	var step_y := 1 if dy > 0.0 else (-1 if dy < 0.0 else 0)
	var t_delta_x := absf(1.0 / dx) if dx != 0.0 else INF
	var t_delta_y := absf(1.0 / dy) if dy != 0.0 else INF
	var t_max_x := INF
	var t_max_y := INF
	if dx != 0.0:
		t_max_x = ((ix + 1 - from.x) if dx > 0.0 else (from.x - ix)) * t_delta_x
	if dy != 0.0:
		t_max_y = ((iy + 1 - from.y) if dy > 0.0 else (from.y - iy)) * t_delta_y
	var guard := absi(ex - ix) + absi(ey - iy) + 2
	while (ix != ex or iy != ey) and guard > 0:
		guard -= 1
		if absf(t_max_x - t_max_y) < 1e-9:
			if get_class_at(ix + step_x, iy) < min_class or get_class_at(ix, iy + step_y) < min_class:
				return false
			ix += step_x
			iy += step_y
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			ix += step_x
			t_max_x += t_delta_x
		else:
			iy += step_y
			t_max_y += t_delta_y
		if get_class_at(ix, iy) < min_class:
			return false
	return true


func is_geo_line_clear(from: Vector2, to: Vector2, min_class := NAVIGABLE) -> bool:
	var a := geo_to_cell(from)
	var b := geo_to_cell(to)
	if wraps:
		# Continuous across the Date Line; the start is taken in the main copy
		# so the region rectangles are found without wrapping.
		b.x = a.x + fposmod(b.x - a.x + columns * 0.5, columns) - columns * 0.5
		var shift := floorf(a.x / columns) * columns
		a.x -= shift
		b.x -= shift
	return _line_clear_cells(a, b, min_class)


## is_geo_line_clear in this grid's cell coordinates, through the regions.
func _line_clear_cells(a: Vector2, b: Vector2, min_class: int) -> bool:
	for region in regions:
		var clip := _clip(a, b, region.get_base_rect())
		if clip.is_empty() or clip[1] - clip[0] <= 1e-12:
			continue
		# The parts before and after the region are checked here, the part
		# inside in the region's own grid (mirrors build_region.composite_clear).
		var direction := (b - a).normalized()
		var p0 := a.lerp(b, clip[0])
		var p1 := a.lerp(b, clip[1])
		if clip[0] > 0.0 and not is_line_clear(a, p0 - direction * SEAM_NUDGE, min_class):
			return false
		if clip[1] < 1.0 and not is_line_clear(p1 + direction * SEAM_NUDGE, b, min_class):
			return false
		var f0 := region.from_base_cell(p0 + direction * SEAM_NUDGE / region.factor)
		var f1 := region.from_base_cell(p1 - direction * SEAM_NUDGE / region.factor)
		return region._line_clear_cells(f0, f1, min_class)
	return is_line_clear(a, b, min_class)


## A base cell-space point in this region's cells, kept inside the region.
func from_base_cell(point: Vector2) -> Vector2:
	var local := (point - Vector2(base_cell)) * factor
	return Vector2(clampf(local.x, 0.0, columns - 0.001), clampf(local.y, 0.0, rows - 0.001))


## Parametric [t0, t1] of the segment a-b inside `rect` (Liang-Barsky), or [].
static func _clip(a: Vector2, b: Vector2, rect: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for pq: Vector2 in [Vector2(-d.x, a.x - rect.position.x), Vector2(d.x, rect.end.x - a.x),
			Vector2(-d.y, a.y - rect.position.y), Vector2(d.y, rect.end.y - a.y)]:
		if pq.x == 0.0:
			if pq.y < 0.0:
				return []
			continue
		var r := pq.y / pq.x
		if pq.x < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return []
	return [t0, t1]
