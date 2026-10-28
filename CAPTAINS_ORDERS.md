# Captain's Orders

The standing decisions of the Captain (the project owner) for
**Little Captain's Hat**. Implementation follows these; when an assignment
and this file disagree, the newer, explicit instruction from the Captain wins,
and this file is updated to match.

Only decisions the Captain has actually given belong in the authoritative
section. Notes added by developers are kept apart and marked as such.

*Small boat. Wide world. Hold onto your hat.*

## Authoritative: Captain-approved decisions

### The game

- **Name and tagline.** The game is *Little Captain's Hat* (developed as *Next
  Harbor* up to Iteration 006). Tagline: *Small boat. Wide world. Hold onto
  your hat.*
- **Cozy first.** A cozy sailing adventure about making a home on the water and
  exploring the world at your own pace. Coziness is the primary design
  principle.
- **Visual direction (Operation Real Horizon, this repository).** An
  illustrated, atmospheric sailing simulator: visual realism 7/10, "Illustrated
  Mariner × Atmospheric Sailing Simulator", natural subdued sea colours,
  believable boats, harbours and cabins, and a modern marine-electronics
  interface. Entirely 2D; hand-illustrated character kept, no glossy
  photorealism. Same gameplay; the creator-owned artwork pipeline is preserved;
  one coherent visual identity. (Supersedes the earlier warm storybook
  direction for this experimental fork; see DEV_GUIDES/ART_DIRECTION.md.)
- **The Captain's artwork** is never overwritten.

### The fleet

- Official boat names, with internal ids that never change:

  | Name | Internal id | Note |
  |---|---|---|
  | Arctic Wanderer 26 | `arctic_wanderer_26` | starter boat for every new game |
  | Wing 33 | `starling_33` | formerly Starling 33 |
  | Clam 40 | `halcyon_40` | formerly Halcyon 40 |
  | Frogleap 36 | `petrel_36` | formerly Petrel 36 |

- Existing saves keep their boats, condition and progression.
- Interiors have one level only, on every boat.

### Iteration 12, A Little Harbour Life (revision build)

- **Iteration 12 is a revision build.** It makes the existing sailing and harbour
  experience more natural and inviting. It does not start the next major
  feature.
- **Revisions are the preferred rhythm** when an iteration's acceptance trial
  reveals meaningful findings.
- **Real objects instead of circles.** Real graphical interaction targets
  replace large visible activation circles: the object itself is highlighted.
  The interaction areas stay generous, and are visible only through developer
  tools.
- **Gangplank and shore access are approved.** The captain walks over a
  gangplank onto the pontoon, where the harbour's services stand.
- **Harbour facilities are data-driven and optional.** Not every harbour has
  every service. Where a harbour has no entry of its own, the existing
  behaviour (every service) remains the default.
- **Copenhagen has a boatyard** (and groceries and Go Ashore).
- **Lohals has no boatyard** in our game.
- **Go Ashore is deliberately lightweight**: small harbour events with modest
  consequences. It is not a town-exploration game: no NPC pathfinding,
  dialogue trees, quests, shop inventories, new currencies, factions,
  walkable villages, generated stories or event chains.
- **Hat loss must be clear without audio.** The loss and the risk before it
  are visible and readable with the sound muted.
- **Course-aligned boat rendering, attempted conservatively.** Technical
  stability and existing save compatibility take priority over forced visual
  changes.

### Iteration 13, The Catch & The Cove

The Captain has approved:

- **Iteration 13, The Catch & The Cove**, version 0.101a, the next feature
  milestone after the Iteration 12 sea trial.
- **Fishing, cooking and anchoring as one connected gameplay experience**:
  sail, fish, find shelter, anchor, cook, rest, continue the voyage.
- **Fishing with manageable equipment and regional fish**: one basic rod,
  four lure families with modest differences, stationary fishing and
  trolling, fair and readable bites and tension.
- **A five-catch trophy display** in the cabin.
- **Lightweight galley cooking** using catches and groceries; no hunger,
  nutrition or mood simulation.
