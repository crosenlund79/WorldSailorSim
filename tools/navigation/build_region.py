"""Builds a high-detail navigation region (Iteration 14): Denmark first.

A region is a rectangle of the chart with its own, finer data, in the same
geographic coordinates and Mercator raster layout as the base chart
(tools/navigation/build_navigation_data.py), so nothing about positions,
saves or projections changes. The base files are left exactly as they are;
the game consults a region's data wherever it covers and the base elsewhere
(NavGrid, SeaRouter, MapView). More regions (Sweden, New Zealand, French
Polynesia...) are more entries in REGIONS and data/navigation/regions.json.

Input:
  OpenStreetMap land polygons as packaged by geo-maps "earth-lands-100m"
  0.6.0 (npm @geo-maps/earth-lands-100m, GeoJSON, about 100 m accuracy; data
  (c) OpenStreetMap contributors, ODbL 1.0; package code MIT):
      https://registry.npmjs.org/@geo-maps/earth-lands-100m/-/earth-lands-100m-0.6.0.tgz
      (sha1 bcee1e6ce052d9c57bc7a2aa3b39912aaaf43c41), file package/map.geo.json
  The base chart data in data/navigation/ (europe_navmask.*, europe_route_graph.json).

Output, data/navigation/regions/<id>/:
  region.json     bounds (snapped to base raster cells), detail factor, sources, licence, processing
  navmask.png     the fine raster (factor x the base resolution): 255 navigable, 128 approach-only, 0 land
  land.json       display data: "detail" (fine) and "overview" (base-level) fill tiles and coastlines, labels
  graph.json      the region's route graph (nodes in fine cells), plus seam edges to base graph nodes
                  (by their base cell) and the base edges that cross the region and are not clear

Processing: polygons clipped to the region (with a margin), holes filled (lakes and the source's tile-seam
artefacts count as land, as in the base chart), rasterized with the base chart's conservative rule (any land
in a cell makes it land, at 1/4-cell precision; approach water needs a water majority). Display polygons are
simplified (detail 0.0003 deg, overview 0.0035 deg like the base chart; islets below a minimum area dropped
from the display only, never from the raster). Not for navigation.

Requires: python3, numpy, scipy, shapely 2, pillow, scikit-image.
Usage: python3 tools/navigation/build_region.py path/to/map.geo.json path/to/cities.json [denmark]
  (cities.json: lutangar/cities.json, GeoNames cities, CC BY 4.0; used for label positions)
"""
import json
import math
import os
import pickle
import sys
import time
from collections import deque

import numpy as np
import shapely
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.spatial import cKDTree
from shapely.geometry import LineString, MultiLineString, Polygon, box
from shapely.ops import unary_union
from skimage.morphology import skeletonize

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
NAV_DIR = os.path.join(ROOT, "data", "navigation")
SUPERSAMPLE = 4

