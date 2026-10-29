# I027 Windows acceptance - The Cost of the Wind

**Status: pending.** The Linux checks passed (see the
[iteration report](ITERATION_27_REPORT.md)). None of this list has been run on
Windows yet. These checks are the Captain's own.

## Setup

1. Download and extract the release ZIP:
   https://github.com/crosenlund79/WorldSailorSim/archive/refs/heads/release/i027.zip
2. In Godot 4.7.x, Import the extracted `project.godot` (not the ZIP), then
   Edit, and wait for the first import.
3. Press **F5**. The bottom-right label reads `BH · i027_04 · TEST · <commit>`.
4. Play at 1280×720 or larger. Do the opening and the quay once in English
   and once in Danish (Settings → Language).

Mark each line **pass**, **fail** (with a note), or **not tried**.

## The ten acceptance items of the commission

| # | Item | How | Result |
|---|---|---|---|
| 1 | New-game opening | Title → **New Game** → Start. The story is told over three pictures: Continue, Space or a click turns the page. On a second New Game, try **Skip**, and on a third **Esc**. Each time you land in the cabin, free to play. **Load** and **Continue** never show it | |
| 2 | Captain's Dreams | The laptop in the cabin (E) → **Dreams**. Pursue up to three. A 100 nm passage fulfils "A passage of your own". The I028 dreams say "later" | |
| 3 | Fuel purchase | On the quay, the red **pump** by the walkway's head: E shows the tank, **Fill up** or +10 L. Is the pump easy to see? | |
| 4 | Fuel consumption | Motor out of harbour (or use **Motor to windward**). The switch panel's fuel goes down, and a notice comes at a quarter tank. Under sail it stays put | |
| 5 | Operating costs | The Harbour Office lists them. Stay a night, then leave: a note shows the dues paid | |
| 6 | Manual and automatic tacking | Plan Copenhagen → Gothenburg. With the wind ahead the boat beats about 45° off it (**I** names the tack). **K** tacks by hand. **Q** offers **Tack now** and **Motor to windward** | |
| 7 | Realistic ETA | The chart's estimate for a leg to windward is longer than the straight line, and the arrival is close to it | |
| 8 | Two distinct yacht layouts | Boatyard: the comparison rows (guests by day/overnight, private guest cabins, suited to). Board the 26 ft and the Clam (catamaran), or the Wing 33: the cabins look and sleep differently | |
| 9 | Save and load | F5 mid-tack, and F9: the boat is where it was, on the same tack, with the same fuel and dreams. An **I026 save** loads aboard with everything kept, and no opening story | |
| 10 | The I026 waterfront | The quay's shops, café, noticeboard, hours and townsfolk all work as before | |

## The Tier 4 changes

| Check | How | Result |
|---|---|---|
| F10 developer menu | It opens and closes on the **quay**, the **deck**, in the **cabin** and on the **chart**. It never opens over another window (e.g. the fuel pump) | |
| Compact quay | Walk the quay at normal speed: buildings narrower, doors and the walkway at true size, every business easy to tell apart and reach (boatyard and travel lift, sail loft, chandlery, office, café, grocery, fishmonger) | |
| Captain and townsfolk | They look like they belong to the illustrated world: no big heads, quiet shading | |
| The hat | Credible on the head, blowing off and carried; still the Captain's hat | |
| The walk | Arms swing opposite the legs, the feet show slightly, diagonals and reverse look right, starting and stopping settle without a snap, no skating. Watch the townsfolk too | |
| 130 % interface scale | Settings → UI scale 130 %: the HUD, the opening's words and the menus fit | |

## Performance on the graphics card (Linux could not measure these)

| Check | How | Result |
|---|---|---|
| Long Passage | A long voyage, then the passage panel at 12 h per second: smooth? | |
| Chart panning | Open the chart and drag it around: smooth? (In the Linux container, panning takes about 150 ms a frame without a GPU, the same as I026) | |
| Quay and harbour at night | Walking the quay at dusk and night: smooth? | |

## Known and accepted (not defects)

- **Between Horizons is a working title only.** A released game has that
  name, so the naming decision comes before any public metadata.
- At full walking speed the planted foot creeps back a little. This is
  deliberate, to keep the feet subtle.
- A tack has no slowdown animation of its own. It is on the polish list.
