# Harbour looks (I021): which harbour looks like what

What every harbour looks like beyond the guest pontoon, as set in `data/harbours/harbour_looks.json` (the source; this page is generated from it). Looks are chosen per harbour by its buildings, materials, land and climate, never by the continent alone: New Zealand's timber towns share the Nordic look, Willemstad's and Cape Town's gabled waterfronts share Denmark's, Hobart's sandstone docks share Scotland's stone, and Dakar does not look like Morocco.

Each look is one original illustration painted by `tools/harbours/paint_harbour_looks.py` in the hand-drawn style of Copenhagen's Nyhavn strip (2300 × 220 px, drawn 1150 × 110 scene units beyond the quay). The same illustration is shared by every harbour of that look, loaded the first time it is needed and kept.

## Special harbours (their own illustration)

These show a view of their own instead of their look's, and are marked with a brass compass star on the chart. The `special` list must equal the harbours with their own `data/harbours/<id>.tres` (a test checks it).

| Harbour | Illustration | Why it is special (shown on the chart) | Base look |
|---|---|---|---|
| Copenhagen | Nyhavn (`assets/harbours/copenhagen/nyhavn.png`) | an illustrated arrival at Nyhavn's painted harbour houses | Gabled harbour town |
| Valletta | Grand Harbour bastions (`assets/harbours/valletta/grand_harbour.png`) | an illustrated arrival beneath the bastions of Grand Harbour | Mediterranean harbour town |
| Symi | Gialos (`assets/harbours/symi/gialos.png`) | an illustrated arrival among the tiers of neoclassical houses at Gialos | Aegean island harbour |
| Essaouira | The Skala (`assets/harbours/essaouira/skala.png`) | an illustrated arrival below the Skala, the old sea bastion | Stone town harbour |
| Lunenburg | Lunenburg waterfront (`assets/harbours/lunenburg/waterfront.png`) | an illustrated arrival at the red waterfront of the old fishing town | Nordic timber harbour |
| Jamestown | Jamestown (`assets/harbours/st_helena/jamestown.png`) | an illustrated arrival in Jamestown's valley between the cliffs | Volcanic island harbour |

## The looks

