# I026 - A World You Can Touch: design (Stage 1)

The audit is [UI_INVENTORY.md](UI_INVENTORY.md) (100 interactions; 19 should
become physical objects, 16 focused views of objects, 37 stay conventional,
35 are already physical). This page records the decisions that follow from
it. Internal stages (one major iteration, `GameVersion.STAGE`): 01 audit and
foundations · 02 living harbours · 03 marine electronics · 04 life aboard ·
05 integration and polish · 06 verification and release.

## The interaction language (all stages)

One convention, the one the game already has: an `Interactable` on the
object, the focus glow around the object's own outline
(`HighlightResolver`), a short prompt in the HUD's prompt bar, **E** to use.
New physical objects follow it; nothing gets an icon, a coloured outline or a
permanent marker. What opens from an object is a **focused view**: the
existing menu, framed so it visibly belongs to the object (a shop counter, a
book, a device bezel, the laptop's screen), dismissed with Esc as every modal.
Quick actions stay: the hotkeys, the action wheel, and the HUD's safety
information.

## Stage 02 - living harbours: the quay

At true scale (I025: about 1 cm per unit) six businesses need some fifty
metres of frontage; the deck view is framed on the boat and its pontoon. So
the harbour gets **its own walkable place, the quay** (`HarbourFront`): the
waterfront at the head of the guest pontoon, reached by walking up the
pontoon's walkway (the old Go Ashore station becomes that walkway). It is a
screen like the chart, not a save area: saving there saves the Captain on
the pontoon, and loading returns to the boat - no save-format change.

- **Separate storefronts**, each recognizable by architecture, sign and
  what stands outside it, in the harbour's regional style (the archetypes of
  `HarbourDressing.TOWNS`): the **boatyard** (a workshop shed, a hull on
  stands, a travel lift where the harbour hauls out), the **chandlery**, the
  **sail loft**, the **grocery**, the **fishmonger** (a stall with crates on
  ice), the **café** (a terrace), the **harbour office** and a
  **noticeboard**. Present only where the harbour has the service
  (`HarbourFacilities`; the trades follow their parent as today). Each opens
  the existing menu through a shop-counter frame; the shared backend
  (prices, stock, ownership, saves) is untouched.
- **Opening hours** (`BusinessHours`): per business type, nudged by region
  and harbour tier, on the harbour's local solar time from the authoritative
  clock. Shown on the door (open/closed sign, lit windows, the hours on a
  plate). A closed door offers **Wait until it opens** (the existing time
  passage, as sleeping), so nobody is stranded; the harbour office's after-
  hours hatch keeps essential services (repairs after damage, basic food)
  reachable at any hour.
- **People** (`HarbourLife`): a handful, deterministic from the harbour and
  the hour, rebuilt when the scene is built (no simulation while away, no
  backlog after sleeping). Routines with destinations and pauses: walking
  the quay, into and out of shops, sitting at the café, a fisherman with
  nets, a shopkeeper locking up. Few or none at night and in bad weather;
  some harbours busy, many quiet. They never stand in a doorway or the
  walkway.
- **The café**: order a coffee (a small price), sit at a terrace table, the
  Captain drinks (the I022 mug), time passes, leave when you like. A few
  customers. Companions ashore lie by the table (the conure on its back).
- **Harbour office and noticeboard**: the harbour's services and hours, its
  tier, local notes from the harbour data, the forecast in words - nothing
  that replaces a safety warning, no quests.
- **Go Ashore** (the small harbour moments) moves to the quay's town end
  (a lane into town).

## Stage 03 - marine electronics

- **One instrument cluster** replaces the sailing panel and the route
  panel's sailing lines: speed, heading, wind, depth where simulated, the
  route (waypoint, distance, ETA), from the same authoritative data the HUD
  already reads (no second calculation), refreshed a few times a second.
  Compact and readable while sailing; click (or a key) for the **focused
  instrument view**.
- **Three packages** (`InstrumentPackage`): *Classic* (analogue dials, fitted
  to every boat), *Modern Cruiser* (compact displays with pages), *Offshore
  Navigator* (a multifunction display with layouts). Sold by the chandlery,
  fitted per boat, owned packages selectable (never lost); all show the
  essential data. Save: a new optional `instruments` field, default
  Classic.
- **Cockpit**: the fitted package's displays drawn at the helm on every
  deck; the chartplotter mounted there (the P panel becomes the helm
  plotter's view; trip planning stays at the chart table and the wheel's
  Charts).
- **Weather and VHF**: forecast pages on the instruments; the VHF set below
  (stage 04). Warnings stay in the HUD.

## Stage 04 - life aboard

- **Logbook** on the chart table (the Captain's Log in a book; L stays).
- **VHF set** at the nav station: the last calls and broadcasts; incoming
  calls still alert.
- **Galley, lockers, berth**: already stations; their menus open as focused
  views of the stove, the locker and the berth.
- **Systems panel**: what is really simulated - the fitted instruments,
  solar panels, sails, hull and gear condition - not new chores.
- **Sail trim** at the cockpit winch (T and the wheel stay).
- **Memories**: the latest postcard pinned in the cabin.

## Kept conventional, on purpose

Pause and settings, save/load, the Handbook and Academy, the clock bar and
time controls, safety and traffic warnings, the interaction prompt, the
shortcut strip, the action wheel, the build identifier, the hull / money /
food line, the Long Passage panel's controls.

## Save data

Only additive, optional fields with safe defaults (`instruments`; nothing
for the quay, hours or people, which are rebuilt from the clock). Save
format 12 stays.
