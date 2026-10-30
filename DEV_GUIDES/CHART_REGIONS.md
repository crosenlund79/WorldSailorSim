# Chart regions: the world chart and detailed coastlines (geographic data preparation)

Iteration 14 added the first detailed region (Denmark); Iteration 16 put the
whole world underneath; Regions and Harbours 2026 added Sweden (Bohuslän and
the east coast, regions of Europe) and New Zealand (two regions of the world
chart itself). How the charts fit together, where the data comes
from, how to rebuild it, and how to add another region.

## 1. How it fits together

The game has **one** chart, in geographic coordinates (longitude, latitude,
WGS 84) with Mercator rasters for navigation, nested three deep:

| Layer | Files | Detail |
|---|---|---|
| World (Iteration 16) | `data/navigation/world/` — `world.json`, `navmask.png`, `graph.json`, `europe_link.json`, `land.res` | 12 cells per Mercator degree (about 5 nautical miles); OpenStreetMap coastlines; wraps round at the Date Line; latitudes 72° S to 80° N |
| Base chart | `data/navigation/europe_navmask.png`, `data/navigation/europe_navmask.json`, `data/navigation/europe_route_graph.json`, `data/navigation/europe_land.json` | 60 cells per Mercator degree (about 1 nautical mile); Natural Earth 10m coastlines |
| Regions | `data/navigation/regions.json` lists them; each has a folder such as `data/navigation/regions/denmark/` | finer (Denmark, Bohuslän, the Swedish east coast: 6 times Europe, about 175 m cells; New Zealand north and south: 18 times the world, 216 cells per Mercator degree); OpenStreetMap coastlines |

Europe is a region of the world chart (one world cell is 5 × 5 European
cells) and Denmark is a region of Europe (one European cell is 6 × 6 Danish
cells), as are Bohuslän and the Swedish east coast. New Zealand's two regions
are regions of the world chart ("parent": "world" in `regions.json`; one world
cell is 18 × 18 of theirs).
A region is a rectangle of its parent chart, its edges on parent raster cells, with
its own raster, route graph and drawing, in the **same coordinates**. Nothing
about positions, saves or projections changes, and the base files stay exactly
as they were: outside the regions the game is unchanged.

- **Navigation** (`src/navigation/nav_grid.gd`): `NavGrid.grid_at()` answers
  with the finest chart covering a position. Point and line checks
  (`cell_class_at_geo`, `is_geo_line_clear`) cut a line where it crosses a
  region's edge and check each part on its own chart.
- **Routes** (`src/navigation/sea_router.gd`): the region's graph replaces the
  base graph nodes inside it; seam edges join the two; base edges that cross
  the region but are not clear on the detailed chart are dropped. Harbour
  approaches are searched in the finest chart.
- **Drawing** (`src/navigation/map_view.gd`): the base land is clipped away
  inside each region; the region draws a light **overview** outline when zoomed
  out and its **detailed** coastline once the chart is zoomed in past
  `detail_from_px_per_degree` (in `region.json`). Region labels appear at their
  own zoom. A region of the world chart (New Zealand) is drawn over the world's
  own land: its rectangle of water first, then its land, in detail wherever the
  world's regional land shows (`detail_from_px_per_degree` 0). A fill ring the
  renderer cannot triangulate is split into quarters, not dropped.
- **Anchoring, fishing, the hat's open water** read the same composite chart
  (`src/anchor/anchor_site.gd`, `src/fishing/fishing_catalog.gd`,
  `src/hat/hat_story.gd`), so they see the detailed coast too.
- **Saves**: a position saved under an older, coarser chart that the detailed
  chart places on land is moved to the nearest open water when the game is
  loaded, and the course is re-planned from there (`GameSession._recover_location`).
  The vessel is never stranded or erased; a notice tells the player.

## 2. The world chart (Iteration 16)

