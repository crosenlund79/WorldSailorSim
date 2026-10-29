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
- **Art direction: Illustrated sailing realism. Cozy at heart.** (Real
  Horizon, made the official direction at the Great Handover.) About 7/10
  realism, entirely 2D: natural, subdued sea colours; believable boat
  proportions and equipment; atmospheric weather; realistic marine materials;
  grounded harbour architecture; practical yacht interiors; a modern
  marine-electronics interface; clear, restrained typography; a warm,
  welcoming sense of life aboard. Never drift back toward the old storybook
  look; never push toward photorealism for its own sake. Cozy first, less is
  more. Details: `DEV_GUIDES/ART_DIRECTION.md`.
- **Approved generated art is protected.** The Captain approves Real Horizon's
  generated appearance; it does not need replacing. The generators in
  `tools/` overwrite their outputs, so they are re-run only when a task asks
  for that art to change, and never over a layer the Captain has replaced.
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

### Iteration 21, A Wider, Warmer World

The Captain has authorized (version 0.108a, save format 12 unchanged), after a
verified checkpoint branch (`backup/post-engine-room-pre-i021`):

- **More world in the existing systems, not more complexity**: about 12–20 real
  harbours chosen for gaps along real routes (verified positions, real water
  access, facilities in the existing tiers, English and Danish), about 8–12 real
  fish in their real regions with art, and a few cabin things in I020's system.
- **Harbours look like their place, never like their continent**: a small
  library of original illustrated harbour looks chosen per harbour by its
  architecture, materials, land and climate (a New Zealand harbour may look
  Scandinavian), in the game's hand-drawn style; no placeholders presented as
  finished art.
- **Special harbours** (those with their own illustrated arrival) get a subtle
  mark on the chart and a line saying why; ordinary services never make a
  harbour special.
- **Additional boats and the parrot and hamster companions only if complete and
  safe**; otherwise a feasibility note. No second UI overhaul.
- This iteration took the number 21. The earlier planned "The Well-Trimmed
  Ship" remains a separately scoped future assignment (not started, not
  cancelled).

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

- Only the repository `crosenlund79/WorldSailorSim` is worked on (canonical
  since the Great Handover; see *Repository migration*). The original
  `crosenlund79/LittleCaptainsHat` is the read-only historical source for
  pre-migration releases (to be archived by the Captain), and the archived
  Next Harbor repository and unrelated projects are never edited.
- Use recoverable checkpoint commits. Never reset, force-push or discard work.
  Major iterations have their own branches (see *Major iteration branches*).
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
- **The Harbourmaster's Inspection.** Before every delivery, and after adding
  or changing content, run `python tools/qa/check_game_content.py`: it must
  report no FAIL. Its WARN and INFO findings are read and either fixed or
  explained in the report; unused assets are listed for the Captain's review
  and never deleted without his approval. Releases follow
  `docs/technical/RELEASE_READINESS.md`.

### Major iteration branches

Every major numbered iteration (I022, I023, ...) has its own development
branch and a permanent recovery branch of the completed iteration, so each one
can be recovered, identified and downloaded on its own.

**Major or minor.** Only a major iteration (a commissioned, numbered
implementation assignment, see *Iterations and versions*) gets its own
branches. These do **not**, unless the Captain says so: injections, small
adjustments, cosmetic polish, hotfixes, and documentation or
quality-assurance assignments. They are committed on the integration branch.

**Names.** For iteration I022 (three digits, the same pattern after it):

| Branch | Purpose |
|---|---|
| `iteration/i022` | Development of the iteration |
| `release/i022` | The completed iteration, frozen |
| `claude/friendly-fermat-dey23f` | The integration branch (unchanged): everything verified ends up here |

**Starting a major iteration.**

