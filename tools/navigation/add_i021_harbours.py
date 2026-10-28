"""Adds the I021 harbours (A Wider, Warmer World) to tools/navigation/harbours.csv and
writes their facility files (data/harbours/facilities/<id>.tres).

Chosen to fill gaps on the world chart along real cruising routes: Ireland's west, the
Hebrides, Iceland's north-west fjords, Atlantic Canada, Malta, the Dodecanese, Morocco's
Atlantic coast, West Africa, the South Atlantic islands and the Cape, the Indian Ocean,
the Strait of Malacca and Tasmania.

Left out: Picton (NZ PCN), at the head of Queen Charlotte Sound, more than the approach limit
from water on the coarse world chart (recorded in harbours_rejected.csv).

Positions: GeoNames (geonames.org, CC BY 4.0; the "cities1000" place points, here read
through the GitHub mirror lutangar/cities.json) to four decimals, cross-checked against
the UN/LOCODE entry (UNECE code list) where that entry has a coordinate. Recorded per
row in "source". Essaouira's UN/LOCODE point (3125N 00930W) lies 25 km inland, so the
GeoNames point is used for all rows. These are gameplay positions of the town, not
berths or marina layouts; on the coarse world chart the harbour reaches open water
through its harbour approach (SeaRouter.find_port_approach), and test_harbours checks
every one. A candidate that fails goes to harbours_rejected.csv with the reason.

Facilities are gameplay tiers (HarbourFacilities), as in Iteration 16: small harbours
have no boatyard, larger ones a boatyard, major service harbours can haul out. Every
harbour here has groceries. Not claims about real businesses.

Descriptions are one plain sentence about the place as a sailor finds it.

Then run tools/navigation/build_harbours.py to write the port resources.

Usage: python3 tools/navigation/add_i021_harbours.py
"""
import csv
import os

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "..")
CSV_PATH = os.path.join(HERE, "harbours.csv")
FACILITY_DIR = os.path.join(ROOT, "data", "harbours", "facilities")