- **Coastal anchoring**: scope, holding, dragging and wake-up alarms, with a
  conservative suitability model that invents no depths.
- **Cozy progression built on the existing renown and Captain's Log
  systems**, not new currencies.
- **Replacement of the old cat and dog in-game graphics** with illustrations
  in the game's established style. (The Captain's original drawings are kept.)
- **Companion interactions use the current highlight system.**
- **No visible activation circles**, anywhere, including the new stations.
- **An eight-directional boat display** rather than continuous
  arbitrary-angle presentation.
- **Accurate underlying navigation and sailing physics**: only the picture is
  in eight directions.
- **Intuitive movement controls** at every orientation.
- **Strict preservation of existing game systems.**
- **Revision iterations remain the preferred follow-up** to significant
  playtest findings.

### Iteration 14, A Bigger World, a Better Boat

The Captain has authorized:

- **Iteration 14, A Bigger World, a Better Boat**, combining two scopes:
  **Boat Care & Equipment** and **Detailed Denmark & Regional Sailing
  Expansion**. Version 0.102a, save format 12.
- **Detailed Denmark**: recognizable coastlines, islands, the Belts and the
  Øresund, keeping the existing chart and one coherent coordinate system. The
  data source, its version or date, licence, coordinate system,
  simplification, scripts and limitations are documented.
- **A reusable regional architecture**, so that later regions (for example
  Sweden, New Zealand, French Polynesia) can be added; level of detail by
  zoom; performance stays responsive. (Those later regions are not part of
  this iteration.)
- **Navigation stays sound**: routes avoid land, harbours stay reachable,
  approaches are coherent, and the eight-direction view stays intact.
- **Harbours**: Copenhagen keeps its boatyard; Lohals keeps no boatyard.
  Facility metadata (groceries, boatyard, haul-out, Go Ashore) and tiers
  (small, larger, major) are optional; not every small harbour gets a
  boatyard.
- **No invented geography**: coastlines are not drawn from memory; no
  depth soundings, buoys, shoals, rocks, shipping lanes, tide tables or real
  marina layouts are invented; no online map tile service is used as an
  undisclosed runtime dependency.
- **Boat care extends the existing condition system** (no duplicate):
  hull, engine, rig and equipment; slow, predictable wear; a readable
  overview with cosmetic / recommended / necessary levels.