| | |
|---|---|
| Land | The same OpenStreetMap land polygons as the Danish region (geo-maps *earth-lands-100m* 0.6.0, below), the whole world. Retrieved 2026-10-25. |
| Licence | Map data © OpenStreetMap contributors, **ODbL 1.0**. The world raster, graph and land are derived databases and are ODbL too. |
| Coordinates | WGS 84 longitude/latitude (EPSG:4326); raster rows in Mercator, aligned cell for cell with the European chart (one world cell = 5 × 5 European cells). |
| Extent | All longitudes (the raster's columns wrap at ±180°); latitudes 72° S to 80° N. Beyond that the chart is not sailable: the polar limit is documented in `world.json` and kept by the raster. |
| Resolution | 12 cells per Mercator degree, about 5 nautical miles at the equator: an **ocean** chart, deliberately coarser than Europe (1 nm) and Denmark (175 m). Narrow passages smaller than a few cells are closed at this scale. |
| Panama | A **gameplay abstraction**: a straight two-cell channel between the UN/LOCODE positions of Colón (PA ONX) and Panama City (PA PTY), so the Pacific can be reached. Not the canal's geometry, locks or rules. |
| Drawn land | Simplified per zoom: an overview (0.08°, shown below 9 px per degree, where it is under a pixel) for the whole world and a regional layer (0.02°) once zoomed in; small islands below the drawing's limit are shown as islet dots. Europe draws its own land from 9 px per degree on. |

**Not in the data**: depths, reefs, shoals, currents, ice, shipping lanes,
harbour layouts. Harbours abroad are UN/LOCODE town positions. Not for
navigation.

### Date Line and wrapping

- Positions are stored with longitudes in −180..180. A route path is a list of
  such points; a segment whose ends differ by more than 180° crosses the Date
  Line and is sailed **the short way** (`GeoMath.wrap_delta`, used by every
  distance, bearing and interpolation). Saved paths may also carry longitudes up
  to ±540° (continuous paths); waypoints stay within ±180°.
- The raster's columns wrap (`NavGrid.wraps`): line checks across the Date Line
  continue on the other side. The router plans on a sphere (A* on 3-D unit
  vectors), so there is no seam and no antipode problem.
- The chart draws the land again one world-width east and west near the edges,
  and markers, labels, courses and the wind at the copy nearest the view, so the
  Pacific looks continuous.

### Routing

- The world graph is a coarse lattice plus channel centre lines, built against
  the world raster and (inside Europe) the European raster. Europe's own graph
  (and Denmark's) replace the world nodes inside them; seam edges join them.
- Every edge is validated by the same line check the game uses, at build time
  and in `tests/suites/test_routing.gd`.
- Harbour approaches scale with the chart's cell size: 10 nm in Europe, six
  world cells (30 nm) abroad (`SeaRouter.approach_radius_nm`).
- A route that cannot be found fails with a message (`SeaRouter.plan_route`),
  never a straight line over land.

## 3. The Danish data

| | |
|---|---|
| Land | OpenStreetMap land polygons as packaged by geo-maps *earth-lands-100m* 0.6.0 (npm `@geo-maps/earth-lands-100m`, GeoJSON, about 100 m accuracy), file `package/map.geo.json`, SHA-1 of the package `bcee1e6ce052d9c57bc7a2aa3b39912aaaf43c41`. Retrieved 2026-10-25. |
| Licence | Map data © OpenStreetMap contributors, **ODbL 1.0** (openstreetmap.org/copyright). The region's raster, land and graph are derived databases and are ODbL too. The package's own code is MIT. |
| Labels | Town positions from GeoNames (lutangar/cities.json, **CC BY 4.0**), only to place the chart's island and water names; texts in `tools/navigation/danish_labels.json`. |
| Coordinates | WGS 84 longitude/latitude (EPSG:4326); raster rows in Mercator like the base chart. |
| Region | 8.0–15.4° E, 53.8–58.0° N, snapped outwards to base cells: Denmark, the Øresund, the Kattegat to Gothenburg, the German Baltic coast to Rügen's west, Bornholm. |

Processing (`tools/navigation/build_region.py`): the polygons are clipped to the
region with a 0.1° margin; holes are filled (lakes and the source's tile-seam
artefacts count as land, as in the base chart); the raster uses the base
chart's conservative rule (any land in a cell makes it land, at 1/4-cell
precision; approach-only water needs a water majority). The route graph is a
lattice that gets finer near the coast plus the centre lines of narrow water,
so narrow sounds get nodes. The drawn coastline is simplified (detail 0.0003°,
overview 0.0035°); tiny islets are dropped from the drawing only, never from
the raster.

**What it is not**: there are no depths, buoys, shoals, rocks, shipping lanes,
tides or harbour layouts. Harbours are gameplay positions near their towns.
The chart is for a cozy game, not for navigation.

## 4. Rebuilding the world chart

```
python3 tools/navigation/build_world.py path/to/map.geo.json
godot --headless --path . --script tools/navigation/world_land_to_res.gd
```

The first writes `world.json`, `navmask.png`, `graph.json`, `europe_link.json`
and `land.json` into `data/navigation/world/` (about 80 seconds); the second
turns `land.json` into the binary `land.res` the chart loads. `land.json`
(about 13 MB) is not kept in the repository; `land.res` is. Both steps are
deterministic. The Europe chart must exist first (the world build reads
`europe_navmask.png` and `europe_route_graph.json` for the seams). The world
harbours are added with `tools/navigation/add_world_harbours.py` (UN/LOCODE
code list) and `tools/navigation/build_harbours.py`, see
[HARBOURS.md](HARBOURS.md).

## 5. Rebuilding the Danish region

You need python3 with numpy, scipy, shapely 2, pillow and scikit-image, and the
two source files (they are not kept in the repository):

1. `map.geo.json` from
   `https://registry.npmjs.org/@geo-maps/earth-lands-100m/-/earth-lands-100m-0.6.0.tgz`
   (unpack; check the SHA-1 above).
2. `cities.json` from the lutangar/cities.json project (GeoNames cities).

```
python3 tools/navigation/build_region.py path/to/map.geo.json path/to/cities.json denmark
```

It writes `region.json`, `navmask.png`, `land.json` and `graph.json` into the
region's folder in about 12 seconds, and prints the graph and seam figures.
The build is deterministic: the same inputs give the same files. Then run the
tests (`tests/suites/test_routing.gd`, `tests/suites/test_regions.gd`,
`tests/suites/test_harbours.gd`); they check that every graph edge is clear,
that routes stay off the drawn land, and that every harbour has an approach.

## 6. Adding another region

A detailed region (for example Sweden, New Zealand or French Polynesia) is a
rectangle of its parent chart: a European region (like Denmark) inside the
Europe rectangle, any other region directly in the world chart.

1. Add an entry to `REGIONS` in `tools/navigation/build_region.py`: a name, the
   bounds, the detail factor (6 for Denmark; keep the fine raster below about
   3,000 × 3,000 cells), the simplification and a labels file like
   `tools/navigation/danish_labels.json`.
2. Build it as above, with land data that covers it and whose licence you
   record in the region's `region.json` (the script writes the source and
   licence fields; change them if your source differs).