1. Identify the latest verified integration baseline (the integration
   branch's remote head, with its tests passing).
2. Make sure unrelated work is committed and pushed.
3. Record the exact starting SHA (all 40 characters).
4. Create `iteration/i022` at that SHA:
   `git push origin <SHA>:refs/heads/iteration/i022`.
5. Verify it remotely: `git ls-remote origin refs/heads/iteration/i022` must
   show that SHA (and the GitHub branch list, when available).
6. Develop the iteration on that branch only. Its first commit sets the
   build identity in `src/app/game_version.gd`: `ITERATION = "i022"`,
   `STAGE = ""`, `CHANNEL = "DEV"` (the label in the window's bottom-right
   corner then reads `LCH · i022 · DEV · <commit>`; since I027 the project
   code is `BH`, for the working title Between Horizons: `BH · i027 · DEV`).

**Build identifier.** Every running build names its checkpoint in the
bottom-right corner (`BuildLabel`), from `GameVersion` only: `ITERATION`,
an optional internal `STAGE` (shown `i022_02`) when an iteration is delivered
in numbered stages, and `CHANNEL` - `DEV` while work is in progress, `TEST`
for a verified snapshot that a release branch points at. Small adjustments
on the integration branch after a release keep that iteration's number with
`DEV`. The values are committed with the code, so a historical checkout names
itself; they are never edited on a `release/…` branch. A public export hides
the label (export feature `public_release`).

If the branch cannot be created and verified, implementation does not begin.
If the GitHub environment refuses a branch, an authorized GitHub
integration/API route may be used; otherwise the work stops and the limitation
is reported. A branch is never reported as existing until it has been seen on
the remote.

**Completing a major iteration.**

1. Run the required tests (`docs/technical/RELEASE_READINESS.md`).
2. Commit all of the iteration's changes; the final commit sets
   `CHANNEL = "TEST"` in `GameVersion` (the snapshot reads
   `LCH · i022 · TEST`). The next development commit after the release sets
   it back to `DEV`.
3. Push `iteration/i022` and verify its remote head.
4. Create `release/i022` at that exact completed SHA:
   `git push origin <SHA>:refs/heads/release/i022`.
5. Verify it remotely (`git ls-remote`, as above).
6. Record both full SHAs (start and completed) in the iteration report.

**Release branches are immutable.** A `release/…` branch is never moved,
reset, deleted, rebased or force-pushed, and nothing is committed to it. A
correction found later belongs to new work (a hotfix on the integration
branch, or the next iteration), never to the snapshot. The `backup/…`
checkpoint branches follow the same rule.

**Integration.** An iteration is integrated into
`claude/friendly-fermat-dey23f` only after its tests and its release branch are
verified. Before merging, check what the integration branch has gained since
the iteration started (`git log <start SHA>..origin/claude/friendly-fermat-dey23f`)
and whether the two can be combined cleanly; never assume it. Integrate with a
normal merge commit (or a fast-forward when nothing was added meanwhile) so
that both the completed iteration and later work are kept. A conflict where
choosing either side would lose behaviour goes to the Captain. After
integration, re-run the tests on the integration branch and verify its remote
head.

**Downloading an iteration as a ZIP.** On GitHub: open the repository, choose
the branch (for example `release/i021`) in the branch selector, then Code →
Download ZIP; or open
`https://github.com/crosenlund79/WorldSailorSim/archive/refs/heads/release/i024.zip`
(replace `i024` with the iteration). Releases before the migration that exist
only in the original repository (`release/i023`) are downloaded from
`https://github.com/crosenlund79/LittleCaptainsHat`; they are not recreated
here. Extract it and open `project.godot` in
Godot, as usual.

**Git tags.** Tags are optional; the release branch is the authoritative
snapshot. If a tag push fails (the GitHub environment may refuse tags), the
tag is not reported as existing: the failure and its message are written in the
report, the push is not forced, and the release branch is relied on. A tag can
be added later, by the Captain on GitHub (Releases) or through an authorized
route, at the release branch's SHA.

**No destructive Git operations** on any shared branch: no force-push, no
`reset --hard` of pushed work, no rebase or amend of pushed commits, no
deleting or renaming `release/…`, `backup/…`, `iteration/…` or the
integration branch, no rewriting of history. Mistakes are corrected by new
commits. Only the Captain may decide otherwise, explicitly.

**Iteration 21** was already under way when this policy was set and kept its
branch and history. Its recovery branch `release/i021` was created at the final
I021 commit, `04a76231581f5a6d0af22ce2c2c138842b869453`, and verified on GitHub.
The pre-I021 checkpoint `backup/post-engine-room-pre-i021` (`ec84cfa`) is
unchanged.

### Repository migration (Operation New Horizon)

The Captain made Real Horizon the official edition and moved development
permanently to `crosenlund79/WorldSailorSim` (created by GitHub Import from
`crosenlund79/LittleCaptainsHat`; the commits up to I023 are the same objects,
so the history is shared, but the two repositories are separate and are never
merged back).

- **Integration branch:** `claude/friendly-fermat-dey23f` in WorldSailorSim
  (as before). It holds Real Horizon merged with everything through I023.
- **Major iterations** from I024 on use `iteration/iNNN` / `release/iNNN` in
  WorldSailorSim, following *Major iteration branches*.
- **Historical branches are not duplicated.** `release/i021`, `release/i022`,
  `iteration/i022` and the `backup/…` branches came across with the import and
  stay untouched; `iteration/i023` and `release/i023` exist only in the
  original repository, which remains their home. The Real Horizon conversion
  and the handover were not numbered iterations.
- The record of the handover (SHAs, parity, limitations) is
  `docs/DEVELOPMENT_HISTORY.md`.

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
- **Iteration 21, A Wider, Warmer World**, version 0.108a, save format 12
  (unchanged): sixteen new harbours (Dingle to Hobart), nine original harbour
  looks chosen per harbour plus six special harbours with their own illustrated
  arrival and a brass star on the chart, the arrival card, ten new fish and
  three cabin things; boats and the parrot and hamster deferred with
  feasibility notes; see `docs/iterations/i021/ITERATION_21_REPORT.md`,
  `docs/iterations/i021/HARBOUR_LOOKS.md` and
  `docs/iterations/i021/WINDOWS_ACCEPTANCE_21.md`. Recovery branch:
  `release/i021` (`04a76231581f5a6d0af22ce2c2c138842b869453`).
- **Iteration 22, The Captain's Other Life**, version 0.109a, save format 12:
  see `docs/iterations/i022/ITERATION_22_REPORT.md` and
  `docs/iterations/i022/WINDOWS_ACCEPTANCE_22.md`. Recovery branch:
  `release/i022` (`2baa01034fbaa956018c58e013b555be8213d77d`).
- **Iteration 23, Steady Hands & Golden Harbours**, version 0.109a
  (unchanged), save format 12: commissioned as a polish injection and
  reclassified as I023 by the Captain after delivery. Trip Details no
  longer moves under a weather warning; every window fits the screen,
  closes with Esc and speaks Danish (a UI sweep test); the interface stays
  readable at dusk and dawn; and the illustrated Golden Harbour Moment on a
  first arrival. See `docs/iterations/i023/ITERATION_23_REPORT.md`. Branches
  `iteration/i023` and recovery branch `release/i023`, both at the
  delivered commit (`d4e2e7e56206b220f8839323186e0c06d2a4c589`).
- **Real Horizon** (not a numbered iteration), version 0.109a, save format
  12 (unchanged): the visual conversion to illustrated sailing realism, then
  the Great Handover (Operation New Horizon): I021–I023 merged into it and
  development moved to `crosenlund79/WorldSailorSim`. See
  `docs/iterations/real_horizon/REAL_HORIZON_REPORT.md` and
  `docs/DEVELOPMENT_HISTORY.md`.
- **Iteration 24, The Company We Keep**, version 0.110a, save format 12
  (unchanged): three companions (a Ragdoll, a Pug, a green-cheeked conure)
  with optional name and gender, smaller and animated in clips; shore visits
  with a departure guard; the companion by the berth on waking; the Captain
  talking to it on long passages; a curated achievement collection of 35 in
  seven categories with when, where and which boat, sustained sailing-speed
  milestones; the cabin laptop as the home of renown, publications and the
  achievements. See `docs/iterations/i024/ITERATION_24_REPORT.md`. Branches
  `iteration/i024` and recovery branch `release/i024`.
- **Iteration 25, A Little More Room Aboard**, version 0.111a, save format 12
  (unchanged): new games start without a companion; now and then an animal
  waits on the dock in a small open box (a Ragdoll, a Pug or a conure), a
  few kind gestures and it follows, and at the companionway the Captain
  adopts it (name, gender) or lets it go home with a little girl; up to two
  companions with their own identities, places, pair moments and a combined
  morning line; the laptop records where each came aboard; cabins, framed
  glass windows on every boat (no live view outside, by the Captain's
  revision), the faded water outside the hull, harbour houses and
  neighbouring boats made more believable. See `docs/iterations/i025/ITERATION_25_REPORT.md`.
  Branches `iteration/i025` (from `cfc9b52`) and recovery branch `release/i025`.
- **Iteration 26, A World You Can Touch**, version 0.112a, save format 12
  (unchanged; one optional `instruments` section): the harbour's businesses
  moved up the pontoon's walkway to a walkable quay, each in its own
  storefront (boatyard with travel lift, chandlery, sail loft, grocery,
  fishmonger, café, harbour office with an after-hours hatch, noticeboard,
  lane into town), with opening hours on the harbour's solar time and a few
  townsfolk on deterministic routines; a café for a coffee on the terrace;
  SKERRY marine electronics in three packages (Classic, Modern Cruiser,
  Offshore Navigator) replacing the sailing panel, with cockpit instruments
  and the helm's chartplotter; the cabin's things as objects (logbook, VHF
  set, switch panel, sea chest, postcard) and the sheet winch, each opening
  its focused view. See `docs/iterations/i026/ITERATION_26_REPORT.md` and
  `docs/technical/PHYSICAL_INTERFACE.md`. Branches `iteration/i026` (from
  `3a27956`) and recovery branch `release/i026`.
- **Iteration 27, The Cost of the Wind**, version 0.113a, save format 12
  (unchanged; optional `ledger` and `dreams` sections): sailing to windward
  (the autopilot beats and gybes on the polar's best angles, manual tacking
  with K or the wheel, an ETA that counts the zigzag); fuel, a pump on every
  quay, harbour dues, Motor to windward and the running costs, with one
  balance file and the career's books; what each boat offers people aboard,
  checked against its drawn cabin, ready for I028's bookings; Dreams of the
  Sea, the PassagePlan contract, AIS preparation and career telemetry; the
  opening story and the working title Between Horizons (a working title
  only: a released game has that name); the Captain and the townsfolk
  redrawn with one shared walk and a credible hat; the compact waterfront.
  See `docs/iterations/i027/ITERATION_27_REPORT.md`. Branches
  `iteration/i027` (from `51c247e`), tier checkpoints
  `backup/i027-tier-1` to `-tier-4`, and recovery branch `release/i027`.
  Windows acceptance pending.
- **Next numbered major iteration: I028** (passengers; not to begin until
  the Captain authorises it).