# id, name, country, latitude, longitude, cross-check, importance, region, island, tier, description
HARBOURS = [
    ("dingle", "Dingle", "Ireland", 52.1408, -10.2689, "UN/LOCODE IE DIN (no coordinate)", 3, "british_isles", 0, "small",
     "Dingle, a small fishing harbour at the head of its bay in Ireland's far south-west, with painted shopfronts above the quay."),
    ("stornoway", "Stornoway", "United Kingdom", 58.2093, -6.3865, "UN/LOCODE GB STO 5813N 00622W", 2, "british_isles", 1, "larger",
     "Stornoway on the Isle of Lewis, the little capital of the Outer Hebrides, where ferries and fishing boats share the inner harbour."),
    ("isafjordur", "Ísafjörður", "Iceland", 66.0748, -23.1350, "UN/LOCODE IS ISA (no coordinate)", 3, "north_atlantic", 0, "small",
     "Ísafjörður, a fishing town on a sandspit in the fjords of Iceland's north-west, under steep mountains."),
    ("lunenburg", "Lunenburg", "Canada", 44.3785, -64.3166, "UN/LOCODE CA LUN (no coordinate)", 2, "north_america", 0, "larger",
     "Lunenburg, Nova Scotia, an old fishing town of painted wooden houses climbing the hill above its red waterfront sheds."),
    ("st_johns", "St. John's", "Canada", 47.5649, -52.7093, "UN/LOCODE CA SJF 4734N 05244W", 2, "north_america", 0, "larger",
     "St. John's, Newfoundland, reached through the narrow cliffs of the Narrows, with rows of colourful wooden houses above the harbour."),
    ("valletta", "Valletta", "Malta", 35.8997, 14.5148, "UN/LOCODE MT MLA 3553N 01430E", 1, "mediterranean", 1, "major",
     "Valletta, Malta, where honey-coloured bastions rise straight out of the water of Grand Harbour."),
    ("symi", "Symi", "Greece", 36.6155, 27.8362, "UN/LOCODE GR SYM 3636N 02750E", 3, "aegean", 1, "small",
     "Symi, a small island harbour in the Dodecanese, ringed by tiers of pastel neoclassical houses."),
    ("essaouira", "Essaouira", "Morocco", 31.5125, -9.7700, "UN/LOCODE MA ESS 3125N 00930W (point inland; not used)", 3, "west_africa", 0, "small",
     "Essaouira on Morocco's Atlantic coast: blue fishing boats beneath the old sea bastion, and gulls over the Skala."),
    ("dakar", "Dakar", "Senegal", 14.6937, -17.4441, "UN/LOCODE SN DKR (no coordinate)", 2, "west_africa", 0, "larger",
     "Dakar, near the westernmost point of Africa, where painted pirogues come in beside a busy commercial port."),
    ("st_helena", "Jamestown", "Saint Helena", -15.9249, -5.7182, "UN/LOCODE SH SHN (no coordinate)", 2, "south_atlantic", 1, "small",
     "Jamestown, St Helena: one long street in a narrow valley between dark volcanic cliffs, alone in the South Atlantic."),
    ("cape_town", "Cape Town", "South Africa", -33.9258, 18.4232, "UN/LOCODE ZA CPT 3355S 01825E", 1, "south_atlantic", 0, "major",
     "Cape Town, beneath Table Mountain, the harbour for sailors on the long way round the Cape of Good Hope."),
    ("zanzibar", "Zanzibar", "Tanzania", -6.1639, 39.1979, "UN/LOCODE TZ ZNZ (no coordinate)", 2, "indian_ocean", 1, "larger",
     "Zanzibar's Stone Town, where dhows lie off coral-stone houses with carved wooden doors."),
    ("port_louis", "Port Louis", "Mauritius", -20.1619, 57.4989, "UN/LOCODE MU PLU (no coordinate)", 1, "indian_ocean", 1, "larger",
     "Port Louis, Mauritius, a busy harbour town between green mountains and the Indian Ocean."),
    ("galle", "Galle", "Sri Lanka", 6.0461, 80.2103, "UN/LOCODE LK GAL (no coordinate)", 2, "indian_ocean", 0, "larger",
     "Galle, Sri Lanka, beside the ramparts of its old fort, on the sea road across the Indian Ocean."),
    ("langkawi", "Langkawi", "Malaysia", 6.3265, 99.8432, "UN/LOCODE MY LGK 0622N 09948E", 2, "southeast_asia", 1, "larger",
     "Kuah on Langkawi, Malaysia, among green limestone islands at the northern entrance of the Strait of Malacca."),
    ("hobart", "Hobart", "Australia", -42.8794, 147.3294, "UN/LOCODE AU HBA 4252S 14718E", 2, "pacific", 1, "larger",
     "Hobart, Tasmania, where old sandstone warehouses line the docks below Mount Wellington."),
]
TIERS = {"small": (True, False, True, False), "larger": (True, True, True, False), "major": (True, True, True, True)}


def main():
    rows = list(csv.DictReader(open(CSV_PATH, encoding="utf-8")))
    fields = list(rows[0].keys())
    known = {r["id"] for r in rows}
    added = 0
    for hid, name, country, lat, lon, check, importance, region, island, tier, description in HARBOURS:
        source = "GeoNames %s (%.4f, %.4f), cities1000; %s; I021" % (name, lat, lon, check)
        row = {"id": hid, "name": name, "country": country, "latitude": "%.4f" % lat, "longitude": "%.4f" % lon,
               "importance": str(importance), "region": region, "island": str(island), "source": source,
               "description": description}
        if hid in known:
            rows = [row if r["id"] == hid else r for r in rows]
        else:
            rows.append(row)
            added += 1
        grocery, boatyard, go_ashore, haul_out = TIERS[tier]
        with open(os.path.join(FACILITY_DIR, hid + ".tres"), "w", encoding="utf-8", newline="\n") as f:
            f.write('[gd_resource type="Resource" script_class="HarbourFacilities" format=3]\n\n'
                    '[ext_resource type="Script" path="res://src/harbour/harbour_facilities.gd" id="1_fac"]\n\n'
                    '[resource]\nscript = ExtResource("1_fac")\ngrocery = %s\nboatyard = %s\ngo_ashore = %s\nhaul_out = %s\n' % (
                        str(grocery).lower(), str(boatyard).lower(), str(go_ashore).lower(), str(haul_out).lower()))
        print("%-12s %-7s %9.4f %9.4f" % (hid, tier, lat, lon))
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(added, "harbours added")


if __name__ == "__main__":
    main()