- **Boatyards show only the services they offer.** The haul-out is a small,
  satisfying event (options, costs, game time passing, a Captain's Log note).
  A harbour without a yard offers no interaction and charges nothing. Costs
  and time scale with the damage and the boat's size.
- **Four to eight equipment upgrades with real effects**; no pay-to-win, no
  tech tree; the Arctic Wanderer stays a small boat.
- **Passage Readiness is advisory, never gating**: condition, provisions,
  weather, route length and the vessel, in human-friendly words.
- **Fishing and anchoring use the new geography**; cooking and provisions are
  recognized; interactions use illustrated highlights, no circles.
- **Saves migrate from format 11**; a saved position that the new chart
  places on land is recovered safely: the vessel is never stranded or erased.

### Revision 0.102b, Life at Anchor

The Captain has approved:

- **A small revision build after Iteration 14** (version 0.102b), not a new
  numbered iteration: a compact cozy ambience pass.
- **Life at Anchor** as a cozy ambience feature: a safely anchored boat feels
  quiet, safe and lived-in (a gentle evening atmosphere, companions that
  visibly settle, a few short, sparing atmospheric lines, a slightly special
  wake-up at anchor), built on the existing systems.
- **Morning Coffee** as a lightweight galley ritual: no beverage system,
  stat, inventory, economy or farmable reward.
- **No major new mechanics** in this revision.
- **No change to the roadmap's next major iteration: Iteration 15 remains
  reserved for the planned performance and stability pass.**

### Iteration 16, The World Awaits

The Captain has approved:

- **Iteration 16 is The World Awaits** (version 0.103a): global sailing and
  international passages are **authorized**. The player can open a world
  chart, plan sensible voyages to harbours abroad, make long passages and
  stop at harbours on the way.
- **Iteration 15 was not delivered.** The Captain authorized Iteration 16 to
  start on the 0.102b baseline, with performance measured first (before and
  after, in `docs/benchmarks/`). Iteration 15 is recorded as skipped; whether
  its performance and stability pass is rescheduled is the Captain's call.
- **Denmark remains the detailed foundation.** Other detailed regions
  (Sweden, New Zealand, French Polynesia, …) are future work, documented in
  `DEV_GUIDES/CHART_REGIONS.md`, not built now.
- **The global chart is intentionally lower resolution** (about 5 nm cells,
  an ocean chart), from real, licensed, documented data (OpenStreetMap land,
  ODbL). No fabricated coastlines; no depths are claimed.
- **The existing simulation is used, not teleportation.** Long Passage time
  lets hours pass per second on the same timeline and stops by itself when
  something needs the captain.
- **Passage Readiness remains advisory**; beyond the forecast horizon it says
  that the weather is not yet known.
- **Small boats remain valid**: every boat can stow passage stores (32 to 45
  days), and island harbours break up the oceans.
- **Cozy activities remain central**: fishing, cooking, anchoring, the
  companions, the hat, sleep, Life at Anchor and coffee, the log, renown,
  maintenance and Go Ashore all work abroad.
- **Performance and save compatibility are mandatory**: save format 12 is
  unchanged; older saves load.
- **No visible activation circles**; the **eight-direction view and the
  precise physics are preserved**.

### Iteration 17, Let There Be Light

The Captain has approved:

- **Iteration 17 is Let There Be Light** (version 0.104a, save format 12
  unchanged). **Cozy lighting is a defining requirement**: day and night
  change gradually, warm lamps light the cabin, the deck is lit practically
  and the harbour lights welcome the boat home.
- **Three navigation experiences are approved**, each with its own purpose:
  - the **cabin world map** is for exploration and dreaming (voyage
    daydreams change nothing);
  - the **navigation station** (the chart table) is for practical regional
    planning;
  - the **cockpit chartplotter** is for immediate sailing.
- **All three use the existing authoritative worldwide navigation system**
  (the same chart, harbours and router). **Worldwide route distance must
  never be artificially restricted by the chart display size.**
- **The world map has no live wind or weather overlay.**
- **Wind visualization is optimized through profiling, caching and
  appropriate sampling** (cached model snapshots, zoom-appropriate density,
  no wind detail at whole-world zoom).
- **Actual sailing weather remains deterministic and coherent worldwide**;
  the overlay only displays it.
- **Wind forecasts are read-only model previews**: previewing never moves
  the boat or the clock, and forecasts are labelled as estimates.
- **Save/load underway must keep the Captain aboard**, where they stood.
- **Boat visuals must reflect the heading while outside** (the deck view
  turns when the course changes).
- **The action-wheel shortcut must appear in the bottom help panel.**
- **Lighting, weather audio and storm presentation are prioritized.**
- **No giant visible activation circles**; the eight-direction view and the
  precise physics are preserved.
- **Iterations 18–21 remain separately scoped** (I018 The Joy of the
  Journey, I019 The Captain's Watch, I020 A Boat of Your Own, I021 The
  Well-Trimmed Ship) and were not started. The cabin wall map is authorized
  as a navigation feature and does not authorize the rest of I020.
- **Difficulty levels remain deferred.**
- **Windows acceptance must not be claimed without the Captain's test.**

### Iteration 18, The Joy of the Journey

The Captain has approved (version 0.105a, save format 12 unchanged; new
fields are optional):

1. **Fishing 2.0 uses a constant-speed circular timing interaction**: a
   needle sweeps a dial at a steady speed and the captain presses inside a
   highlighted arc.
2. **Rarity determines the challenge, not the weight grade** (more
   successful presses and a narrower arc for rarer fish).
3. **Perfect hits influence specimen quality modestly** (a small nudge to
   the landed weight; skill matters, luck is not replaced).
4. **Each supported fish species needs recognizable illustrated artwork.**
5. **Prominent fish visuals occasionally blink and flick their tails.**
6. **Fish art and animation must be lightweight and reusable** (a few small
   layered images per species; Reduce motion stills them).
7. **Keep preferences filter by rarity and specimen size** (grade).
8. **Released fish are excluded from trophy records.**
9. **Sharks are released** and are not edible or sellable inventory.
10. **Junk catches are occasional and worthless.**
11. **Sail Trim is optional and offers modest efficiency benefits**
    (leaving it to the crew sails as before).
12. **Long Passage must remain faithful to normal simulation** (fewer
    interruptions, never different outcomes).
13. **A waypoint can be marked as an anchorage.**
14. **Reaching an anchorage stops the route leg and prompts for normal
    manual anchoring** (the anchor is never set by itself).
15. **The Captain must never be routed onto land by an anchorage
    waypoint.**
16. **A black anchor ball appears at anchor in daylight.**
17. **The appropriate white anchor light appears at night.**
18. **A modest buoy or rode makes anchoring visually evident.**
19. **The pet can join the Captain outside while safely moored or
    anchored.**
20. **Pet behaviour must remain safe on all four vessels.**
21. **The I017 world-route display defect is a required carry-forward
    fix.**
22. **Cabin light contrast and exterior navigation lights receive
    refinements.**
23. **Wind forecast intervals should be useful, not arbitrarily short.**
24. **Iterations 19–21 remain separate** (I019 The Captain's Watch, I020 A
    Boat of Your Own, I021 The Well-Trimmed Ship) and were not started.
25. **No selectable difficulty mode is introduced.**

### Revision 0.105b, Safe Harbours, Deep Waters & the Sprite Workshop

The Captain has approved (version 0.105b, save format 12 unchanged; new
fields are optional):

1. **Worldwide anchoring is a required gameplay capability.**
2. **The coarse global chart must not prohibit all international
   anchorages.**
3. **Real bathymetry is preferred where appropriate.**
4. **Game-estimated depths are permitted when transparent, deterministic
   and coherent.**
5. **The game does not claim navigation-grade depth accuracy.**
6. **Normal anchoring remains useful worldwide.**
7. **Anchorage suitability is separate from land avoidance.**
8. **Shelter/exposure is separate from depth.**
9. **Zoom-dependent chart highlights show eligible anchoring areas.**
10. **Overlay computation must be visible-area-only and cached.**
11. **Anchorage waypoints must use the existing navigation system.**
12. **The Magic Anchor is approved as fictional equipment.**
13. **The Magic Anchor can overcome excess or uncertain depth.**
14. **It can support appropriate deep/offshore emergency deployment.**
15. **It does not overcome land, impassable geography or weather
    exposure.**
16. **Magic Anchor deployment uses a fair skill check.**
17. **Successful special deployment uses the existing anchor holding
    model.**
18. **The Captain's existing anchor ball, light, rode and buoy remain.**
19. **Sprite Workshop Phase 1 is approved.**
20. **Every relevant artwork folder contains a CSV list of expected
    replacement files and written instructions.**
21. **Artwork targets 2× normal display resolution.**
22. **Inventory reports unique designs separately from static directional
    drawings.**
23. **Artwork is classified by complexity and expected resolution.**
24. **Assets are ranked by hand-drawing priority.**
25. **Valid installed replacement PNGs automatically override current
    artwork.**
26. **Missing or invalid replacements safely fall back to existing
    visuals.**
27. **The original Captain-owned artwork is preserved.**
28. **Full Windows acceptance will follow this revision.**
29. **I019–I021 remain independently scoped and are not cancelled.**
30. **Successfully anchoring automatically stops the engine; the engine
    remains off until the Captain raises the anchor and chooses to start
    it.**
31. **All four boats receive decorative solar panels. No electrical,
    battery, charging or power-management mechanics are authorized.**

### Iterations and versions

- Iteration numbers are plain sequential integers: no letter suffixes and no
  sub-iteration numbers. Minor correction prompts belong to their parent
  iteration. One commissioned implementation assignment is one iteration.
- Game version numbers are separate from iteration numbers. They follow
  0.<milestone><letter>: 0.100a, 0.100b (fixes and refinements within a
  milestone), 0.101a (the next feature milestone), 0.200a (a large step).
- The save format has its own version, changed only when persistent game state
  genuinely requires it.

### Working rules

- Only the repository `crosenlund79/LittleCaptainsHat` is worked on. The archived
  Next Harbor repository and unrelated projects are never edited.
- Use recoverable checkpoint commits. Never reset, force-push or discard work.
- A delivery states the version, the final commit, the branch, the report and
  the Windows checklist, and ends with the clickable branch link (mandatory).
- The Captain's own workflow is: GitHub branch → Code → Download ZIP → extract →
  open `project.godot` in Godot → run. A Windows executable is not made unless
  asked.
- Testing is focused and proportionate: no inflated test counts for cosmetic
  details. A suite that was skipped is reported as skipped. Windows acceptance
  is claimed only after the Captain's own trial.
- **Performance register (Turbocharge).** Every iteration that measures or
  changes performance updates `docs/technical/PERFORMANCE_OPPORTUNITIES.md`:
  new evidence, status changes, implemented items with their commit and
  measured benefit. Verified bottlenecks and hypotheses stay separate; large
  reworks are recorded for the Captain's decision, never done silently.
- **GDScript guides (the Engine Room).** Every `.gd` file has one entry in each
  of `docs/technical/GDSCRIPT_GUIDE_EN.md`, `GDSCRIPT_GUIDE_DA.md` and
  `GDSCRIPT_ARCHITECTURE.md`. Creating or removing a script: add or remove its
  entry in all three. Materially changing a script: review its three entries
  and correct what is out of date (only those entries; never regenerate a
  whole guide for a small change). Then run
  `python tools/docs/check_gdscript_guides.py` and record the review with
  `--acknowledge PATH --note "..."`; a delivery leaves the checker passing.
  The code is the authority: a stale entry is fixed, never trusted.

### Not now

These remain separately approved future assignments; they are not started
early:

- further detailed regions (the architecture allows them; Denmark is the only
  one built). The worldwide chart itself was commissioned as Iteration 16.

(Fishing and anchoring, listed here until Iteration 12, were commissioned by
the Captain as Iteration 13. Maintenance and equipment, listed here until
Iteration 13, were commissioned as part of Iteration 14.)

## Phase One and Phase Two

The Captain distinguishes the **current authorized development scope** (Phase
One) from a **locked future Phase Two**. The precise wording of the Phase Two
policy is **still not written down in this repository** (checked again in
Iterations 13 and 14), so it is not restated or guessed here. It stays in
force exactly as the Captain defined it; the scope freeze holds.

What is established by the Captain's current authorization: Iterations 13,
14 and 16 are within the current scope; they do not reopen or expand Phase
Two. Iteration 14 added one detailed region and boat care as authorized.
Iteration 16 adds global sailing and international passages, which the
Captain explicitly authorized; it does not invent Phase Two wording or reopen
Phase Two (the wording was again not found in the repository in Iteration 16).
Iteration 17 (lighting, atmosphere, navigation views) is likewise within the
Captain's authorization and does not reopen Phase Two; the wording was again
not found in the repository in Iteration 17.
Iteration 18 (fishing, sail trim, anchorages, the pet on deck, refinements)
is likewise within the Captain's authorization and does not reopen Phase
Two; the wording was again not found in the repository in Iteration 18.
*Developer note: please add the Phase Two wording here.*

## Iteration log

- Iterations 001–006: built as *Next Harbor* (see the iteration reports).
- Visual Identity V01, version 0.100a: see `docs/revisions/v0.100a/VISUAL_IDENTITY_V01_REPORT.md`.
- A Living Little World, version 0.100b: see `docs/revisions/v0.100b/VISUAL_POLISH_0100B_REPORT.md`.
- **Iteration 12, A Little Harbour Life**, version 0.100c: an authorized revision
  build; see `docs/iterations/i012/ITERATION_12_REPORT.md` and `docs/iterations/i012/WINDOWS_ACCEPTANCE_12.md`.
- **Iteration 13, The Catch & The Cove**, version 0.101a: fishing, the galley,
  anchoring, the new cat and dog and the eight-direction sailing view; see
  `docs/iterations/i013/ITERATION_13_REPORT.md` and `docs/iterations/i013/WINDOWS_ACCEPTANCE_13.md`.
- **Iteration 14, A Bigger World, a Better Boat**, version 0.102a, save format
  12: detailed Denmark as the first regional chart, Danish harbours with
  service tiers, boat care, boatyard services and haul-outs, equipment and
  Passage Readiness; see `docs/iterations/i014/ITERATION_14_REPORT.md` and
  `docs/iterations/i014/WINDOWS_ACCEPTANCE_14.md`.
- **Revision 0.102b, Life at Anchor**: a cozy revision after Iteration 14
  (life at anchor, morning coffee; save format unchanged); see
  `docs/revisions/v0.102b/REVISION_0_102B_REPORT.md` and `docs/revisions/v0.102b/WINDOWS_SMOKE_0_102B.md`. Iteration 15 is
  reserved for the performance and stability pass.
- **Iteration 16, The World Awaits**, version 0.103a, save format 12
  (unchanged): a worldwide chart on OpenStreetMap land with Date Line
  wrapping, worldwide routing, 36 international harbours (Atlantic islands,
  the Caribbean, Panama, the Pacific, New Zealand), Long Passage time,
  passage stores, global wind and ocean weather, and the Captain's Log firsts
  of the voyage abroad; see `docs/iterations/i016/ITERATION_16_REPORT.md` and
  `docs/iterations/i016/WINDOWS_ACCEPTANCE_16.md`. Iteration 15 (the performance and stability
  pass) was skipped at the Captain's instruction.
- **Iteration 17, Let There Be Light**, version 0.104a, save format 12
  (unchanged): day and night lighting with warm cabin lamps, deck and harbour
  lights and soft shadows; weather sound with thunderstorms and muffled
  cabin acoustics; the cabin world map with voyage daydreams, the regional
  navigation station and the cockpit chartplotter; the world-chart rendering
  fix and the cached wind overlay with time previews; the deck turning with
  the course, the sail above the captain, fenders stowed underway, the
  sailing panel, the action wheel, F5/F9 quicksave, harbours by country and
  the docking arrival; see `docs/iterations/i017/ITERATION_17_REPORT.md` and
  `docs/iterations/i017/WINDOWS_ACCEPTANCE_17.md`.
- **Iteration 18, The Joy of the Journey**, version 0.105a, save format 12
  (unchanged; optional new fields): Fishing 2.0 with the circular reel-in
  dial, illustrated fish that blink and flick their tails, weight grades,
  keep preferences, sharks and junk, fishing at anchor; Sail Trim; fewer
  Long Passage stops; anchorage waypoints with the arrival question; the
  anchor ball, anchor light, rode and buoy; the companion following the
  captain on deck; cabin light contrast, navigation lights on the rail and
  1-hour wind forecast steps; the world-route panning fix; see
  `docs/iterations/i018/ITERATION_18_REPORT.md` and `docs/iterations/i018/WINDOWS_ACCEPTANCE_18.md`.
- **Revision 0.105b, Safe Harbours, Deep Waters & the Sprite Workshop**,
  version 0.105b, save format 12 (unchanged; optional new fields): anchoring
  worldwide on a fine coastal raster with game-estimated depths (labelled
  GAME ESTIMATE), shelter judged separately, the zoom-limited anchorage
  overlay, the fictional Magic Anchor with its timing dial, the engine
  stopping at anchor, decorative solar panels on all four boats, and Sprite
  Workshop Phase 1 (`art_replacements/`); see `docs/revisions/v0.105b/REVISION_0_105B_REPORT.md`,
  `docs/artwork/SPRITE_WORKSHOP_REPORT.md` and `docs/revisions/v0.105b/WINDOWS_ACCEPTANCE_0_105B.md`.