| Look | What it shows | Harbours |
|---|---|---|
| **Nordic timber harbour** (`nordic_timber`, 36) | Painted timber houses and boat sheds with steep roofs: the fishing harbours of Scandinavia, the Faroes and Iceland, and timber towns elsewhere that look the same (Atlantic Canada, New Zealand). | Arendal, Auckland, Bergen, Bodø, Florø, Gilleleje, Hammerfest, Haugesund, Honningsvåg, Kotka, Kristiansand, Kristiansund, Larvik, Lohals, Luleå, Lunenburg, Mariehamn, Narvik, Nelson, Nynäshamn, Oulu, Reykjavík, Rødvig, St. John's, Stavanger, Strömstad, Sundsvall, Svolvær, Tromsø, Trondheim, Tórshavn, Vaasa, Wellington, Whangarei, Ålesund, Ísafjörður |
| **Gabled harbour town** (`gabled_waterfront`, 45) | Brick and rendered townhouses with stepped and curved gables: Danish and German harbour towns, the Hanseatic Baltic, the Low Countries, and Dutch- and Cape Dutch-built waterfronts. | Aarhus, Bremerhaven, Cape Town, Copenhagen, Cuxhaven, Den Helder, Dragør, Dunkirk, Ebeltoft, Faaborg, Gdynia, Gothenburg, Grenaa, Harlingen, Helsingør, IJmuiden, Juelsminde, Kalmar, Kalundborg, Karlskrona, Kerteminde, Kiel, Korsør, Liepāja, Malmö, Marstal, Middelfart, Nyborg, Nysted, Pärnu, Rudkøbing, Rønne, Skagen, Stege, Svendborg, Sønderborg, Tallinn, Visby, Vlissingen, Vordingborg, Willemstad, Ystad, Zeebrugge, Ærøskøbing, Świnoujście |
| **Stone harbour of the Atlantic coast** (`atlantic_stone`, 33) | Grey granite and sandstone houses with slate roofs and chimneys: Scotland, Ireland, Wales, Brittany, Normandy, Galicia, the Channel Islands, Helsinki's stone quays and Hobart's sandstone warehouses. | A Coruña, Aberdeen, Belfast, Boulogne-sur-Mer, Brest, Calais, Cherbourg, Concarneau, Dieppe, Dingle, Douglas, Dublin, Gijón, Helsinki, Hobart, Kirkwall, Le Havre, Leith, Lerwick, Liverpool, Lorient, Milford Haven, Oban, Peterhead, Portsmouth, Saint-Malo, Saint-Nazaire, St Helier, St Peter Port, Stornoway, Swansea, Whitby, Wick |
| **Mediterranean harbour town** (`mediterranean`, 81) | Warm rendered and stone houses with terracotta roofs and shutters, a bell tower: Italy, southern France and the French Atlantic's limestone towns, Spain, Portugal, Croatia, mainland Greece, Türkiye, Cyprus and Malta. | Ajaccio, Alghero, Almería, Ancona, Arcachon, Bar, Barcelona, Bari, Bastia, Bodrum, Bonifacio, Brindisi, Cagliari, Calvi, Cannes, Capri, Cartagena, Catania, Chania, Chios, Civitavecchia, Corfu, Dubrovnik, Faro, Genoa, Gibraltar, Heraklion, Hvar, Ibiza, Kalamata, Kavala, Korčula, Kuşadası, La Rochelle, La Spezia, Lagos, Larnaca, Las Palmas, Les Sables-d'Olonne, Limassol, Lipari, Lisbon, Livorno, Marmaris, Marseille, Messina, Mytilene, Málaga, Nafplio, Naples, Nice, Olbia, Palermo, Palma, Patras, Peniche, Piraeus, Portimão, Porto (Leixões), Portoferraio, Pula, Rijeka, Rimini, Rovinj, Sines, Split, Syracuse, Sète, Taranto, Thessaloniki, Toulon, Trapani, Valletta, Venice, Vlorë, Volos, Zadar, Zakynthos, Çeşme, İzmir, Šibenik |
| **Aegean island harbour** (`aegean_island`, 7) | Whitewashed houses with blue doors, flat roofs and a chapel dome: the Cyclades and the small Greek islands. | Hydra, Mykonos, Naxos, Paros, Santorini, Skiathos, Symi |
| **Stone town harbour** (`stone_town`, 2) | Lime-washed masonry with arched doors and roof terraces behind a sea wall: Morocco's Atlantic coast and the Swahili coast's stone towns. | Essaouira, Zanzibar |
| **Tropical harbour town** (`tropical_town`, 20) | Low painted houses with tin roofs and verandas among palms and mango trees: the Caribbean, West Africa, the Indian Ocean, Central America and the larger Pacific towns. | Castries, Colón, Dakar, Falmouth Harbour, Fort-de-France, Galle, Honolulu, Langkawi, Lautoka, Le Marin, Mindelo, Nassau, Nouméa, Panama City, Papeete, Port Louis, Port of Spain, San Juan, St. George's, Suva |
| **Tropical island harbour** (`tropical_island`, 6) | Small timber and thatched buildings among palms on a beach: the islands of Polynesia, the Cook Islands, Tonga and the Grenadines. | Avarua, Bora Bora, Fakarava, Nuku'alofa, Port Elizabeth, Uturoa |
| **Volcanic island harbour** (`volcanic_island`, 9) | Green slopes and dark lava rock, a few white houses and a white church: the Azores, Madeira, Lanzarote, the Galápagos, the Marquesas, Samoa and St Helena. | Arrecife, Atuona, Funchal, Horta, Jamestown, Pago Pago, Ponta Delgada, Puerto Ayora, Taiohae |

## Adding or changing

- A new harbour: give it a look in `harbours` (the suite fails for a harbour without one).
- A new look: add it under `looks` with its title (translated through `locale/da.po`) and an image, painted by a new function in `paint_harbour_looks.py`.
- A new special harbour: paint its own view, add `data/harbours/<id>.tres` (a `HarbourArt` with the landmark, like Copenhagen's) and add the harbour to `special` with one line saying why.
- A missing image never breaks a harbour: it shows the plain quay (and the chart shows no star unless the harbour is in `special`).