REGIONS = {
    "denmark": {
        "name": "Danish waters",
        # Denmark with the Øresund, the Kattegat to Gothenburg, the German Baltic coast to
        # Rügen's west and Bornholm. Snapped outwards to base raster cells.
        "west": 8.0, "east": 15.4, "south": 53.8, "north": 58.0,
        "factor": 6,
        "detail_simplify": 0.0003, "detail_min_area": 0.000002,
        "overview_simplify": 0.0035, "overview_min_area": 0.0002,
        "tile_deg": 0.5,
        "labels": "danish_labels.json",
    },
    # Sweden (Regions and Harbours 2026): Bohuslän north of the Danish region (its south edge is
    # Denmark's north edge), and the east coast from Västervik to the Stockholm archipelago and
    # Åland's Sea. Both refine Europe's chart.
    "bohuslan": {
        "name": "Bohuslän",
        "west": 10.9, "east": 12.4, "south": 58.0055, "north": 59.2,
        "factor": 6,
        "detail_simplify": 0.0003, "detail_min_area": 0.000002,
        "overview_simplify": 0.0035, "overview_min_area": 0.0002,
        "tile_deg": 0.5,
        "labels": "swedish_labels.json", "label_group": "bohuslan",
    },
    "swedish_east_coast": {
        "name": "The Swedish east coast",
        "west": 16.3, "east": 19.4, "south": 57.55, "north": 60.0,
        "factor": 6,
        "detail_simplify": 0.0003, "detail_min_area": 0.000002,
        "overview_simplify": 0.0035, "overview_min_area": 0.0002,
        "tile_deg": 0.5,
        "labels": "swedish_labels.json", "label_group": "east",
    },
    # New Zealand refines the world chart (12 cells per Mercator degree) 18 times, to 216: the
    # North Island with Cook Strait, the Marlborough Sounds and Tasman Bay; and the South Island
    # south of them with Stewart Island.
    "nz_north": {
        "name": "New Zealand: North Island and Cook Strait",
        "parent": "world",
        "west": 171.9, "east": 179.0, "south": -41.7, "north": -34.0,
        "factor": 18,
        "detail_simplify": 0.0003, "detail_min_area": 0.000002,
        "overview_simplify": 0.0035, "overview_min_area": 0.0002,
        "tile_deg": 0.5,
        "labels": "new_zealand_labels.json", "label_group": "north",
    },
    "nz_south": {
        "name": "New Zealand: South Island",
        "parent": "world",
        "west": 166.0, "east": 174.6, "south": -47.5, "north": -41.733,
        "factor": 18,
        "detail_simplify": 0.0003, "detail_min_area": 0.000002,
        "overview_simplify": 0.0035, "overview_min_area": 0.0002,
        "tile_deg": 0.5,
        "labels": "new_zealand_labels.json", "label_group": "south",
    },
}

# Graph lattice in fine cells (coarse to fine) and the narrow-water skeleton spacing.
LATTICE = [192, 96, 48, 24, 12]
BAND_OVERLAP = 1.3
SKELETON_GAP = 5
MAX_EDGES_PER_NODE = 12
SEAM_BAND_BASE = 10         # base nodes this close (base cells) to the region are linked to it
SEAM_LINKS = 6


def merc_y(lat):
    return math.degrees(math.log(math.tan(math.pi / 4.0 + math.radians(lat) / 2.0)))


# The chart a region refines: Europe's (European waters) or the world chart (anywhere else,
# e.g. New Zealand; Regions and Harbours 2026). Same Mercator raster layout either way.
PARENTS = {
    "europe": ("europe_navmask.json", "europe_navmask.png", "europe_route_graph.json"),
    "world": ("world/world.json", "world/navmask.png", "world/graph.json"),
}


class Base:
    def __init__(self, parent="europe"):
        meta_file, mask_file, graph_file = PARENTS[parent]
        meta = json.load(open(os.path.join(NAV_DIR, meta_file)))
        self.west = meta["bounds"]["west"]
        self.cpd = meta["cells_per_mercator_degree"]
        self.my_north = meta["mercator_north"]
        mask = np.array(Image.open(os.path.join(NAV_DIR, mask_file)).convert("L"))
        self.mask = mask
        self.rows, self.cols = mask.shape
        graph = json.load(open(os.path.join(NAV_DIR, graph_file)))
        n = graph["nodes"]
        self.nodes = [(n[i], n[i + 1]) for i in range(0, len(n), 2)]
        e = graph["edges"]
        self.edges = [(e[i], e[i + 1]) for i in range(0, len(e), 2)]

    def cell(self, lon, lat):
        return (lon - self.west) * self.cpd, (self.my_north - merc_y(lat)) * self.cpd

    def geo(self, cx, cy):
        lon = self.west + cx / self.cpd
        my = math.radians(self.my_north - cy / self.cpd)
        return lon, math.degrees(2.0 * math.atan(math.exp(my)) - math.pi / 2.0)


class Region:
    def __init__(self, rid, spec, base):
        self.id = rid
        self.spec = spec
        self.k = spec["factor"]
        self.base = base
        self.c0 = int(math.floor((spec["west"] - base.west) * base.cpd))
        self.c1 = int(math.ceil((spec["east"] - base.west) * base.cpd))
        self.r0 = int(math.floor((base.my_north - merc_y(spec["north"])) * base.cpd))
        self.r1 = int(math.ceil((base.my_north - merc_y(spec["south"])) * base.cpd))
        self.cols = (self.c1 - self.c0) * self.k
        self.rows = (self.r1 - self.r0) * self.k
        self.west, self.north = base.geo(self.c0, self.r0)
        self.east, self.south = base.geo(self.c1, self.r1)

    def to_fine(self, lon, lat):
        bx, by = self.base.cell(lon, lat)
        return (bx - self.c0) * self.k, (by - self.r0) * self.k

    def fine_to_base(self, fx, fy):
        return fx / self.k + self.c0, fy / self.k + self.r0