3. Add the folder to `data/navigation/regions.json`.
4. Regions must not overlap. A region outside Europe becomes a region of the
   world chart: its edges on world cells (12 per Mercator degree) and its
   factor relative to the world (for example 12 for one-mile cells). Charts
   nest recursively in the code (`NavGrid.grid_at`, `SeaRouter._merge`), but
   a world-level region is written with `"parent": "world"` in its `REGIONS`
   entry (the builder then aligns it to world cells and seams it to the world
   graph) and listed with `"parent": "world"` in `regions.json`;
   `NavGrid.load_world` attaches it beside Europe (New Zealand is the example).
5. Run the tests. Add harbours for the region as described in
   [HARBOURS.md](HARBOURS.md).

### Detailed Cruising Regions

A detailed chart is navigation data. A **Detailed Cruising Region** (Denmark —
Home Waters, Sweden — The Archipelagos, New Zealand — The Long White Cloud) is
the player-facing idea built on it: an area with more local harbours,
anchorages and coastal destinations. They are data too:
`data/cruising/regions.json` (names, info texts, outlines, the chart's mark,
the waterfront look, the detail charts that cover it) and
`data/cruising/destinations.json` (built by `tools/navigation/build_cruising.py`
from `tools/navigation/cruising_destinations.csv`; candidates left out, with
the reason, in `cruising_destinations_omitted.csv`). Every destination is
checked against the game's own charts with `tools/qa/check_destinations.gd`
before it is imported. `CruisingRegions` (`src/navigation/cruising_regions.gd`)
answers which region a harbour belongs to, what kind of destination it is and
its metadata for I028. Another region is another entry in both files, its
destinations rows in the CSV and, if its coast needs it, a detail chart above.

## 7. Performance

Measured by `tests/suites/test_regions.gd` (headless; see the Iteration 14
report for the figures): navigation with the region loads in well under a
second, a route through Danish waters plans in a few milliseconds, and the
chart switches between the overview and the detailed layer in a fraction of a
millisecond. The detailed coastline is drawn in 0.5° tiles so that only the
visible ones cost anything.

The world chart (Iteration 16, see `docs/benchmarks/`): the worldwide router
loads in under a second (about 54,000 nodes with Europe and Denmark merged), a
route from Copenhagen to Tahiti plans in well under 100 ms, the chart draws the
world in 10° tiles shown only when in view, and the drawn land is loaded once
from the binary `land.res` and cached.