# --- Raster -------------------------------------------------------------------------------

def rasterize(region, polygons):
    s = SUPERSAMPLE
    image = Image.new("1", (region.cols * s, region.rows * s), 0)
    draw = ImageDraw.Draw(image)
    for poly in polygons:
        pts = []
        for lon, lat in poly.exterior.coords:
            fx, fy = region.to_fine(lon, lat)
            pts.append((fx * s, fy * s))
        draw.polygon(pts, fill=1, outline=1)
    fine = np.array(image, dtype=bool).reshape(region.rows, s, region.cols, s)
    land = fine.any(axis=(1, 3))
    approach = fine.sum(axis=(1, 3)) * 2 <= s * s
    return ~land, approach | ~land


# --- Line checks (mirror NavGrid.is_line_clear / NavGrid.is_geo_line_clear) -----------------

def segment_clear(ok, x0, y0, x1, y1):
    rows, cols = ok.shape

    def at(x, y):
        return 0 <= x < cols and 0 <= y < rows and ok[y, x]
    ix, iy = math.floor(x0), math.floor(y0)
    ex, ey = math.floor(x1), math.floor(y1)
    if not at(ix, iy):
        return False
    dx, dy = x1 - x0, y1 - y0
    step_x = 1 if dx > 0 else (-1 if dx < 0 else 0)
    step_y = 1 if dy > 0 else (-1 if dy < 0 else 0)
    t_delta_x = abs(1.0 / dx) if dx != 0 else math.inf
    t_delta_y = abs(1.0 / dy) if dy != 0 else math.inf
    t_max_x = ((ix + 1 - x0) if dx > 0 else (x0 - ix)) * t_delta_x if dx != 0 else math.inf
    t_max_y = ((iy + 1 - y0) if dy > 0 else (y0 - iy)) * t_delta_y if dy != 0 else math.inf
    guard = abs(ex - ix) + abs(ey - iy) + 2
    while (ix != ex or iy != ey) and guard > 0:
        guard -= 1
        if abs(t_max_x - t_max_y) < 1e-9:
            if not at(ix + step_x, iy) or not at(ix, iy + step_y):
                return False
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
        if not at(ix, iy):
            return False
    return True


NUDGE = 0.01  # float32-safe: Godot vectors are single precision


def clip_t(ax, ay, bx, by, x0, y0, x1, y1):
    """Parametric [t0, t1] of segment a-b inside the rectangle, or None (Liang-Barsky)."""
    t0, t1 = 0.0, 1.0
    dx, dy = bx - ax, by - ay
    for p, q in ((-dx, ax - x0), (dx, x1 - ax), (-dy, ay - y0), (dy, y1 - ay)):
        if p == 0:
            if q < 0:
                return None
            continue
        r = q / p
        if p < 0:
            t0 = max(t0, r)
        else:
            t1 = min(t1, r)
        if t0 > t1:
            return None
    return t0, t1


def composite_clear(region, base_ok, fine_ok, ax, ay, bx, by):
    """A line in base-cell coordinates, checked against the fine raster inside the region and
    the base raster outside. Same rules as NavGrid.is_line_clear on the composite grid."""
    clip = clip_t(ax, ay, bx, by, region.c0, region.r0, region.c1, region.r1)
    if clip is None or clip[1] - clip[0] <= 1e-12:
        return segment_clear(base_ok, ax, ay, bx, by)
    t0, t1 = clip
    length = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / length, (by - ay) / length

    def point(t):
        return ax + (bx - ax) * t, ay + (by - ay) * t
    if t0 > 0.0:
        px, py = point(t0)
        if not segment_clear(base_ok, ax, ay, px - ux * NUDGE, py - uy * NUDGE):
            return False
    if t1 < 1.0:
        px, py = point(t1)
        if not segment_clear(base_ok, px + ux * NUDGE, py + uy * NUDGE, bx, by):
            return False
    p0 = point(t0)
    p1 = point(t1)
    f0 = _clamp_fine(region, (p0[0] - region.c0) * region.k + ux * NUDGE, (p0[1] - region.r0) * region.k + uy * NUDGE)
    f1 = _clamp_fine(region, (p1[0] - region.c0) * region.k - ux * NUDGE, (p1[1] - region.r0) * region.k - uy * NUDGE)
    return segment_clear(fine_ok, f0[0], f0[1], f1[0], f1[1])


def _clamp_fine(region, x, y):
    return min(max(x, 0.0), region.cols - 0.001), min(max(y, 0.0), region.rows - 0.001)


# --- Graph (as build_navigation_data.build_graph, on the fine raster) ------------------------

def build_graph(water):
    rows, cols = water.shape
    clearance = ndimage.distance_transform_edt(water)
    nodes = {}

    def add(cx, cy, spacing):
        if (cx, cy) not in nodes:
            nodes[(cx, cy)] = spacing

    for level, spacing in enumerate(LATTICE):
        offset = spacing // 2
        ys, xs = np.mgrid[offset:rows:spacing, offset:cols:spacing]
        c = clearance[ys, xs]
        ok = c >= 0.6 * spacing
        if level > 0:
            ok &= c < 0.6 * LATTICE[level - 1] * BAND_OVERLAP
        for y, x in zip(ys[ok], xs[ok]):
            add(int(x), int(y), spacing)
    skeleton = skeletonize(water) & (clearance < 0.6 * LATTICE[-1] * BAND_OVERLAP)
    ys, xs = np.nonzero(skeleton)
    grid = {}
    for idx in np.lexsort((xs, ys)):
        x, y = int(xs[idx]), int(ys[idx])
        key = (x // SKELETON_GAP, y // SKELETON_GAP)
        near = False
        for gx in (key[0] - 1, key[0], key[0] + 1):
            for gy in (key[1] - 1, key[1], key[1] + 1):
                for (px, py) in grid.get((gx, gy), ()):
                    if (px - x) ** 2 + (py - y) ** 2 < SKELETON_GAP ** 2:
                        near = True
        if not near:
            grid.setdefault(key, []).append((x, y))
            add(x, y, SKELETON_GAP)
    keys = list(nodes.keys())
    pts = np.array([[x + 0.5, y + 0.5] for x, y in keys])
    spacing = np.array([nodes[k] for k in keys], dtype=float)
    tree = cKDTree(pts)
    edges = set()
    for i, (p, s) in enumerate(zip(pts, spacing)):
        candidates = tree.query_ball_point(p, max(2.6 * s, 8.0))
        candidates.sort(key=lambda j: (pts[j][0] - p[0]) ** 2 + (pts[j][1] - p[1]) ** 2)
        made = 0
        for j in candidates:
            if j == i:
                continue
            if made >= MAX_EDGES_PER_NODE:
                break
            a, b = (i, j) if i < j else (j, i)
            if (a, b) in edges:
                made += 1
                continue
            if segment_clear(water, p[0], p[1], pts[j][0], pts[j][1]):
                edges.add((a, b))
                made += 1
    return stitch(water, keys, edges)


def stitch(water, keys, edges):
    """Joins graph pieces lying in the same body of water (see the base builder)."""
    labels, _ = ndimage.label(water)
    index = {k: i for i, k in enumerate(keys)}
    keys = list(keys)
    edges = set(edges)
    parent = list(range(len(keys)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b in edges:
        parent[find(a)] = find(b)

    def add_node(c):
        if c in index:
            return index[c]
        index[c] = len(keys)
        keys.append(c)
        parent.append(len(parent))
        return index[c]
    rows, cols = water.shape
    stitched = 0
    while True:
        groups = {}
        for i, (x, y) in enumerate(keys):
            groups.setdefault((labels[y, x], find(i)), []).append(i)
        by_body = {}
        for (body, root), members in groups.items():
            by_body.setdefault(body, []).append(members)
        todo = [sorted(m, key=len)[0] for m in by_body.values() if len(m) > 1]
        if not todo:
            break
        progressed = False
        for members in todo:
            root = find(members[0])
            start = [keys[i] for i in members]
            prev = {c: None for c in start}
            queue = deque(start)
            target = None
            while queue:
                c = queue.popleft()
                j = index.get(c)
                if j is not None and find(j) != root:
                    target = c
                    break
                x, y = c
                for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= n[0] < cols and 0 <= n[1] < rows and n not in prev and water[n[1], n[0]]:
                        prev[n] = c
                        queue.append(n)
            if target is None:
                continue
            chain = []
            c = target
            while c is not None:
                chain.append(c)
                c = prev[c]
            anchor = 0
            pts = [chain[0]]
            while anchor < len(chain) - 1:
                reach = anchor + 1
                while reach + 1 < len(chain) and segment_clear(water, chain[anchor][0] + .5, chain[anchor][1] + .5,
                                                               chain[reach + 1][0] + .5, chain[reach + 1][1] + .5):
                    reach += 1
                pts.append(chain[reach])
                anchor = reach
            ids = [add_node(c) for c in pts]
            for a, b in zip(ids, ids[1:]):
                if a != b:
                    edges.add((min(a, b), max(a, b)))
                    parent[find(a)] = find(b)
            stitched += 1
            progressed = True
        if not progressed:
            break
    print("stitched", stitched, "graph pieces", flush=True)
    return keys, edges


# --- Display ----------------------------------------------------------------------------

def display_polygons(land, tolerance, min_area):
    simple = land.simplify(tolerance, preserve_topology=True)
    result = []
    for g in getattr(simple, "geoms", [simple]):
        for p in getattr(g, "geoms", [g]):
            if isinstance(p, Polygon) and p.area >= min_area:
                result.append(Polygon(p.exterior))
    return result


def ring(coords):
    out = [[round(x, 5), round(y, 5)] for x, y in coords]
    if len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out


def tiles_and_coast(polygons, region, tile_deg):
    rect = box(region.west, region.south, region.east, region.north)
    tiles = []
    lon = region.west
    while lon < region.east:
        lat = region.south
        while lat < region.north:
            cell = box(lon, lat, min(lon + tile_deg, region.east), min(lat + tile_deg, region.north))
            for poly in polygons:
                if not poly.intersects(cell):
                    continue
                piece = poly.intersection(cell)
                for g in getattr(piece, "geoms", [piece]):
                    if isinstance(g, Polygon) and g.area > 1e-9:
                        r = ring(g.exterior.coords)
                        if len(r) >= 3:
                            tiles.append(r)
            lat += tile_deg
        lon += tile_deg
    coast = []
    for poly in polygons:
        line = LineString(poly.exterior.coords).intersection(rect)
        for g in getattr(line, "geoms", [line]):
            if isinstance(g, LineString) and len(g.coords) >= 2:
                coast.append([[round(x, 5), round(y, 5)] for x, y in g.coords])
    return tiles, coast


def place_labels(spec, cities_path, group=""):
    """Chart labels from town positions (GeoNames via cities.json, CC BY 4.0): a land label at a
    town on that land, a water label halfway between two towns facing each other across it."""
    towns = {}
    for c in json.load(open(cities_path)):
        if c["country"] in spec.get("countries", []):
            towns.setdefault(c["name"], (float(c["lng"]), float(c["lat"])))
    labels = []
    for entry in spec["labels"]:
        if group and entry.get("group", group) != group:
            continue
        at = [towns[t] for t in entry["towns"]]
        lon = sum(p[0] for p in at) / len(at) + entry.get("shift", [0, 0])[0]
        lat = sum(p[1] for p in at) / len(at) + entry.get("shift", [0, 0])[1]
        labels.append({"text": entry["text"], "kind": entry["kind"], "lon": round(lon, 4), "lat": round(lat, 4),
                       "min_px_per_degree": entry.get("min_px_per_degree", 90.0)})
    return labels


# --- Main -----------------------------------------------------------------------------------

def load_land(path, region, cache):
    if os.path.exists(cache):
        return pickle.load(open(cache, "rb"))
    margin = 0.1
    W, S, E, N = region.west - margin, region.south - margin, region.east + margin, region.north + margin
    data = json.load(open(path))
    parts = []
    for poly in data["geometries"][0]["coordinates"]:
        ext = np.asarray(poly[0])
        if ext[:, 0].max() < W or ext[:, 0].min() > E or ext[:, 1].max() < S or ext[:, 1].min() > N:
            continue
        # Holes filled: lakes and the source's tile seams are land, as in the base chart.
        clipped = shapely.clip_by_rect(Polygon(ext), W, S, E, N)
        if clipped.is_empty:
            continue
        if not clipped.is_valid:
            clipped = shapely.make_valid(clipped)
        parts.append(clipped)
    land = unary_union(parts)
    polygons = []
    for g in getattr(land, "geoms", [land]):
        for p in getattr(g, "geoms", [g]):
            if isinstance(p, Polygon):
                polygons.append(Polygon(p.exterior))
    land = unary_union(polygons)
    pickle.dump(land, open(cache, "wb"))
    return land


def main():
    source = sys.argv[1]
    cities_path = sys.argv[2]
    rid = sys.argv[3] if len(sys.argv) > 3 else "denmark"
    spec = REGIONS[rid]
    started = time.time()
    parent = spec.get("parent", "europe")
    base = Base(parent)
    region = Region(rid, spec, base)
    print("region %s: base cells %d..%d x %d..%d, fine raster %d x %d, geo %.4f..%.4f E %.4f..%.4f N" % (
        rid, region.c0, region.c1, region.r0, region.r1, region.cols, region.rows,
        region.west, region.east, region.south, region.north), flush=True)
    land = load_land(source, region, "/tmp/region_%s_land.pkl" % rid)
    raster_polys = [p for p in getattr(land, "geoms", [land]) if isinstance(p, Polygon)]
    print(len(raster_polys), "land polygons,", sum(len(p.exterior.coords) for p in raster_polys), "points", flush=True)

    water, approach = rasterize(region, raster_polys)
    print("raster: water cells", int(water.sum()), "of", water.size, time.time() - started, flush=True)
    out_dir = os.path.join(NAV_DIR, "regions", rid)
    os.makedirs(out_dir, exist_ok=True)
    mask = np.where(water, 255, np.where(approach, 128, 0)).astype(np.uint8)
    Image.fromarray(mask, mode="L").save(os.path.join(out_dir, "navmask.png"), optimize=True)

    keys, edges = build_graph(water)
    print(len(keys), "region graph nodes,", len(edges), "edges", time.time() - started, flush=True)

    # Seam: base nodes near the region link to region nodes they can see (composite line check).
    base_ok = base.mask == 255
    fine_ok = water
    pts = np.array([[x + 0.5, y + 0.5] for x, y in keys])
    tree = cKDTree(pts)
    seam = []
    base_inside = 0
    for bx, by in base.nodes:
        cx, cy = bx + 0.5, by + 0.5
        inside = region.c0 <= cx < region.c1 and region.r0 <= cy < region.r1
        if inside:
            base_inside += 1
            continue
        dx = max(region.c0 - cx, 0.0, cx - region.c1)
        dy = max(region.r0 - cy, 0.0, cy - region.r1)
        if math.hypot(dx, dy) > SEAM_BAND_BASE:
            continue
        fx, fy = (cx - region.c0) * region.k, (cy - region.r0) * region.k
        found = tree.query_ball_point([fx, fy], (SEAM_BAND_BASE + 6) * region.k)
        found.sort(key=lambda j: (pts[j][0] - fx) ** 2 + (pts[j][1] - fy) ** 2)
        made = 0
        for j in found:
            if made >= SEAM_LINKS:
                break
            gx, gy = region.fine_to_base(pts[j][0], pts[j][1])
            if composite_clear(region, base_ok, fine_ok, cx, cy, gx, gy):
                seam.append([bx, by, j])
                made += 1
    # Base edges that cross the region must be clear on the fine raster too.
    blocked = []
    for a, b in base.edges:
        (ax, ay), (bx, by) = base.nodes[a], base.nodes[b]
        ax, ay, bx, by = ax + 0.5, ay + 0.5, bx + 0.5, by + 0.5
        if clip_t(ax, ay, bx, by, region.c0, region.r0, region.c1, region.r1) is None:
            continue
        if not composite_clear(region, base_ok, fine_ok, ax, ay, bx, by):
            blocked.append([base.nodes[a][0], base.nodes[a][1], base.nodes[b][0], base.nodes[b][1]])
    print(len(seam), "seam links,", base_inside, "base nodes inside (replaced),", len(blocked), "crossing base edges blocked",
          time.time() - started, flush=True)

    flat_nodes = []
    for x, y in keys:
        flat_nodes += [x, y]
    flat_edges = []
    for a, b in sorted(edges):
        flat_edges += [a, b]
    json.dump({"note": "Nodes are fine-raster cells (column, row) of this region; seam links are "
                       "[base column, base row, region node]; blocked are base edges [c0, r0, c1, r1] that "
                       "cross the region and are not clear on its raster.",
               "nodes": flat_nodes, "edges": flat_edges, "seam": seam, "blocked_base_edges": blocked},
              open(os.path.join(out_dir, "graph.json"), "w"), separators=(",", ":"))

    detail = display_polygons(land, spec["detail_simplify"], spec["detail_min_area"])
    overview = display_polygons(land, spec["overview_simplify"], spec["overview_min_area"])
    d_tiles, d_coast = tiles_and_coast(detail, region, spec["tile_deg"])
    o_tiles, o_coast = tiles_and_coast(overview, region, 4.0)
    labels = place_labels(json.load(open(os.path.join(os.path.dirname(__file__), spec["labels"]))), cities_path,
                          spec.get("label_group", ""))
    json.dump({"region": rid, "name": spec["name"],
               "detail": {"fill_tiles": d_tiles, "coast": d_coast},
               "overview": {"fill_tiles": o_tiles, "coast": o_coast},
               "labels": labels},
              open(os.path.join(out_dir, "land.json"), "w"), separators=(",", ":"), ensure_ascii=False)
    print("display: detail %d polygons %d points, overview %d polygons %d points" % (
        len(detail), sum(len(p.exterior.coords) for p in detail), len(overview), sum(len(p.exterior.coords) for p in overview)),
          flush=True)

    meta = {
        "id": rid, "name": spec["name"], "parent": parent,
        "source": "OpenStreetMap land polygons via geo-maps earth-lands-100m 0.6.0 (npm @geo-maps/earth-lands-100m, "
                  "about 100 m accuracy). Map data (c) OpenStreetMap contributors, ODbL 1.0, "
                  "openstreetmap.org/copyright. Package code MIT.",
        "retrieved": "2026-10-25",
        "licence": "ODbL 1.0 (derived database: this region's raster, land and graph are ODbL too)",
        "label_source": "Label positions from GeoNames town coordinates (lutangar/cities.json, CC BY 4.0, geonames.org); label texts: tools/navigation/%s." % spec["labels"],
        "crs": "WGS 84 longitude/latitude (EPSG:4326); raster in Mercator rows like the base chart",
        "processing": ("Clipped to the region with a 0.1 deg margin; holes filled (lakes and tile-seam artefacts "
                       "are land); raster at %d cells per Mercator degree (%d x the base), land if any part of a cell "
                       "is land (1/%d cell precision), approach water with a water majority; display simplified "
                       "%.4f deg (detail) and %.4f deg (overview). Not for navigation.") % (
            base.cpd * region.k, region.k, SUPERSAMPLE, spec["detail_simplify"], spec["overview_simplify"]),
        "factor": region.k,
        "base_cells": {"column": region.c0, "row": region.r0, "columns": region.c1 - region.c0, "rows": region.r1 - region.r0},
        "bounds": {"west": region.west, "south": region.south, "east": region.east, "north": region.north},
        "columns": region.cols, "rows": region.rows,
        "cells_per_mercator_degree": base.cpd * region.k,
        "mercator_north": base.my_north - region.r0 / base.cpd,
        "base_west": region.west,
        "detail_from_px_per_degree": 140.0,
    }
    json.dump(meta, open(os.path.join(out_dir, "region.json"), "w"), indent=1, ensure_ascii=False)
    print("done in %.0f s" % (time.time() - started), flush=True)


if __name__ == "__main__":
    main()
