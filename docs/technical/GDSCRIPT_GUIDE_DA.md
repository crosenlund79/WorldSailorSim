# GDScript-guiden (dansk)

Et venligt kort over alle scripts i Little Captain's Hat: hvad hvert script
gør, hvad det arbejder sammen med, hvornår det kører, og hvad der kan
påvirkes, hvis du ændrer det. Der er ét afsnit pr. `.gd`-fil, grupperet
efter hvor filen ligger. Den engelske udgave er
[GDSCRIPT_GUIDE_EN.md](GDSCRIPT_GUIDE_EN.md), og udviklerreferencen
(afhængigheder, signaler, regler der skal holde, tests) er
[GDSCRIPT_ARCHITECTURE.md](GDSCRIPT_ARCHITECTURE.md).

**Koden bestemmer.** Hvis et afsnit her siger noget andet end scriptet, har
scriptet ret, og afsnittet skal gennemgås. Værktøjet
`python tools/docs/check_gdscript_guides.py` fortæller, hvilke afsnit der
mangler eller måske er forældede (se [Sådan holdes guiderne opdaterede](#sådan-holdes-guiderne-opdaterede)).

Nogle ord, du vil møde:

- **Script**: en `.gd`-fil med GDScript-kode. De fleste hænger på en
  **node** (en ting i en Godot-scene: en tekst, en båd, en knap) og giver
  den en opførsel.
- **Scene**: en `.tscn`-fil, en færdig opstilling af noder (en båds kahyt,
  en menu).
- **Autoload**: et script, Godot starter én gang, når spillet starter, og
  som kører hele tiden og kan nås ved navn alle steder fra (`GameSession`,
  `Simulation`, …).
- **Signal**: en besked, et script sender ("båden er ankommet"). Andre
  scripts kan lytte efter den, uden at afsenderen behøver at kende dem.
- **Resource**: en datafil, Godot kan indlæse (`.tres`), fx en havn eller
  en båds sejlegenskaber.
- **Tilstand** (state): de ting, spillet husker (hvor båden er, klokken,
  dine penge). Et gemt spil består af den.

## En rundtur i spillet

### Sådan starter spillet

Godot åbner `src/app/app.tscn`, **programskallen** (`App`,
`src/app/app.gd`). Otte autoloads kører allerede: indstillinger, lyd,
spilsessionen, simuleringen, gemte spil, diagnoseloggen, brugerfladens tema
og musikken. Skallen viser indlæsningsskærmen (den forbereder verdens
søkort én gang) og derefter hovedmenuen. Allerførste gang spørger den om
sproget. **Nyt spil** spørger efter en ledsager (kat eller hund) og starter
en ny session i København om bord på Arctic Wanderer 26.

### Skærme, menuer og handlinger

Der vises præcis én **skærm** ad gangen (hovedmenuen, dækket, kahytten,
søkortet eller drømmekortet), skiftet med en overtoning af `SceneRouter`.
Menuer og dialoger lægger sig ovenpå i en **stak** (`ModalStack`), og mens
en menu er åben, står spilverdenen stille. Informationslinjen (`Hud`)
ligger over verden. Om bord går man med WASD. Står man ved en station
(roret, kortbordet, komfuret, fiskestangen …) og trykker **E**, beder
bådområdet (`BoatArea`) om at få noget gjort. Bådområdet sender ønsket op
til `App`, som åbner den rigtige menu eller beder spillet om at handle.
**Q** åbner handlingshjulet, en kort liste over det, du kan gøre lige nu.

### Hvor spilleren og båden "bor"

Alt, hvad spillet husker, er almindelige data i `SessionState`
(`src/core/session_state.gd`), som ejes af autoloaden `GameSession`. Kun
`GameSession` ændrer dem: skærme og menuer *beder* om noget
(`GameSession.depart()`, `GameSession.buy_decor(...)`), og `GameSession`
tjekker reglerne, ændrer data og sender et signal, så skærmene kan følge
med. Båden, sejladsen, ankeret, fiskene i køleboksen, huen, ledsageren,
dine penge og dit ry og hver båds pleje og kahyt ligger alle der.

### Sådan går tiden, og sådan skifter vejret

Spillets tid går kun gennem autoloaden `Simulation`. Hvert billede rykker
den uret frem (hurtigere ved 5× eller 20×) og flytter båden langs kursen.
På et fast net af tidspunkter (hvert 5. spilminut) spørger den vejret
(`WeatherModel`, `WindField`), hvad vinden gør. Den beslutter sejl eller
motor (`PropulsionController`), ser efter dårligt vejr på ruten forude og
tjekker ankeret, forrådet, trafikken og radioen. Vejret regnes ud alene fra
tid og sted, så det er det samme, uanset om du sejler ved 1×, sover dig
igennem det eller indlæser et gemt spil.

### Navigation over hele verden

Havnene er data (`PortCatalog`, én `PortData` pr. havn). Verdens søkort er
bygget på forhånd til et navigationsnet (`NavGrid`), og `SeaRouter` finder
en rute langs det, der holder sig fri af land og går gennem kanalerne
(Kiel, Suez, Panama), hvor de er åbne. Kortbordet (`WorldMap`) viser ruten,
lader dig sætte rutepunkter og ankerpladser og planlægger sejladsen.
`PlannedRoute` er planen, mens båden ligger i havn, og `Voyage` er turen,
når du har kastet los.

### Lang passage

På en lang sejlads kan du lade timer gå for hvert sekund. `Simulation`
kører de samme trin hurtigere (`passage_rate`) og stopper selv, når noget
kræver dig: vejr forude, en fisk på krogen, ankerpladsen nået, et skib på
kollisionskurs, et opkald på radioen eller ankomst. Sejladskortet
(`VoyageMap`) viser turen imens.

### Gemme og indlæse

`SaveManager` skriver hele `SessionState` som JSON i en gemmeplads og
læser den tilbage igen. Den tjekker alt og opgraderer ældre gemte spil
(migrering). Formatet er version 12. Nyere dele (ankeralarmens niveau,
VHF-standby og tingene i kahytten) er valgfrie, så ældre gemte spil stadig
kan indlæses. Indstillinger, også sproget, gemmes for sig (`SettingsManager`)
og aldrig i et spil.

### Engelsk og dansk

Spillet taler engelsk eller dansk (I019). Tekst slås op i et katalog
(`locale/da.po`) gennem små hjælpefunktioner i `Loc` (`src/core/loc.gd`).
En sætning oversættes først, derefter sættes tallene ind, og tal, datoer,
penge og kompasretninger skrives, som hvert sprog gør det. Knapper og
tekster, der viser en hel sætning, oversætter Godot selv. Sproget vælges
første gang spillet starter (`LanguagePicker`) eller under Indstillinger.

### Trafik, radar og VHF (I019)

Andre skibe opfindes på stedet af `TrafficModel` ud fra sted og tid, så de
samme skibe er der efter en indlæsning. `Simulation` regner ud, om nogen
vil passere tæt forbi (nærmeste passage). En reel risiko meldes én gang, og
den vækker dig og stopper Lang passage. Radaren på dækket (`RadarPanel`)
viser skibene. En gang imellem kommer der et opkald på radioen (`VhfRadio`,
`VhfDialog`): en sejlbåd, der beder dig blive i nærheden, eller en fiskerbåd,
der gerne vil høre vejrudsigten. Det er frivilligt at svare, og takken
udbetales én gang.

### Butikker og din egen båd (I020)

Fiskehandleren, skibshandlen og sejlmageren (`HarbourTrades`) findes i de
havne, hvis data tillader det, og nås gennem købmanden og bådeværftet.
Hvert køb går gennem `GameSession` og sker helt eller slet ikke. Det, du
ejer til dine kahytter, og hver båds sejldug ligger i `HomeState`. Tingene
i kahytten tegnes af `CabinDecor` steder, hvor kahytten selv har plads,
aldrig oven på en station.

## Sådan holdes guiderne opdaterede

Hvert script har ét afsnit i hver af de tre guider under en overskrift som
``### `src/core/loc.gd` ``. Når et script tilføjes, fjernes eller ændres, så kør:

```
python tools/docs/check_gdscript_guides.py
```

Det viser afsnit, der mangler, findes to gange eller er blevet tilovers, og
scripts, der er ændret siden deres afsnit sidst blev gennemgået. Når du har
læst scriptet og rettet dets afsnit, så noter gennemgangen:

```
python tools/docs/check_gdscript_guides.py --acknowledge src/core/loc.gd --note "gennemgået efter flertalshjælperen"
```

Reglerne står i [CAPTAINS_ORDERS.md](../../CAPTAINS_ORDERS.md) (Working rules).


## Programskal, kernetilstand og tjenester

### `src/app/app.gd`

**Formål:** Spillets "dirigent": det forbinder menuerne, skærmene og spillets systemer, så de arbejder sammen.
- **Hvad det gør:** Viser hovedmenuen, starter og indlæser spil, åbner alle vinduer (pausemenu, søvn, fiskestang, ankerspil, bådeværft, butikker, Logbogen og flere) og gør spillets hændelser til korte beskeder og lyde på skærmen. Det er det ene sted, der håndterer Esc og genvejstasterne (F5 hurtig-gem, F9 hurtig-indlæs, H kaptajnshue, L Logbogen, R hal ind), så to vinduer aldrig reagerer på det samme tastetryk. Ved ankomst (I021) viser den ankomstkortet: havnens billede, "Ankommet til …" og én sætning om stedet. Siden I022 spørger den, før en båd købes på værftet, starter nye spil på den valgte sværhedsgrad og åbner dialogen for sværhedsgrad fra pausemenuen. I022: lange gøremål om bord (fjernarbejde, et postkort, en økt på det lille spil) går på det ene ur gennem `pass_time`: en overgang til sort, simulationen kørt én gang mens uret tæller, en linje hvis noget afbrød, og tilbage i ×1; kahyttens Q-hjul tilbyder Skriv et postkort og Arbejd på dit lille spil. I022 Skipperskolen: den har Skipperskolens kort på sit eget lag, tilbyder den første sejlads én gang ved det første nye spil på denne computer og åbner Skipperens håndbog med F1 eller fra pausemenuen. Steady Hands: hver knap får sin kliklyd én gang, også når den flyttes til en anden forælder. Golden Harbours: første ankomst til en havn med et billede viser det gyldne havneøjeblik (havnens billede belyst efter tidspunktet, med logbogslinjen på) i stedet for det lille kort og en særskilt logbogsbesked; en kendt havn beholder det lille kort. Beskeder om omdømme viser nu milepælenes navne på det valgte sprog. I024: arbejdspladsen og punktet Laptop på kahyttens hjul åbner Kaptajnens laptop (`open_laptop`, `LaptopView`), hvor postkort, rejseopdateringer, fjernarbejde, det lille spil og bedrifterne nu bor (`open_work_menu`, `open_postcards` og `open_game_dev` åbner den på den rigtige app). Fortøjet følger ledsageren Kaptajnen i land ad landgangen og bliver nogle gange lidt længere på pontonen; før der kastes los, spørger den, om ledsageren skal kaldes om bord (`recall_companion`, også på hjulet). Efter en rigtig søvn kan en lille linje fortælle, hvor ledsageren findes, og på lange passager taler Kaptajnen nu og da med den (`_update_passage_talk`: timet efter rejsens eget ur, kun i stille øjeblikke, aldrig en strøm af linjer efter hurtig tid eller en indlæsning). Den tilføjer også det lille versions-id i nederste højre hjørne, én gang (`BuildLabel`). I025: et nyt spil begynder uden ledsager (Nyt spil spørger ikke længere efter en). Hver ledsager følger Kaptajnen i sit eget tempo, og to tager aldrig samme plads på dækket eller pontonen; før der kastes los, nævnes begge, hvis begge er i land, og "Kald … om bord" henter dem alle på én gang. Når et dyr fra kajen har fulgt Kaptajnen hen til nedgangen, kommer spørgsmålet om adoption, før man går ned (`ask_about_dock_animal`, `AdoptionDialog`): Adoptér giver det et navn, byder det velkommen om bord med en kort linje og går ned; Ikke nu holder Kaptajnen på dækket, og den lille pige kommer og henter dyret; Esc beslutter intet. Med to ledsagere taler Kaptajnen på en lang passage nogle gange til den ene, andre gange om dem begge, stadig én bemærkning ad gangen; sejler man alene, er der ingen snak på passagen. I026: op ad pontonens gangbro kommer Kaptajnen til kajen (`open_quay`, `HarbourFront`), en skærm ligesom søkortet. Hver dør dér åbner forretningens egen menu i dens butiksdisk-ramme (`ShopCounter`); en lukket dør siger, hvornår den åbner, og tilbyder at vente til da (`ask_wait_until_open`, hvor tiden går som under søvn); havnekontorets luge har altid åbent (mad og en nødreparation); caféen sælger en kop kaffe og sætter Kaptajnen ved et bord på terrassen; opslagstavlen og stræden ind til byen (Gå i land) er der også, og går man ned igen, kommer man om bord. Gemmer man på kajen, står Kaptajnen på pontonen ved gangbroen. Instrumenterne (I, et klik på HUD'ens instrumenter eller på enhederne ved roret, handlingshjulet) åbner nærbilledet `InstrumentView`, og P åbner rorets kortplotter tæt på (`PlotterView`) i stedet for at slå et HUD-panel til og fra. I kahytten åbner logbogen, VHF-radioen, eltavlen, sømandskisten og det nyeste postkort deres visninger (`open_cabin_object`), hver indrammet som genstanden (`FocusFrame`), ligesom proviantskabet, komfuret, trofætavlen og køjens søvndialog; VHF-radioens lampe blinker, mens et opkald venter. Skødespillet på dækket åbner sejltrimmet. En trafikalarm vises nu under sin egen overskrift, "Trafikadvarsel". I027: K (eller "Vend nu" / "Bom nu" på handlingshjulet, mens autopiloten krydser) vender eller bommer i hånden og siger, hvilken halse båden nu er for. I027 trin 2: kajens brændstofpumpe åbner brændstofmenuen; handlingshjulet tilbyder "Motor op mod vinden".
- **Arbejder sammen med:** `GameSession`, `Simulation`, `SaveManager`, `SceneRouter`, `Hud`, `ModalStack`, `Toasts`, `AudioManager`, `WeatherAudio`, `SessionLog`. I026: `HarbourFront`, `BusinessHours`, `ShopCounter`, `FocusFrame`, `InstrumentView`, `PlotterView`.
- **Holder styr på:** Kun skærmens bogføring: om redningsrapporten er åben, et VHF-radioopkald eller et spørgsmål om ankerpladsen, der venter på at blive vist, sekunderne før en fisk på krogen slipper væk, hvornår hver ledsager næste gang følger dig mellem kahyt, dæk og land, og hvornår Kaptajnen næste gang taler med den på en lang passage. Selve spillet ligger i `GameSession`. I026: også hvilken forretning på kajen den åbne menu hører til (for dens ramme).
- **Hvornår det kører:** Altid: det er hovedscenen, der starter med spillet.
- **Hvis du ændrer det:** Næsten alle forløb kan blive påvirket: hvilke vinduer der åbner hvor, hvornår spillet pauser bag en menu, hvad spilleren får at vide efter søvn eller ankomst, motorlyden og reglerne for hurtig-gem.

### `src/app/game_version.gd`

**Formål:** Holder spillets versionsnummer ét sted.
- **Hvad det gør:** Giver den version, spillerne ser (fx "0.113a"), en udgave kun med tal til værktøjer, og den korte kode for præcis denne build (commit), når den kan findes. Også den eneste kilde til udviklingsversionens id: iterationen ("i027"), et valgfrit internt stadie ("i027_02") og DEV eller TEST, samlet til mærket "BH · i027 · DEV · <commit>" (eller et ærligt "BH · dev-build", når iterationen ikke er sat), og om mærket vises.
- **Arbejder sammen med:** `SessionLog` (skriver versionen ved opstart), hovedmenuen (viser den), `BuildLabel` (viser id'et), `tools/write_build_info.py` (skriver `build_info.json`).
- **Holder styr på:** Buildens commit-kode, læst én gang og husket.
- **Hvornår det kører:** Når noget spørger efter versionen (opstartslog, hovedmenu).
- **Hvis du ændrer det:** Du skal også ændre versionen i projektindstillingerne; en test tjekker, at de to passer sammen. Gemte spil registrerer spillets version. Sæt iteration, stadie og kanal ved hvert checkpoint, som kaptajnens ordrer siger (*Major iteration branches*).

### `src/app/scene_router.gd`

**Formål:** Skifter den ene synlige skærm (hovedmenu, kahyt, dæk, søkort) med en kort overtoning til sort.
- **Hvad det gør:** Fjerner den gamle skærm, laver den nye og toner tilbage. Der findes kun én skærm ad gangen, så spilleren eller båden kan aldrig blive fordoblet.
- **Arbejder sammen med:** `App` (beder om hvert skærmskift); skærmene selv.
- **Holder styr på:** Den aktuelle skærm, og om et skift er i gang ("optaget").
- **Hvornår det kører:** Hver gang skærmen skifter.
- **Hvis du ændrer det:** Skærmskift, overtoningens tid og "optaget"-tjekket, som mange vinduer venter på.

### `src/art/marine_palette.gd`

**Formål:** De fælles farver i Real Horizon-udseendet, samlet ét sted.
- **Hvad det gør:** Navngivne materialefarver (hav, himmel, glasfiber, stål, teak, træ, kajsten, instrumentpaneler, cyan, rav, lampelys) og `sea_colour()` til et kyst- eller stormvejrshav. Al proceduremæssig tegning tager sine materialer herfra; Python-malerne bruger de samme værdier (`tools/art/marine_palette.py`).
- **Arbejder sammen med:** `SeaSurface`, `HarbourDressing`, `CabinWindows`, `PostcardView` og stilguiden i `DEV_GUIDES/ART_DIRECTION.md`.
- **Holder styr på:** Intet; kun konstanter.
- **Hvornår det kører:** Når noget tegnes med disse farver.
- **Hvis du ændrer det:** Havets, havnenes og tingenes udseende overalt på én gang; hold den i trit med Python-paletten.

### `src/core/academy.gd`

**Formål:** Skipperskolens indhold og fremskridt (I022): Skipperens håndbog, den første sejlads og tipsene.
- **Hvad det gør:** Læser `data/academy/academy.json`: håndbogens kapitler og sider, de otte trin i den første sejlads og tipsene. Taster skrives aldrig i teksterne; `{interact}` og lignende udfyldes fra spillets egne tastebindinger, som tastaturet viser dem, så ingen tekst kan nævne en forkert tast. Den søger i siderne på det valgte sprog og gemmer fremskridtet (første sejlads tilbudt, begyndt, sprunget over eller færdig; trinnet; de viste tips) i indstillingerne på denne computer.
- **Arbejder sammen med:** `SettingsManager` (fremskridtet), `AcademyGuide`, `HandbookMenu`, `App`, `Loc`.
- **Holder styr på:** Datafilen, læst én gang.
- **Hvornår det kører:** Når en side, et trin eller et tip vises, og når fremskridtet ændres.
- **Hvis du ændrer det:** Tilføj nye tekster i datafilen med `{action}`-pladsholdere; `test_academy` fejler ved en ukendt pladsholder eller en manglende dansk tekst.

### `src/core/achievement_catalog.gd`

**Formål:** Samlingen af bedrifter, som vises på laptoppen i kahytten (I024).
- **Hvad det gør:** Læser `data/progression/achievements.json`: et mindre udvalg af meningsfulde bedrifter i syv kategorier (rejser, sømandskab, sejlpræstationer, livet om bord, ledsagerskab, opdagelser, omdømme). En bedrift er et udsnit af de ry-optegnelser, spillet allerede fører, aldrig et regnskab ved siden af: den låses op, når en af dens optegnelser er gennemført (eller nok optegnelser af én slags), og ry betales stadig én gang af selve optegnelsen, så intet betales to gange, og et ældre gemt spils bedrifter vises med det samme. Den fortæller, hvornår, hvor (en havn eller en position til søs) og på hvilken båd en bedrift blev låst op, og siger ærligt "Stedet er ikke registreret" eller "Låst op tidligere", når et ældre gemt spil ikke ved det. En skjult hemmelighed viser kun sit hint og det hemmelige mærke.
- **Arbejder sammen med:** `ObjectiveProgress` (optegnelserne), `ObjectiveCatalog` (målene for fjerne havne), `PortCatalog`, `VesselCatalog`, `Simulation` (datoer), `Loc`, `LaptopView` (viser den); mærkerne ligger i `assets/achievements/`.
- **Holder styr på:** Datafilen, læst én gang (kun til læsning).
- **Hvornår det kører:** Når laptoppen viser bedrifter.
- **Hvis du ændrer det:** Hvad samlingen viser, aldrig hvad der betales. En bedrifts id er fast: omdøb den aldrig.

### `src/core/anchor_state.gd`

**Formål:** Optegnelsen over ankeret: om båden ligger for anker, hvor, og hvor godt det holder.
- **Hvad det gør:** Gemmer ankerets position, kædelængden (scope: 3, 5 eller 7 gange dybden), hvor godt det blev sat, hvordan det holder (godt, rimeligt, dårligt, driver), ankeralarmen, de stille øjeblikke ved ankerpladsen, der allerede er set, og hvilket anker der er ude (normalt eller Magic Anchor). Det kan kopiere sig selv og lave sig om til gemme-data og tilbage.
- **Arbejder sammen med:** `SessionState` (holder det), `GameSession` (den eneste kode, der ændrer det), `SaveManager`.
- **Holder styr på:** Alle ankerets oplysninger ovenfor.
- **Hvornår det kører:** Når ankeret bruges, tjekkes, gemmes eller indlæses.
- **Hvis du ændrer det:** Gemte spil (anker-delen), ankeralarmen, at ankeret driver, og hvilke stille øjeblikke for anker der gentages efter indlæsning.

### `src/core/boat_care_state.gd`

**Formål:** Plejeoptegnelsen for én båd: daglig slitage, monteret udstyr og servicehistorik.
- **Hvad det gør:** Husker, hvornår bunden sidst blev renset, hvor slidt rigningen er (0–100), motortimer siden sidste service, hvilke udstyrsopgraderinger der er monteret, og de seneste 12 serviceeftersyn.
- **Arbejder sammen med:** `SessionState` (én optegnelse pr. båd), `GameSession` (ændrer den), `BoatCare` (regner ud, hvad slitagen betyder), `SaveManager`.
- **Holder styr på:** Oplysningerne ovenfor, for hver båd.
- **Hvornår det kører:** Under sejlads (slitagen vokser) og på bådeværftet (service, opgraderinger); ved gemme og indlæse.
- **Hvis du ændrer det:** Bådens fart og vejrskader fra slitage, bådeværftets skærme og "boat_care"-delen af gemte spil.

### `src/core/captains_log.gd`

**Formål:** Logbogen (Captain's Log): din sejlhistorie.
- **Hvad det gør:** Holder totalerne (sømil sejlet, gennemførte rejser, ankomster), den længste passage, hver havn du har besøgt, og de sidste 50 rejser. Den skriver en rejse ned, når den slutter, enten ved ankomst eller ved redning.
- **Arbejder sammen med:** `GameSession` (den eneste, der skriver i den), `ObjectiveCatalog` (læser den for at give ry), Logbogens menu, `SaveManager`.
- **Holder styr på:** Statistikken, besøgte havne og de seneste rejser.
- **Hvornår det kører:** Når en rejse slutter; når Logbogen vises, gemmes eller indlæses.
- **Hvis du ændrer det:** Logbogens skærm, præstationer og ry, der afhænger af sømil eller havne, og "log"-delen af gemte spil.

### `src/core/career_ledger.gd`

**Formål:** Karrierens regnskab: hver euro ind og ud efter kilde, brændstof købt og brugt, og hver rejses egne tal (I027).
- **Hvad det gør:** Noterer hver ændring af pengene med, hvor de kom fra eller gik hen (proviant, brændstof, havnepenge, fjernarbejde, fiskeri osv.), sømilene for sejl og for motor og en kort oversigt over hver rejse, når den slutter. Havnekontoret læser det til driftsomkostningerne, og karrieretestene læser det til deres rapporter.
- **Arbejder sammen med:** `GameSession` (den eneste, der skriver), `SessionState` (gemmes med spillet), havnekontoret, karrieresimulatoren.
- **Holder styr på:** Summerne efter kilde, de seneste par hundrede poster og rejser og rejsen undervejs.
- **Hvornår det kører:** Hver gang penge, brændstof eller båden flytter sig.
- **Hvis du ændrer det:** Hvad driftsomkostningerne og karriererapporterne viser; aldrig selve pengene.

### `src/core/difficulty.gd`

**Formål:** De tre sværhedsgrader: Afslappet, Standard og Erfaren skipper (I022).
- **Hvad det gør:** Læser `data/progression/difficulty.json` og giver faktorerne for det niveau, der spilles: startpenge, hvor hurtigt mad og vand bruges, slid, vejrskader, havneudgifter og redningsgebyret. Standard er 1,0 overalt, spillet som det er tænkt; selve vejret er det samme på alle niveauer. Den giver også hvert niveaus navn og beskrivelse på det valgte sprog.
- **Arbejder sammen med:** `GameSession` (spillets niveau), `SessionState` (startpenge), stederne der bruger faktorerne (`GameSession` proviant, slid, priser på bådpleje og redning; `Simulation` vejrskader), `DifficultyPicker`.
- **Holder styr på:** Niveauerne fra datafilen, læst én gang.
- **Hvornår det kører:** Hver gang et af de tal bruges.
- **Hvis du ændrer det:** Balancen ændres for de niveauer, du redigerer; Standard bør forblive 1,0.

### `src/core/economy.gd`

**Formål:** Driftsomkostningerne ved et liv på vandet samlet ét sted: brændstof og havnepenge (I027).
- **Hvad det gør:** Læser balancefilen `data/economy/economy.json` og svarer på: hvor meget en båds tank rummer og motoren bruger, hvad brændstof koster i en havn (efter egn, lidt mere i små havne), hvad en nats havnepenge er for en båd af en given længde, og hvor mange nætter der ligger mellem to tidspunkter efter havnens eget ur.
- **Arbejder sammen med:** `GameSession` (opkræver dem), `HarbourDressing` (egnen), `HarbourFacilities` (havnens størrelse), `BusinessHours` (havnens ur).
- **Holder styr på:** Intet andet end filen, den læser én gang.
- **Hvornår det kører:** Hver gang brændstof eller havnepenge prissættes.
- **Hvis du ændrer det:** Prisen på brændstof og havne (selve tallene ligger i datafilen).

### `src/core/fishing_state.gd`

**Formål:** Alt om fiskeri om bord, som skal huskes.
- **Hvad det gør:** Gemmer fiskestangen og blinkene, om linen er ude (og om der trolles eller fiskes stille), fiskene i køleboksen, fangstrekorder for hver art, trofætavlen med fem fisk, hvilke fisk du vil beholde, og om hurtig tid stopper ved hvert bid. Hver fisk får sit eget nummer, så den kun kan beholdes, genudsættes, sælges eller tilberedes én gang.
- **Arbejder sammen med:** `SessionState`, `GameSession` (den eneste, der skriver), `FishingCatalog`, fiskemenuen og trofætavlen, `SaveManager`.
- **Holder styr på:** Alt ovenfor. Et bid, der er i gang, gemmes ikke.
- **Hvornår det kører:** Når der fiskes, sælges eller tilberedes fisk; ved gemme og indlæse.
- **Hvis du ændrer det:** Fiskeri, køleboksens størrelse, trofætavlen og "fishing"-delen af gemte spil.

### `src/core/galley_state.gd`

**Formål:** Kabyssens optegnelse: måltider og kaffekruset.
- **Hvad det gør:** Husker, hvornår besætningen sidst fik et varmt måltid (en mæt besætning bruger lidt mindre proviant indtil et bestemt tidspunkt), hvor mange måltider der er lavet, og hvor kaffekruset står (i hånden, i holderen, på bordet).
- **Arbejder sammen med:** `SessionState`, `GameSession`, `SaveManager`.
- **Holder styr på:** Hvor længe besætningen er mæt, antal måltider, sidste måltid og krusets plads.
- **Hvornår det kører:** Når der laves mad eller kaffe, og ved gemme og indlæse.
- **Hvis du ændrer det:** Hvor hurtigt maden slipper op efter et måltid, kaffekruset og "galley"-delen af gemte spil.

### `src/core/game_session.gd`

**Formål:** Vogteren af det kørende spil: det eneste sted, hvor spillets tilstand ændres.
- **Hvad det gør:** Starter, afslutter og indlæser spil og tilbyder alle spillets handlinger: lægge en kurs, sætte sejl, ankomme, redning, penge, proviant, bådpleje, fiskeri, madlavning, ankeret, kaptajnshuen, ledsagerens flytninger, ry og rejseopdateringer. Det melder hver ændring ud med signaler (beskeder et objekt sender, som andre kan lytte efter) og rører aldrig skærmene. Siden I022 købes både (`buy_vessel`, én gang, på et værft, aldrig under nul), og kun både, du ejer, kan sejles; den holder også sværhedsgraden, som skalerer forbrug af mad og vand, slid, priser på bådpleje og proviant og redningsgebyret. I022 fritidssysler: den gemmer postkortet under arbejde (brugt tid bevares ved afbrydelse, smides ud på forlangende), lægger et færdigt kort i scrapbogen med ry første gang for hvert motiv, og tæller det lille spils økter for de timer, der faktisk er arbejdet, med ry for hver milepæl én gang og de første salg ved udgivelsen. I024: ledsageren må gå i land, mens båden er fortøjet, men bliver aldrig efterladt: der kan ikke kastes los, før den er kaldt om bord (`recall_companion`). Landgang i 5 havne og i 3 lande og en uge til søs sammen giver bedrifter for ledsageren; når Kaptajnen vågner, findes den ved køjen, nu og da med en lille linje (`wake_companion`). Vedvarende fart for sejl måles på simulationens egne trin (`note_sailing`: bedste time og bedste døgn, milepæle for 7, 9 og 12 knob i en time og et døgn på 150 sømil), og hver ry-optegnelse noterer nu, hvor og på hvilken båd den blev optjent. I025: der kan være ingen, én eller to ledsagere, så kaldene om ledsagere tager et ledsagernummer (`get_companion(id)`, `get_companions`, `get_companion_count`, `has_room_for_companion`, `set_companion_area(area, spot, id)`, `get_companions_ashore`), og hver ledsager har sin egen tidsplan og plads. Ved hver ankomst til en havn afgør den, om et dyr venter på kajen (`DockEncounters`), og den håndterer de venlige gestus (`befriend_dock_animal`), adoption af dyret (`adopt_dock_animal`: en ny ledsager med navn, køn, og hvornår og hvor den kom om bord, plus optegnelsen "Velkommen om bord" uden omdømme) og "Ikke nu" (`decline_dock_animal`); når der kastes los, bliver et ventende dyr på sin kaj. Opvågning giver én linje om én eller begge ledsagere; båden kaster ikke los, mens en af dem er i land, og at kalde dem om bord henter dem alle. Sejler man alene, er der ingen morgenlinje, og ledsagerens pris for en uge til søs kræver en ledsager. I026: caféen på kajen sælger en kop kaffe til en lille pris, skaleret efter sværhedsgraden som andre udgifter, og intet andet ændres (`buy_cafe_coffee`). Den holder styr på den maritime elektronik: pakken monteret i hver båd (`get_instrument_package`), køb af en pakke i skibshandelen, betalt helt eller slet ikke, monteret med det samme i båden om bord og derefter Kaptajnens til enhver båd (`buy_instrument_package`), gratis montering af en pakke, man ejer, hvor som helst (`fit_instrument_package`), og den side, hvert display viser (`set_instrument_page`), hver meldt med `instruments_changed`. I027: den holder styr på rejsens krydsning (hvor langt fra kurslinjen båden er, hvilken side, vendingerne) og tæller den distance, der faktisk er sejlet gennem vandet. I027 trin 2: hver ændring af pengene noteres i karrierens regnskab; motoren bruger brændstof (og stopper, når tanken er tom); brændstof købes ved tankanlægget; havnepenge betales, når man sejler, for nætterne ved kaj (resten eftergives, hvis pengene ikke rækker); Kaptajnen kan vælge at gå for motor op mod vinden.
- **Arbejder sammen med:** `SessionState` (de data, det ejer), `Simulation` (flytter tiden frem og kalder tilbage), `SaveManager`, `App`, HUD og menuer, mange kataloger (`PortCatalog`, `SeaRouter`, `VesselCatalog`, `ObjectiveCatalog`, `BoatCare`, `FishingCatalog`).
- **Holder styr på:** Den aktuelle `SessionState`, om der er ændringer, der ikke er gemt, og et par ting, der ikke gemmes (en fisk på linen, om kaptajnen sover, om båden ligger roligt for anker, det aktuelle ubrudte stræk for sejl til fartrekorderne).
- **Hvornår det kører:** Altid (en autoload: et script Godot starter automatisk, og som altid findes).
- **Hvis du ændrer det:** Næsten alle spilleregler og hvad der havner i gemte spil. Ændr med stor forsigtighed.

### `src/core/hat_state.gd`

**Formål:** Optegnelsen over kaptajnshuen.
- **Hvad det gør:** Husker, om huen hænger på sin krog, er på hovedet, bæres under armen eller er tabt; hvor meget vind den har taget; hvor mange huer der er tabt og købt; og en kort historik over mindeværdige hue-øjeblikke til Logbogen.
- **Arbejder sammen med:** `SessionState`, `GameSession` (den eneste, der skriver), `Simulation` (vindtjek), `ObjectiveCatalog` (hue-præstationer), hue-mærket og spillerens grafik.
- **Holder styr på:** Alle huens oplysninger ovenfor. Der er kun én hue, og den tilhører spilleren, ikke båden.
- **Hvornår det kører:** På dæk i vind, når huen bruges eller købes, og ved gemme og indlæse.
- **Hvis du ændrer det:** Hvornår huen blæser væk, hue-præstationer og "hat"-delen af gemte spil.

### `src/core/home_state.gd`

**Formål:** "En båd helt din egen": de kahytsting du ejer og hver båds sejl.
- **Hvad det gør:** Husker, hvilke kahytsting du har købt, hvilke der vises på hver båd, og hvilket sejldug hver båd bruger. Ukendte ting fjernes stille, når et spil indlæses.
- **Arbejder sammen med:** `SessionState`, `GameSession`, `HarbourTrades` (listen over pynt og sejldug), menuen "Make it home" og sejlmageren.
- **Holder styr på:** Den pynt du ejer, og valgene for hver båd.
- **Hvornår det kører:** Når du køber eller vælger pynt eller sejl; ved gemme og indlæse.
- **Hvis du ændrer det:** Kahyttens pynt, sejlenes farver og "home"-delen af gemte spil (valgfri, så gamle gemte spil stadig kan indlæses).

### `src/core/loc.gd`

**Formål:** Små hjælpere, så spillet kan tale engelsk eller dansk.
- **Hvad det gør:** Oversætter tekster, vælger ental eller flertal, giver navne på måneder og ugedage og skriver tal på den lokale måde (5.5 eller 5,5; 10,000 eller 10.000).
- **Arbejder sammen med:** Godots oversættelsessystem og det danske katalog `locale/da.po`; bruges af næsten alle scripts, der viser tekst.
- **Holder styr på:** Intet af sit eget (kun et gemt mønster til talformatering).
- **Hvornår det kører:** Når der vises tekst.
- **Hvis du ændrer det:** Tekst og tal overalt i spillet, på begge sprog.

### `src/core/objective_catalog.gd`

**Formål:** Listen over sejlmål og præstationer, der giver ry.
- **Hvad det gør:** Læser målene fra `data/progression/objectives.json`, tilføjer nogle "fjerne horisonter"-mål for fjerne havne og tjekker, hvilke mål en afsluttet rejse eller en hue-hændelse har opfyldt. Den ved også, hvor mange euro en rejseopdatering betaler pr. point ry. Hemmelige præstationer forbliver skjulte, indtil de findes. I024: et mål markeret "retired" (pensioneret) er taget ud af samlingen af bedrifter og Logbogens liste over mål, men betaler stadig sit lille ry som før.
- **Arbejder sammen med:** `GameSession` (spørger efter en rejse eller hue-hændelse), `CaptainsLog`, `ObjectiveProgress`, `HatState`, `PortCatalog`, Logbogens menu, `AchievementCatalog` og laptoppen.
- **Holder styr på:** De indlæste mål (kun til læsning).
- **Hvornår det kører:** Når en rejse slutter, når huen tabes eller købes, og når Logbogen viser mål.
- **Hvis du ændrer det:** Hvilke præstationer der findes, hvor meget ry de giver, og hvor meget rejseopdateringer betaler.

### `src/core/objective_progress.gd`

**Formål:** Dit ry og hvilke mål du har gennemført.
- **Hvad det gør:** Holder ry for hele spillet (falder aldrig), ry der endnu ikke er udgivet, hvert gennemført mål og hvornår, de seneste belønninger og de udgivne rejseopdateringer. Den sikrer, at ingen rejse nogensinde bliver betalt to gange. Siden I024 husker den også, hvor og på hvilken båd et mål første gang blev nået, og hvad det betalte (ældre optegnelser har simpelthen intet sted), personlige rekorder som den bedste time og det bedste døgn for sejl, og hvornår det samlede ry passerede 250 og 1.000.
- **Arbejder sammen med:** `SessionState`, `GameSession` (den eneste, der skriver), `ObjectiveCatalog`, `AchievementCatalog`, Logbogens menu, laptoppen, Go Ashore-hændelser (gå i land).
- **Holder styr på:** Alt ovenfor.
- **Hvornår det kører:** Når der optjenes eller udgives ry; ved gemme og indlæse.
- **Hvis du ændrer det:** Ry, indtægten fra rejseopdateringer og "progress"-delen af gemte spil.

### `src/core/pastimes.gd`

**Formål:** Reglerne for skipperens to fritidssysler om bord: Postkort fra havet og En spiludvikler til søs (I022).
- **Hvad det gør:** Læser `data/pastimes/postcards.json` og `data/pastimes/game_dev.json`. For postkort finder den, hvad et kort kan vise, ud fra spillets egne optegnelser (besøgte havne, fangede fisk, følgesvenden, sejladser, vejret undervejs, aftenlyset hvor båden er), billedteksterne med navnene udfyldt, layoutene, hvor lang tid et kort tager (to timer) og dets ry; hvert motiv giver kun ry én gang. For det lille spil giver den titlen, milepælene, opgaverne (2 til 4 timer hver), hvor mange point en arbejdsøkt giver (dobbelt for det kloge svar) og rækkefølgen svarene vises i. I025: et kort kan vise hver slags ledsager om bord (ét motiv pr. slags; intet, når man sejler alene).
- **Arbejder sammen med:** `GameSession` (gemmer tilstanden og giver ry), `PastimesState`, `PostcardMenu`, `PostcardView`, `GameDevMenu`, skibsloggen, fangstrekorderne, `PortCatalog`, `Daylight`.
- **Holder styr på:** Kun de to datafiler, læst én gang.
- **Hvornår det kører:** Når en fritidsmenu åbnes, og når et kort eller en arbejdsøkt bliver færdig.
- **Hvis du ændrer det:** Ret teksterne i datafilerne (de trækkes ud til oversættelse); hold motiverne bundet til rigtige optegnelser i spillet, så intet kort viser noget, der ikke er sket.

### `src/core/pastimes_state.gd`

**Formål:** Hvad gemmefilen husker om fritidssyslerne: scrapbogen, et postkort under arbejde og det lille spils fremskridt (I022).
- **Hvad det gør:** Holder de lavede postkort (nyeste sidst, højst 40), kortet under arbejde med de minutter, der allerede er brugt på det, og spillets point, milepæl, arbejdsøkter, en afbrudt økt og udviklerdagbogen. Den laver dem om til gemmedata og tilbage; et ældre spil har bare en tom scrapbog, og ødelagte dele udelades i stedet for at afvise spillet.
- **Arbejder sammen med:** `SessionState` (gemt som "pastimes"), `GameSession`.
- **Holder styr på:** `postcards`, `draft`, `game`.
- **Hvornår det kører:** Når spillet gemmes, indlæses og kopieres.
- **Hvis du ændrer det:** Hold indlæsningen tolerant; et afbrudt kort eller en afbrudt økt skal overleve en gemning, så det kan gøres færdigt senere.

### `src/core/provisions.gd`

**Formål:** Proviant: hvor mange dages mad og vand der er om bord.
- **Hvad det gør:** Bruger én dag af hver pr. 24 spiltimer (maden lidt langsommere, når besætningen er mæt), fylder op og afgør, hvornår der skal advares (lav, kritisk, tom). Det skader aldrig nogen at løbe tør; det forhindrer kun næste afgang.
- **Arbejder sammen med:** `SessionState`, `GameSession`, proviantskabet, købmanden, HUD og kahyttens grafik.
- **Holder styr på:** Dage med mad, dage med vand og den seneste advarsel.
- **Hvornår det kører:** Ved hvert skridt i spiltiden og når du handler eller laver mad.
- **Hvis du ændrer det:** Hvor længe du kan sejle, advarslerne og "provisions"-delen af gemte spil.

### `src/core/session_state.gd`

**Formål:** Det komplette gemte billede af ét spil, som rene data.
- **Hvad det gør:** Holder alt, et gemt spil skal bruge (hvor du er om bord, uret, båden og dens position, rejsen, penge, proviant, stand for hver båd, Logbogen, ry, huen, fiskeri, kabys, anker, bådpleje, hjem), og laver det om til gemme-data og tilbage, mens hver del kontrolleres. Siden I022 husker den også, hvilke både kaptajnen ejer, og sværhedsgraden; gemte spil fra før I022 ejer alle både og er Standard. I022: den gemmer også fritidssyslerne (scrapbogen, et kort under arbejde, det lille spil). I024: et nyt spil giver ledsagerens valgte navn og køn videre. I025: den har ledsagerne som en liste (ingen, én eller to, hver med et fast nummer, der aldrig genbruges) og dyrene, man finder på en kaj (`DockEncounters`). Et nyt spil starter uden ledsager; et gemt spil fra før I025 beholder sin ene ledsager som nummer 1, og det gamle felt med én ledsager skrives stadig for den første, så gemmeformatet forbliver version 12. I026: den husker også de instrumentpakker, der ejes, og den, der er monteret i hver båd (`InstrumentState`, den valgfrie del `instruments`); ældre gemte spil får Classic overalt, og gemmeformatet forbliver 12. I027: den holder også brændstoffet i hver båds tank, karrierens regnskab, hvornår båden lagde til, og valget om at gå for motor op mod vinden.
- **Arbejder sammen med:** `GameSession` (ejer og ændrer det), `SaveManager` (skriver og læser det), alle de mindre tilstands-optegnelser i `src/core/`.
- **Holder styr på:** Hele spillets tilstand.
- **Hvornår det kører:** Ved nyt spil, hver gang der gemmes og indlæses, og som data bag hele spillet.
- **Hvis du ændrer det:** Selve gemme-formatet. En ændring her kræver som regel en ny gemme-version og en overgang (migration) i `SaveManager`.

### `src/core/simulation.gd`

**Formål:** Spillets ur og den motor, der flytter båden gennem tiden.
- **Hvad det gør:** Hvert billede laver det rigtig tid om til spiltid (1 rigtigt sekund = 1 spilminut ved 1×) og flytter båden langs kursen, med sejl eller motor efter vinden. Det tjekker vejret, huen, fiskebid, ankeret, trafik og opkald på VHF-radioen på et fast tidsgitter, så resultatet bliver det samme ved enhver hastighed, under søvn og under en Lang passage. Siden I022 skaleres vejrskader efter sværhedsgraden (selve vejret ikke). I022: fjernarbejde fortæller nu også, hvad der stoppede det før tid, så tidsskærmen kan sige det. I024: efter hvert trin fortæller det `GameSession`, hvor hurtigt båden sejlede, og om det var for sejl, til fartrekorderne. I027: den sejler op mod vinden. Kan et ben ikke sejles lige, krydser båden (eller bommer med vinden) i sin bedste vinkel, skifter side ved kanten af et bælte om kurslinjen, før land eller ved et vedvarende vindskift og mister lidt tid ved hver vending; i en havns indsejling holder den sin linje. Ankomstestimatet regner vendingerne med. I027 trin 2: med en tom tank kan motoren ikke starte; og når Kaptajnen vælger at gå for motor op mod vinden, sejles et ben, båden ellers ville krydse op ad, for motor, så længe der er brændstof. Ankomstestimatet regner med brændstoffet om bord: når det er brugt, sejles stilleperioderne langsomt for sejl.
- **Arbejder sammen med:** `GameSession` (læser og opdaterer spillet), `WeatherModel`, `PropulsionController`, `WeatherDamage`, `HatConfig`, `FishingCatalog`, `TrafficModel`, `VhfRadio`; `App` lytter efter dens advarsler.
- **Holder styr på:** Ikke gemt: farten for Lang passage, et gemt (cachet) skøn over ankomsttiden, og om kaptajnen er under dæk.
- **Hvornår det kører:** Altid (en autoload); det står stille, mens spillet er sat på pause.
- **Hvis du ændrer det:** Sejlfart, ankomsttider, vejrvarsler, skader og redninger, tabte huer og bid. Meget følsomt.

### `src/core/vessel_condition.gd`

**Formål:** Navne for, hvor sund en båd er (0–100 %).
- **Hvad det gør:** Sorterer en stand i Sound, Worn, Damaged eller Critical (god, slidt, skadet, kritisk) og skriver den som "87 % · Sound".
- **Arbejder sammen med:** HUD, bådeværftets og passagens paneler, bådens skadesgrafik, `BoatCare`.
- **Holder styr på:** Intet af sit eget; standen ligger i `SessionState`.
- **Hvornår det kører:** Når standen vises.
- **Hvis du ændrer det:** Betegnelser og hvordan bådens skader ser ud.

### `src/core/vhf_radio.gd`

**Formål:** Opkald på VHF-radioen under sejlads.
- **Hvad det gør:** Af og til beder en lystbåd i nød dig om at holde dig i nærheden, eller en fiskerbåd spørger efter vejrudsigten. Om et opkald kommer, er bestemt af rejsen og spillets vejr-frø (seed), så indlæsning eller søvn aldrig bringer det samme opkald to gange. Den skriver også, hvad du hører i radioen.
- **Arbejder sammen med:** `Simulation` (spørger efter opkald), `GameSession` (svar og belønning), VHF-dialogen.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Under sejlads, med nogle timers spiltid imellem.
- **Hvis du ændrer det:** Hvor ofte der kommer opkald, hvor længe man skal holde sig i nærheden, og hvor meget ry og penge de giver.

### `src/diagnostics/session_log.gd`

**Formål:** En lille teknisk dagbog over hver kørsel af spillet, til at finde fejl (ikke spillerens Logbog).
- **Hvad det gør:** Skriver én linje pr. vigtig hændelse (start, skærmskift, gemme, rejser, huen, redninger, penge, fejl) i en fil i brugerens mappe. Filerne holdes små, og kun de 10 nyeste beholdes.
- **Arbejder sammen med:** Signaler fra `GameSession`, `SaveManager`, `App`, `GameVersion`.
- **Holder styr på:** Den åbne logfil og hvor meget der er skrevet.
- **Hvornår det kører:** Altid (en autoload).
- **Hvis du ændrer det:** Kun diagnosefilerne; spillet påvirkes ikke.

### `src/persistence/legacy_saves.gd`

**Formål:** Henter gemte spil fra "Next Harbor", spillets gamle navn.
- **Hvad det gør:** Finder gamle gemte spil i den gamle mappe og kopierer dem, når spilleren siger ja, ind i ledige pladser. De gamle filer ændres aldrig, og en plads, der er i brug, overskrives aldrig.
- **Arbejder sammen med:** `SaveManager`, `App` og hovedmenuen (Import-knappen).
- **Holder styr på:** Intet af sit eget (tests kan pege den på en anden mappe).
- **Hvornår det kører:** Fra hovedmenuen, kun når der findes gamle gemte spil.
- **Hvis du ændrer det:** Import af gamle spil.

### `src/persistence/save_manager.gd`

**Formål:** Gemmer og indlæser spil.
- **Hvad det gør:** Skriver 3 gemmepladser og et hurtig-gem som filer i brugerens mappe, på en sikker måde (en midlertidig fil kontrolleres, og det forrige gemte spil beholdes som backup). Ved indlæsning kontrollerer den filen og opgraderer ældre gemme-versioner trin for trin.
- **Arbejder sammen med:** `SessionState`, `App`, gem/indlæs-menuen, hovedmenuen, `LegacySaves`, `SessionLog`.
- **Holder styr på:** Kun gemmemappens placering; selve de gemte spil er filer.
- **Hvornår det kører:** Altid (en autoload); arbejder når der gemmes, indlæses eller vises pladser.
- **Hvis du ændrer det:** Om gamle gemte spil stadig kan indlæses. Vær meget forsigtig.

### `src/settings/settings_manager.gd`

**Formål:** Spillerens indstillinger, adskilt fra gemte spil.
- **Hvad det gør:** Holder og anvender lydstyrker, vinduestilstand, VSync, interfacets størrelse, grafikstil, den drejende sejlvisning, valg for blink og bevægelse, interfacets dag/nat-lys, sprog og den senest valgte søvnlængde. Ændringer virker med det samme; de skrives først til disken, når der gemmes. Siden I022 findes der også en lydstyrke for vind (100 % som standard, præcis lyden fra før). I022: den gemmer også indstillingen for tips og Skipperskolens fremskridt på denne computer (Gendan standarder beholder fremskridtet).
- **Arbejder sammen med:** Godots lyd og skærm, indstillingsmenuen, `App` (valg af sprog ved første opstart), mange skærme der lytter efter ændringer.
- **Holder styr på:** Alle valgene ovenfor, i `user://settings.cfg`.
- **Hvornår det kører:** Altid (en autoload); indlæses ved opstart.
- **Hvis du ændrer det:** Lydniveauer, skærm- og tilgængelighedsvalg for alle spillere.

## Navigation og vejr

### `src/navigation/anchorage_layer.gd`

**Formål:** Maler blødt farvet vand på søkortet, der hvor båden kan ankre.
- **Hvad det gør:** Når du slår "Anchorages" til og zoomer tæt ind på en kyst, farver det vandet turkis, hvor det almindelige anker når bunden, og ravgult, hvor kun Magic Anchor holder. Det regner søkortet ud i felter på 1 grad ("tiles"), lidt i hvert billede, så spillet aldrig hakker.
- **Arbejder sammen med:** `MapView` (som ejer det), `CoastalGeography` (hvor vandet er), `DepthService` (hvor dybt det er), `SeaRouter` (vand som ruterne allerede bruger), `AnchorSite` (reglerne for ankring).
- **Holder styr på:** De færdige felter som små billeder (højst 48 gemmes), plus nogle tidsmålinger til testene.
- **Hvornår det kører:** Kun på søkortet, kun mens Anchorages-kontakten er slået til, og du er zoomet langt nok ind.
- **Hvis du ændrer det:** Markeringerne kan komme til at være uenige med, hvor spillet faktisk lader dig ankre, eller søkortet kan blive langsomt, når du zoomer langs en kyst.

### `src/navigation/coastal_geography.gd`

**Formål:** Ved præcis, hvor vandet er tæt på en kyst, til brug ved ankring.
- **Hvad det gør:** Læser et fint land/vand-kort over hele verden (omkring en halv sømil pr. felt) og svarer på: er dette sted vand, er det fri af kysten, hvor langt er der til nærmeste land, hvor meget åbent vand er der i vindsiden, og findes der en kort, sikker vej herfra ud til de sejlruter, ruteberegneren bruger.
- **Arbejder sammen med:** `SeaRouter` og `NavGrid` (det grovere sejlkort), `DepthService`, `AnchorSite`, `GameSession`, `AnchorageLayer`.
- **Holder styr på:** Den indlæste kystfil og et lager (cache) med op til 512 udpakkede kortfelter.
- **Hvornår det kører:** Indlæses første gang noget spørger om vand tæt på land (ankring, ankerplads-laget, rutepunkter tæt på land).
- **Hvis du ændrer det:** Hvilke bugter du kan sejle ind i og ankre i, og om et rutepunkt tæt på kysten er tilladt.

### `src/navigation/depth_data.gd`

**Formål:** Læser en rigtig havdybde-fil, hvis en sådan nogensinde bliver installeret.
- **Hvad det gør:** Åbner en særlig dybdefil (lavet af et værktøj ud fra rigtige data om havbunden) og slår dybden op på et vilkårligt punkt. Spillet leveres i dag uden en sådan fil, så den har kun betydning i testene.
- **Arbejder sammen med:** `DepthService` (den eneste bruger).
- **Holder styr på:** Filens bytes og de dybdefelter, den har pakket ud indtil videre.
- **Hvornår det kører:** Kun hvis der findes en dybdefil; i praksis kun i testene.
- **Hvis du ændrer det:** Intet i almindeligt spil; test af rigtige dybdedata kan gå i stykker.

### `src/navigation/depth_service.gd`

**Formål:** Det ene sted, spillet spørger "hvor dybt er vandet her?".
- **Hvad det gør:** Giver en dybde for ethvert sted på havet med en mærkat, der siger, hvor den kommer fra. Da der ikke er installeret rigtige dybdedata, er hver dybde et "GAME ESTIMATE" (et skøn til spillet): dybere jo længere fra land, stejlere ved nogle kyster, lavere i lukkede bugter og i lave have som de danske farvande. Det gør også dybder til venlige ord som "about 9 m".
- **Arbejder sammen med:** `CoastalGeography`, `DepthData`, `AnchorSite`, `AnchorageLayer`, `GameSession`, ankermenuen.
- **Holder styr på:** Intet, der ændrer sig; skønnet er altid det samme på samme sted i alle spil.
- **Hvornår det kører:** Hver gang spillet tjekker en ankerplads eller viser en dybde.
- **Hvis du ændrer det:** Hvor det almindelige anker virker, og hvor du har brug for Magic Anchor, over hele verden.

### `src/navigation/geo_math.gd`

**Formål:** En værktøjskasse med søkort-matematik på længde- og breddegrader.
- **Hvad det gør:** Måler afstande i sømil, regner kompaskurser ud, finder punkter langs en rute og håndterer datolinjen (hvor længdegraden springer fra 180° øst til 180° vest). Det skriver også positioner i den kendte form "55°40.5′N 12°35.0′E". I027: den kan også flytte en kort afstand væk fra en position i en given retning (til bådens afstand fra linjen under krydsning).
- **Arbejder sammen med:** Næsten alle navigationsdele: `SeaRouter`, `Voyage`, `PlannedRoute`, `MapView`, `WeatherModel`, `Simulation`, `GameSession` og mange skærmbilleder.
- **Holder styr på:** Intet af sit eget; det er kun beregninger.
- **Hvornår det kører:** Hele tiden, når noget har brug for en afstand eller en position.
- **Hvis du ændrer det:** Afstande, rejsetider, hvor båden tegnes, og om ruter passer sammen, kan alt sammen gå galt.

### `src/navigation/map_projection.gd`

**Formål:** Gør længde- og breddegrad til flade søkort-koordinater og tilbage igen.
- **Hvad det gør:** Bruger Mercator-projektionen (det klassiske søkort, hvor en lige linje er en fast kompaskurs) til at placere ting på det tegnede søkort.
- **Arbejder sammen med:** `MapView`, `CabinWorldMap` og værktøjet, der forbereder verdens landmasser.
- **Holder styr på:** Kun sin skala (søkort-enheder pr. grad).
- **Hvornår det kører:** Hver gang et søkort tegnes eller klikkes på.
- **Hvis du ændrer det:** Alt på søkortet kan rykke forkert, og den gemte tegning af verdens land passer ikke længere.

### `src/navigation/map_view.gd`

**Formål:** Tegner navigationssøkortet og gør mus og tastatur til handlinger på kortet.
- **Hvad det gør:** Tegner vand, land, kystlinjer, havnemærker og -navne, gradnet, vejrområder, kanaler, kurser, rutepunkter, ankerpladser, båden og nåle for besøgte havne. Det klarer zoom, panorering og at kortet går hele vejen rundt om jorden, og melder klik og træk videre til søkort-skærmen. Det giver også Dreamer's Map dens malede farver. Siden I021 har en særlig havns nål en lille kompasstjerne i messing.
- **Arbejder sammen med:** `WorldMap` (som bestemmer, hvad klik betyder), `MapProjection`, `PortCatalog`, `WeatherModel`, `WeatherStyle`, `WindLayer`, `AnchorageLayer`, `SeaRouter` (kanaler), `NavGrid` (listen over regioner), `WorldLand`.
- **Holder styr på:** Hvad der vises lige nu (kurs, rutepunkter, valgt havn), kameraet, og lagre (caches) af det forberedte land, så søkortet åbner hurtigt næste gang.
- **Hvornår det kører:** Mens kortbordet eller kahyttens Dreamer's Map er åbent.
- **Hvis du ændrer det:** Hvordan søkortet ser ud og føles, hvor hurtigt det åbner og panorerer, og om klik rammer den rigtige havn eller det rigtige rutepunkt.

### `src/navigation/nav_grid.gd`

**Formål:** Sejlkortet, der siger, hvor en båd må sejle.
- **Hvad det gør:** Holder et gitter over verden, hvor hvert felt er åbent vand, "indsejlingsvand" nær havne eller land. Det kan tjekke, om en lige kurs krydser land. Finere gitre for Europa og Danmark ligger inde i verdensgitteret, og verden hænger sammen hele vejen rundt ved datolinjen.
- **Arbejder sammen med:** `SeaRouter` (den vigtigste bruger), `CoastalGeography`, `AnchorageLayer`, `WindLayer`, `MapView`, kortplotteren.
- **Holder styr på:** Gitterfelterne indlæst fra datafilerne og sine finere regionale gitre.
- **Hvornår det kører:** Indlæses én gang sammen med ruteberegneren (på indlæsningsskærmen) og bruges derefter ved hvert rutetjek.
- **Hvis du ændrer det:** Ruter kan komme til at krydse land, eller rigtige sejlruter kan blive spærret.

### `src/navigation/planned_route.gd`

**Formål:** En planlagt kurs: hvor den starter, dine rutepunkter, destinationen og den præcise linje, der skal sejles.
- **Hvad det gør:** Holder den kurs, ruteberegneren fandt, hvilke rutepunkter der er ankerpladser, og deler den op i stræk. Den kan beskrive sig selv ("Copenhagen → Kiel · 152 nm") og gøre sig til gemte data og tilbage igen, og tjekker, at gemte data giver mening.
- **Arbejder sammen med:** `SeaRouter` (laver den), `Voyage`, `GameSession`, `SessionState`, `WorldMap`, `PortCatalog`.
- **Holder styr på:** Start, rutepunkter, markering af ankerpladser, destination og rutens punkter.
- **Hvornår det kører:** Hver gang en kurs planlægges, sejles, gemmes eller indlæses.
- **Hvis du ændrer det:** Gemte spil (planlagte kurser og sejladser) kan holde op med at kunne indlæses, eller båden kan sejle en anden linje end den, søkortet viser.

### `src/navigation/port_catalog.gd`

**Formål:** Listen over alle havne i spillet.
- **Hvad det gør:** Finder havne ud fra deres id, ud fra område (kun dem på skærmen) eller ud fra navn i havnesøgningen.
- **Arbejder sammen med:** `PortData` (hver havn), `MapView`, `WorldMap`, `SeaRouter`, `GameSession`, gemmesystemet og mange menuer.
- **Holder styr på:** Havnene fra `data/navigation/port_catalog.tres` og hurtige opslagsregistre.
- **Hvornår det kører:** Indlæses på indlæsningsskærmen og deles af hele spillet.
- **Hvis du ændrer det:** Havnesøgningen, hvilke havne der vises på søkortet, og om gemte spil genkender deres havne.

### `src/navigation/port_data.gd`

**Formål:** Oplysningerne om én havn.
- **Hvad det gør:** Gemmer havnens id, navn (vist på dit sprog), land, position, beskrivelse og hvor vigtig den er (det bestemmer, fra hvilket zoomniveau den vises på søkortet). Siden I021 giver den også havnens sætning på det valgte sprog.
- **Arbejder sammen med:** `PortCatalog` og alt, der viser havne eller laver ruter til dem.
- **Holder styr på:** Kun den ene havns oplysninger.
- **Hvornår det kører:** Indlæses sammen med havnelisten.
- **Hvis du ændrer det:** Ændrer du en havns `id`, går gemte spil, der nævner den, i stykker; ændrer du dens position, flytter den på søkortet, og ruterne ændrer sig.

### `src/navigation/sea_router.gd`

**Formål:** Regner sejlruter ud, der aldrig krydser land, og tjekker ruter.
- **Hvad det gør:** Finder en kurs mellem havne og gennem dine rutepunkter ved hjælp af et forberedt net af punkter i åbent vand og retter den derefter ud. Den finder vejen ud af hver havn, kan bruge Kielerkanalen og Suezkanalen og kan nå ankerpladser tæt på kysten. Den tjekker også en hel rute, før den bruges, og flytter et rutepunkt, der er sat på land, ud til nærmeste vand.
- **Arbejder sammen med:** `NavGrid`, `PortCatalog`, `PlannedRoute`, `CoastalGeography`, `GeoMath`, `GameSession`, `WorldMap`, `VoyageDaydream`, `TrafficModel`.
- **Holder styr på:** Rutenettet, vejene ud af havnene og nylige rutestykker (i et lager/cache).
- **Hvornår det kører:** Indlæses på indlæsningsskærmen; bruges hver gang en kurs sættes ud eller ændres.
- **Hvis du ændrer det:** Hvilke steder der kan nås, hvor lange ruterne er, og om ruter nogensinde krydser land.

### `src/navigation/traffic_model.gd`

**Formål:** Finder på andre skibe på havet til radaren og VHF-radioen.
- **Hvad det gør:** Placerer fragtskibe, tankskibe, færger, fiskerbåde og lystsejlere nær båden, flere nær travle havne. Hvert skib følger et lige spor på vandet. Samme sted og tid giver altid de samme skibe, også efter indlæsning af et gemt spil. Den regner også ud, hvor tæt et skib vil passere.
- **Arbejder sammen med:** `Simulation`, radarpanelet, `VhfRadio`, `SeaRouter`, `PortCatalog`.
- **Holder styr på:** Et lager (cache) af skibsspor; intet gemmes.
- **Hvornår det kører:** Når spillet leder efter skibe i nærheden (radar, advarsler om trafik).
- **Hvis du ændrer det:** Hvor travlt havet føles, og hvornår du får advarsler om skibe, der passerer tæt forbi.

### `src/navigation/vessel_profile.gd`

**Formål:** Hvor hurtigt én båd sejler, og hvornår den skifter til motoren.
- **Hvad det gør:** Gør vindstyrke og vindvinkel til en sejlfart (med en spiler-bonus for vind agten fra), giver motorfarten, reglerne for hvornår der skal motorsejles, og hvor godt båden klarer hårdt vejr. I027: den bidevindsdel af kurven er hævet til, hvad en tursejler faktisk gør op mod vinden, og hver båd har den tid, en vending koster den.
- **Arbejder sammen med:** `GameSession`, `PropulsionController`, `WeatherDamage`, `VesselDefinition`, menuen på bådeværftet.
- **Holder styr på:** Bådens indstillingstal (gemt i bådfiler som `data/vessel/starter_sloop.tres`).
- **Hvornår det kører:** Hver gang båden sejler.
- **Hvis du ændrer det:** Bådenes fart, rejsetider og hvor ofte motoren kører.

### `src/navigation/voyage.gd`

**Formål:** Den sejlads, du er i gang med lige nu.
- **Hvad det gør:** Holder den kurs, der sejles, og hvor langt båden er nået ad den; bådens position regnes altid ud fra disse to. Den gemmer også sejladsens tal til Logbogen (sejlet distance, værste vejr, skader), stop ved ankerpladser og at ligge stille og vente på et skib i nød. I027: den holder også bådens krydsning - hvor langt fra kurslinjen den er og på hvilken side - så den position, alle læser, har den forskydning med.
- **Arbejder sammen med:** `PlannedRoute`, `GameSession`, `SessionState`, gemmesystemet, `WorldMap`, `CaptainsLog`.
- **Holder styr på:** Hvor langt båden er nået, kursens version, advarsler der allerede er givet, oplysninger om afgangen, logbogstal, fremskridt ved ankerpladser.
- **Hvornår det kører:** Mens båden er undervejs.
- **Hvis du ændrer det:** Hvor båden er, gemte spil midt i en sejlads og tallene i Logbogen.

### `src/navigation/voyage_daydream.gd`

**Formål:** Skriver kaptajnens dagdrøm om en fjern sejlads på Dreamer's Map.
- **Hvad det gør:** Når du trykker "Imagine this voyage", planlægger den en rigtig rute, vælger op til tre rigtige havne undervejs og skriver nogle venlige linjer i én af fem stemninger. Den ændrer aldrig noget i spillet.
- **Arbejder sammen med:** `SeaRouter`, `PortCatalog`, `PassageReadiness`, `GameSession`, `WorldMap`.
- **Holder styr på:** Et lille lager (cache) af de seneste dagdrømme.
- **Hvornår det kører:** Kun når du beder om det på Dreamer's Map.
- **Hvis du ændrer det:** Kun dagdrømmens tekst og den rute, den viser.

### `src/navigation/weather_legend.gd`

**Formål:** Den lille signaturforklaring i søkortets Weather-fane, der forklarer vejrsymbolerne.
- **Hvad det gør:** Tegner én linje pr. slags vejr (kuling, tordenrisiko, tordenvejr, cyklon) med farve, omrids, symbol og navn.
- **Arbejder sammen med:** `WeatherStyle`, `WorldMap` (som tilføjer den).
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Mens søkortets Weather-fane vises.
- **Hvis du ændrer det:** Kun hvordan forklaringen ser ud.

### `src/navigation/weather_style.gd`

**Formål:** Bestemmer, hvordan hver slags vejr ser ud på søkortet.
- **Hvad det gør:** Én tabel med farver, udfyldning, stregtyper (fuld, stiplet, prikket) og mærkater, plus kode der tegner symbolerne (vindstreger, sky, lyn, spiral). Både søkortet og forklaringen bruger den, så de altid passer sammen.
- **Arbejder sammen med:** `MapView`, `WeatherLegend`, `WorldMap`, `WeatherEvent`, `WeatherModel`.
- **Holder styr på:** Intet, der ændrer sig.
- **Hvornår det kører:** Hver gang der tegnes vejr på søkortet.
- **Hvis du ændrer det:** Udseende og mærkater på vejrområderne.

### `src/navigation/wind_layer.gd`

**Formål:** Søkortets vindpile og den svage farvetone på havet.
- **Hvad det gør:** Viser, hvor vinden blæser hen, farvet efter styrke, med præcis den samme vind, som båden sejler i. Du kan flytte billedet op til seks timer frem eller tilbage. Det arbejder lidt i hvert billede, så panorering forbliver glat, og skjuler sig, når der er zoomet langt ud ("Zoom in to see wind details").
- **Arbejder sammen med:** `MapView` (som ejer det), `WeatherModel`, `NavGrid`, `GameSession`, `WorldMap` (knapper og forklaring).
- **Holder styr på:** De seneste vindbilleder (op til 14 tidspunkter) og hvilke gitterpunkter der er land.
- **Hvornår det kører:** Kun mens søkortet er åbent, og Wind-kontakten er slået til.
- **Hvis du ændrer det:** Kun hvad søkortet viser; den rigtige sejlvind afhænger ikke af det.

### `src/navigation/world_land.gd`

**Formål:** En færdigpakket samling af verdens landformer til søkortet.
- **Hvad det gør:** Holder verdens landomrids, der allerede er omregnet til søkort-koordinater, så søkortet åbner hurtigt uden at læse en stor tekstfil.
- **Arbejder sammen med:** `MapView`, `CabinWorldMap` og værktøjet `tools/navigation/world_land_to_res.gd`, der laver den.
- **Holder styr på:** Landformer, kystlinjer, små øer som prikker og stednavne.
- **Hvornår det kører:** Indlæses, første gang et søkort åbnes.
- **Hvis du ændrer det:** Verdensfilen skal bygges igen med værktøjet, ellers falder søkortet tilbage på den langsommere tekstfil.

### `src/navigation/world_map.gd`

**Formål:** Søkort-skærmen: planlæg, ret og følg din kurs.
- **Hvad det gør:** Styrer kortbordet: vælg en destination, sæt en kurs, tilføj, træk og fjern rutepunkter, markér ankerpladser, og tryk Apply eller Discard. Den viser status, forventet ankomst, vind, vejret langs kursen og Passage Readiness (klarhed til sejladsen), har en havnesøgning og slår vind- og ankerpladslagene til og fra. I kahytten bliver den til Dreamer's Map med "Imagine this voyage". Siden I021 fortæller detaljerne for en særlig havn også, hvorfor den er særlig, og havnens sætning følger sproget.
- **Arbejder sammen med:** `MapView`, `GameSession`, `SeaRouter`, `PortCatalog`, `Simulation`, `VoyageDaydream`, `PassageReadiness`, `AnchorSite`, `WeatherLegend`, `WindLayer`.
- **Holder styr på:** Udkastet til den kurs, der rettes i (den ændrer aldrig din rigtige kurs, før du trykker Apply).
- **Hvornår det kører:** Når kortbordet eller kahyttens kort åbnes.
- **Hvis du ændrer det:** Hvordan kursplanlægning virker, og søkort-skærmens opbygning og knapper.

### `src/electronics/instrument_data.gd`

**Formål:** Én aflæsning af alt, hvad bådens instrumenter viser, taget fra spillets egne data (I026).
- **Hvad det gør:** Samler fart, kurs, den sande vind og dens vinkel til stævnen, vindstød og et ord om vejret, ruten (destination, distance tilbage, ankomsttid), næste sving og vejrudsigten for næste strækning, ankeret og (kun til ankers) dybden og, når der spørges, udsigten for de næste 3, 6 og 12 timer. Den regner intet ud selv: alt kommer fra spillets tilstand, simuleringen og søkortets næste sving, så de billigste instrumenter viser nøjagtig det samme vigtige som de dyreste. Der er ingen tilsyneladende vind og intet ekkolod under sejlads, fordi spillet ikke simulerer dem. Den gemmer også aflæsningerne som sætninger (de ord, det gamle sejlpanel brugte). I027: på en halse siger kurslinjen, hvilken ("styrbord halse, krydser op mod vinden"), og en linje om krydsningen giver fremdriften mod kursen og omtrent hvornår næste vending kommer.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `WorldMap` (næste sving), `Hud` (vindordene), `PropulsionState`, `SailTrim`, `DepthService`, `AnchorSite`; læses af `InstrumentCluster`, `InstrumentView` og `PlotterView`.
- **Holder styr på:** Værdierne i én aflæsning; vejrudsigter gemmes pr. strækning og pr. halve time spiltid.
- **Hvornår det kører:** Nogle gange i sekundet, mens instrumenterne er på skærmen.
- **Hvis du ændrer det:** Hvad alle instrumenter viser; tallene skal fortsat komme fra spillets egne kilder.

### `src/electronics/instrument_face.gd`

**Formål:** Hvordan instrumenterne ser ud: tegningen af skiver, displays og multifunktionsskærmen for alle tre instrumentpakker (I026).
- **Hvad det gør:** Tegner i enhver størrelse Classic-pakkens runde analoge skiver (fart, kurs, vind) og dens LCD-repeater, Modern Cruisers firkantede farvedisplays med deres sider (fart, kurs, vind, rute, næste sving, vejr, trim) og Offshore Navigators brede multifunktionsdisplay med dets opstillinger (oversigt, sejlads, navigation, vejr), hver i sit hus med glas, belysning om natten, et kompasbånd, en vindrose med røde og grønne sektorer for bidevind og en "motorvejs"-visning af kursen. Al tekst skrumper, så den passer til sin plads, også lange danske ord. Den tegner kun ud fra én aflæsning og læser aldrig selv spillet. De mange små streger rundt om en skive tegnes i to strøg (store og små), så skiverne er billige at tegne hvert billede til søs.
- **Arbejder sammen med:** `InstrumentData` (hvad der skal vises), `InstrumentPackage` (farver og stil); bruges af `InstrumentCluster`, `InstrumentView` og `PlotterView`.
- **Holder styr på:** Intet (kun de indlæste skrifttyper).
- **Hvornår det kører:** Hver gang et instrument tegnes igen (nogle gange i sekundet).
- **Hvis du ændrer det:** Udseendet af alle instrumenter i HUD'en, i nærbillederne og rundt om plotteren.

### `src/electronics/instrument_package.gd`

**Formål:** En af de tre instrumentpakker, en båd kan have: Classic, Modern Cruiser og Offshore Navigator fra det opdigtede mærke SKERRY (I026).
- **Hvad det gør:** Læser listen over pakker fra `data/electronics/instrument_packages.json`: Classic (analoge skiver og en LCD-repeater, på alle både, gratis), Modern Cruiser (kompakte displays med sider) og Offshore Navigator (et multifunktionsdisplay med opstillinger). Hver har navn, model, tekst, pris, displays og sider og farver om dagen og om natten. Alle viser de samme data, så den billige aldrig er mindre sikker; de adskiller sig kun i udseende og opstilling.
- **Arbejder sammen med:** `InstrumentState` (hvilke der ejes og er monteret), `GameSession`, `ChandleryMenu` (sælger dem), `InstrumentFace`, `CockpitInstruments`, `InstrumentCluster`, `InstrumentView`, `PlotterView`, `SystemsView`.
- **Holder styr på:** Kataloget, indlæst én gang.
- **Hvornår det kører:** Når instrumenterne tegnes, eller skibshandelen er åben.
- **Hvis du ændrer det:** Pakkernes priser og udseende; id'erne ligger i de gemte spil.

### `src/electronics/instrument_state.gd`

**Formål:** Hvilke instrumentpakker Kaptajnen ejer, og hvilken der er monteret i hver båd (I026).
- **Hvad det gør:** Husker de købte pakker (Classic ejes altid), pakken monteret i hver båd (Classic, når intet er valgt) og den side, hvert display viser. En pakke, der én gang er købt, er Kaptajnens til enhver båd og går aldrig tabt. Den laver det om til gemme-data og tilbage og afviser aldrig et gemt spil: ældre gemte spil har bare Classic overalt, og ukendte dele springes stille over.
- **Arbejder sammen med:** `SessionState` (gemmer den som den valgfrie del `instruments`), `GameSession` (ændrer den), `InstrumentPackage`.
- **Holder styr på:** Ejede pakker, den monterede pakke pr. båd og de valgte sider.
- **Hvornår det kører:** Når instrumenter købes, monteres eller skifter side, og ved hver gemning og indlæsning.
- **Hvis du ændrer det:** De gemte spil; gemmeformatet er stadig 12, så nye felter skal have sikre standardværdier.

### `src/ui/fuel_menu.gd`

**Formål:** Tankanlæggets pumpe på kajen (I027).
- **Hvad det gør:** Viser, hvad der er i bådens tank, og hvor langt det rækker for motor, prisen her og dine penge, og fylder tanken op eller tilføjer ti liter - så meget som pengene rækker. Åbent på alle tider, i alle havne.
- **Arbejder sammen med:** `GameSession` (buy_fuel, tanken), `App` (åbner den fra kajens pumpe, indrammet som stål).
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Mens den er åben.
- **Hvis du ændrer det:** Hvordan brændstof købes (prisen kommer fra balancefilen).

### `src/ui/instrument_draw.gd`

**Formål:** Små fælles tegnehjælpere til instrumentlignende brugerflade (Real Horizon).
- **Hvad det gør:** Tegner instrumentskiver med kant og streger, buer, slanke visere, datafelter, hjørnebeslag, omrids og pilespidser i temaets farver, så hjul, sejltrim, radar, kortplotter og piktogrammer ligner ét sæt marineinstrumenter.
- **Arbejder sammen med:** `ReelDial`, `SailTrimPanel`, `RadarPanel`, `ChartPlotter`, `GoAshoreMenu`, `CookingMenu`, `HaulOutScene`, `UiTheme`.
- **Holder styr på:** Intet; statiske hjælpere (indlæst med preload, intet klassenavn).
- **Hvornår det kører:** Mens de paneler tegnes.
- **Hvis du ændrer det:** Alle instrumentskiver på én gang.

### `src/water/sea_surface.gd`

**Formål:** Det illustrerede hav omkring båden (Real Horizon).
- **Hvad det gør:** Sætter havets shader (`sea_surface.gdshader`) på dækkets vandpolygon og giver den vindretning og søgang ved båden, havnens læ, stormvejr, regn og sollys, så vejret glider langsomt ind. Dønning og krusninger følger vinden; skumtoppe og skumstriber kommer fra omkring 18 kn.
- **Arbejder sammen med:** `BoatArea` (opretter den), `Simulation` (vejret ved båden), `GameSession`, `Daylight`, `WeatherAudio` (regn), `MarinePalette`.
- **Holder styr på:** Nuværende og ønsket søgang, læ, storm, regn og sol, og hvor langt mønsteret er strømmet agterud.
- **Hvornår det kører:** På dækket, hvert billede (én vejrprøve hvert 0,5 s).
- **Hvis du ændrer det:** Hvordan havet ser ud i alt slags vejr; kun visning, simuleringen røres aldrig.

### `src/weather/weather_event.gd`

**Formål:** Ét stykke farligt vejr: et kulingområde, et område med tordenrisiko, et tordenvejr eller en tropisk cyklon.
- **Hvad det gør:** Beskriver, hvor hændelsen er, hvor stor og hvor kraftig den er på ethvert tidspunkt, mens den vokser, bevæger sig og aftager, med et lidt uregelmæssigt omrids og, for tordenvejr, byger med vindstød. At spørge til den ændrer den aldrig.
- **Arbejder sammen med:** `WeatherModel` (som skaber hændelserne), `WeatherStyle`, `MapView`, `Simulation`, vejrlyde.
- **Holder styr på:** Nogle få faste tal, der bestemmes, når hændelsen opstår.
- **Hvornår det kører:** Hver gang vejret aflæses eller tegnes.
- **Hvis du ændrer det:** Hvordan uvejr bevæger sig, og hvor kraftige de føles; det samme seed (startværdi for tilfældigheden) vil give et andet vejr.

### `src/weather/weather_exposure.gd`

**Formål:** Husker, hvilket vejr båden er i lige nu, og siden hvornår.
- **Hvad det gør:** Noterer det aktuelle fareniveau, hvilken hændelse der er skyld i det, og den kraftigste vind og de kraftigste vindstød undervejs. Det nulstilles i havn.
- **Arbejder sammen med:** `SessionState` (ejer det), `GameSession` (opdaterer det, med data fra `Simulation`), `SaveManager`, `WeatherModel`, `WeatherSample`.
- **Holder styr på:** Fareniveau, starttid, vejrtype, hændelsens id, største vind og største vindstød.
- **Hvornår det kører:** Opdateres hvert 5. spilminut, mens båden er undervejs.
- **Hvis du ændrer det:** Gemte spil (det gemmes i dem). Kun lidt i spillet reagerer på det i dag, men testene bruger det til at tjekke, at vejret er det samme ved alle spilhastigheder.

### `src/weather/weather_model.gd`

**Formål:** Spillets vejr: det ene svar på "hvordan er vejret her, lige nu?".
- **Hvad det gør:** Starter fra den almindelige vind (`WindField`) og lægger kuling, områder med tordenrisiko og tordenvejr samt tropiske cykloner oven i, hver dannet efter årstid og havområde. Det giver vind, vindstød, fareniveau og en vejrtype og kan liste de uvejr, der findes på et tidspunkt. Samme seed, sted og tid giver altid det samme vejr.
- **Arbejder sammen med:** `WindField`, `WeatherEvent`, `WeatherSample`, `Simulation`, `GameSession`, `MapView`, `WindLayer`, HUD'en (skærmens faste visning), vejrlyde og mange andre.
- **Holder styr på:** Vejrindstillingerne fra `data/weather/weather_events.json` og lagre (caches) af hændelser.
- **Hvornår det kører:** Altid, når noget spørger om vejret.
- **Hvis du ændrer det:** Hvert uvejr, hver advarsel, al vejrskade og al sejlfart i spillet.

### `src/weather/weather_sample.gd`

**Formål:** Vejret på ét sted og tidspunkt, samlet i én pakke.
- **Hvad det gør:** Holder den jævne vind, vindstød, baggrundsvind, fareniveau, vejrtype, det ansvarlige uvejr, tordenmarkeringer og risikoen for cyklonsæson.
- **Arbejder sammen med:** `WeatherModel` (udfylder den), `Simulation`, `GameSession`, `AnchorSite`, HUD'en, `WorldMap`, vejrlyde.
- **Holder styr på:** Kun værdierne fra den ene aflæsning.
- **Hvornår det kører:** Hver gang der spørges om vejret.
- **Hvis du ændrer det:** Alt, der læser vejrdetaljer (advarsler, tekster i HUD'en, ankring).

### `src/weather/wind_field.gd`

**Formål:** Den almindelige baggrundsvind overalt i verden.
- **Hvad det gør:** Blander typiske vinde fra omkring 40 steder i Europa og fra verdens vindbælter (passatvinde, vestenvinde, stille områder) til en jævn vind og lægger langsomme ændringer over dage oveni. Samme sted, tid og seed giver altid den samme vind. Den giver også kompasnavne som "WSW" (på dansk "VSV").
- **Arbejder sammen med:** `WeatherModel` (den vigtigste bruger), `PropulsionController`, HUD'en, `Simulation`, `AnchorSite`, radaren og instrumenterne.
- **Holder styr på:** Vindindstillingerne fra `data/weather/wind_climate.json` og to forudberegnede vindgitre.
- **Hvornår det kører:** Altid, når der er brug for vind.
- **Hvis du ændrer det:** Vinden overalt og dermed sejlfart og rejsetider.

## Både, dæk, kahytter og verden omkring dem

### `src/aboard/anchor_ambience.gd`

**Formål:** Regner stemningen "en stille aften for anker" ud (en farvetone og hvor stærkt kahytslampen lyser), mens båden ligger roligt for anker.
- **Hvad det gør:** Hvert halve sekund ser den på tidspunktet på dagen, og om båden ligger roligt for anker, og glider så tonen og lampens skær mod den rette stemning. Siden Iteration 17 viser den ikke selv noget (den er skjult); bådens belysning står for det rigtige lys, og denne node gemmer kun tallene til ankerøjeblikkene og testene.
- **Arbejder sammen med:** `GameSession` (tid på dagen, roligt for anker), `AnchorLife` (farvetoner og lampestyrker), `BoatArea` (som tilføjer den og fortæller, hvor kahytslamperne er).
- **Holder styr på:** Nuværende og ønsket farvetone og lampestyrke samt listen over lampernes pladser i kahytten.
- **Hvornår det kører:** Når du er på dækket eller i kahytten (én pr. bådområde).
- **Hvis du ændrer det:** Man ser ikke meget af det i spillet i dag; det er mest testene af ankerstemningen, der vil mærke det.

### `src/aboard/anchor_life.gd`

**Formål:** Regelbogen for et roligt og sikkert ophold for anker: hvad klokken er om bord, og hvilke stille linjer spillet viser.
- **Hvad det gør:** Omsætter spiltiden og bådens længdegrad til en lokal time og en fase (morgen, dag, aften, nat). Indeholder farvetonerne, lampestyrkerne og de korte, stille linjer ("The anchor holds. The sea is quiet.") og vælger én på en måde, der giver samme resultat hver gang.
- **Arbejder sammen med:** `GameSession` (som afgør, hvornår båden ligger roligt, og husker øjeblikkene), `AnchorAmbience`, `AboardBadge`, `CompanionState` (linjerne om katten og hunden).
- **Holder styr på:** Intet selv; kun faste regler og tekster.
- **Hvornår det kører:** Når spillet spørger om tiden på dagen om bord eller om et øjeblik for anker.
- **Hvis du ændrer det:** Tidspunkterne for aften og nat, vindgrænsen for at ligge "roligt" (18 kn), ventetiden før den første stille linje og de tekster, Kaptajnen læser for anker, ændres alle.

### `src/aboard/cabin_decor.gd`

**Formål:** Tegner en af Kaptajnens hyggelige ting i kahytten (tæppe, krydderurter, indrammet søkort, olielampe, bogreol, signalflag) og finder en god plads til hver.
- **Hvad det gør:** Hver ting tegnes med enkle former i Real Horizon-materialerne og har ingen kollision (man kan gå hen over den). En hjælpefunktion sætter vægting langs skrogets sider, skiftevis styrbord og bagbord, og tæppet på åbent gulv nær midten, altid fri af stationer og ledsagerens hvilepladser. Den samme kahyt giver altid de samme pladser. Siden I021 tegner den også et modelskib, et glas med havglas og et barometer i messing, og siden Operation Paperwork et kompas i messing. Ting, der ikke finder en væg i første forsøg, får et nyt kig, også inde fra hvert skrog og lidt tættere sammen, så alle ti får plads i hver kahyt; intet, der allerede har en plads, flytter sig.
- **Arbejder sammen med:** `BoatArea` (opretter og placerer dem), `HarbourTrades` (listen over pynteting, og om de hører til på væg eller gulv), `CabinHomeMenu` (hvor Kaptajnen vælger dem).
- **Holder styr på:** Hvilken ting den er, og hvilken side den hænger på.
- **Hvornår det kører:** I kahytten, når den indlæses, eller når Kaptajnen ændrer valget af pynt.
- **Hvis du ændrer det:** Kahytspyntens udseende og placering; en placeringsfejl kunne lægge en ting over en station eller kattens seng.

### `src/aboard/cabin_object.gd`

**Formål:** De ting, en sejler bruger under dæk, som rigtige genstande i kahytten: logbogen, VHF-radioen, el-tavlen, sømandskisten og det nyeste postkort (I026).
- **Hvad det gør:** Tegner hver genstand, hvor den hører hjemme: den indbundne logbog og radioen ved kortbordet, el-tavlen ved motorkassen eller kabyssen, sømandskisten ved fodenden af køjen og, når der er et, det nyeste postkort stillet op på salonbordet. Hver har sin egen E-station; logbogen åbner Kaptajnens logbog som en bog, radioen VHF-radioens visning, tavlen bådens systemer, kisten "Make it home" og postkortet scrapbogen. Pladserne findes ud fra kahyttens egne møbler, på et sted Kaptajnen kan stå ved, og ikke oven i en anden station, så alle både får dem uden håndplacerede markører; mangler kahytten møblet, mangler den bare genstanden. Radioens lampe blinker, mens et opkald venter.
- **Arbejder sammen med:** `BoatArea` (placerer dem og sender ønsket videre), `App` (åbner visningerne), `Interactable`, `BoatFixture`, `GameSession` (om der er et postkort).
- **Holder styr på:** Hvilken genstand det er, og om et radioopkald venter (til lampen).
- **Hvornår det kører:** I kahytten.
- **Hvis du ændrer det:** Hvor kahyttens genstande står, og om Kaptajnen kan nå dem på alle både; de har ingen kollision og spærrer aldrig for at gå.

### `src/aboard/coffee_mug.gd`

**Formål:** Tegner Kaptajnens kaffekrus, hvor det står: i kopholderen ved roret på dækket eller på bordet i kahytten.
- **Hvad det gør:** På dækket tegner den altid kopholderen i rustfrit stål og kruset i den, når kaffen står der. Den tegner igen, når kaffen flyttes. Den har også en krus-tegning, som sømandsfiguren bruger, når den bærer kaffen.
- **Arbejder sammen med:** `GameSession` (hvor kaffen er), `BoatArea` (opretter kopholderen og kruset på bordet), `SailorDrawing` (låner krus-tegningen).
- **Holder styr på:** Kun hvilket sted den viser ("holder" eller "table").
- **Hvornår det kører:** Når du er på dækket eller i kahytten.
- **Hvis du ændrer det:** Hvordan kruset og holderen ser ud på dækket, på bordet og i Kaptajnens hånd.

### `src/aboard/galley_stove.gd`

**Formål:** Tegner det lille komfur med to blus i kabyssen med en pande, der damper, efter et måltid er lavet.
- **Hvad det gør:** Tegner komfur og pande; når et måltid er lavet, tændes blussene, og der stiger damp op i cirka 12 sekunder. Den viser kun ting: stationen ved siden af åbner madlavningsmenuen.
- **Arbejder sammen med:** `GameSession` (beskeden om, at et måltid er lavet), `BoatArea` (placerer den), `HighlightResolver` (dens omrids til fremhævningen, når den er i fokus).
- **Holder styr på:** Hvor længe dampen har tilbage, og et lille animationsur.
- **Hvornår det kører:** I kahytten.
- **Hvis du ændrer det:** Kun udseendet af komfuret og dampen.

### `src/aboard/rod_holder.gd`

**Formål:** Tegner fiskestangen i sin holder på hækrælingen, med linen slæbende agter ud og spidsen, der nikker, når en fisk bider.
- **Hvad det gør:** Tegner holder, stang og hjul; mens linen er ude, tegnes en blødt bevægende line ned i vandet; når en fisk har bidt på, nikker stangens spids. Stationen ved siden af åbner fiskemenuen.
- **Arbejder sammen med:** `GameSession` (linen ude, fisk på krogen), `BoatArea` (placerer den på bagbords ræling nær agterenden).
- **Holder styr på:** Et lille animationsur.
- **Hvornår det kører:** På dækket.
- **Hvis du ændrer det:** Kun hvordan stangen ser ud og bevæger sig; reglerne for fiskeri ligger andre steder.

### `src/aboard/trophy_board.gd`

**Formål:** Trofætavlen af træ på kahytsvæggen med fem pladser til Kaptajnens mest bemærkelsesværdige fangster.
- **Hvad det gør:** Viser et lille billede af hver trofæfisk (eller en farvet fiskeform) og svage omrids for tomme pladser ("endnu ikke fanget"). Den opdateres, når fiskeriet ændrer sig, eller et spil indlæses. Stationen ved siden af åbner trofælisten.
- **Arbejder sammen med:** `GameSession` (fiskeriets optegnelser), `FishingState` (antal trofæer), `FishArt` (fiskebilleder), `BoatArea` (placerer den), `HighlightResolver`.
- **Holder styr på:** De fem billedholdere på tavlen.
- **Hvornår det kører:** I kahytten.
- **Hvis du ændrer det:** Tavlens udseende; rækkefølgen af trofæerne afgøres andre steder.

### `src/aboard/windlass.gd`

**Formål:** Tegner ankerspillet (spillet til ankerkæden) på fordækket.
- **Hvad det gør:** Når ankeret er oppe, tegnes det stuvet i stævnrullen; for anker tegnes kæden, der løber over stævnen ned i vandet, og en pulserende rød ring, hvis ankeret glider (drager). Stationen ved siden af åbner ankermenuen.
- **Arbejder sammen med:** `GameSession` (for anker eller ej, ankerets tilstand), `AnchorState`, `BoatArea` (placerer den på fordækket).
- **Holder styr på:** Hvor stævnrullen er, og et lille animationsur.
- **Hvornår det kører:** På dækket.
- **Hvis du ændrer det:** Kun udseendet af ankerspil og kæde, også advarselsbilledet når ankeret glider.

### `src/boat/anchor_signals.gd`

**Formål:** Viser alle, at båden ligger for anker: den sorte ankerkugle i rigningen, ankerlinen ned i vandet og en lille markeringsbøje.
- **Hvad det gør:** Ses kun, mens båden faktisk ligger for anker. Tegner kuglen mellem mast og stævn, et tov i en bue ud til en vippende bøje (strammere når ankeret glider) og et særligt messing-udseende for det magiske anker. Tegnede billeder fra Sprite Workshop kan erstatte kuglen og bøjen.
- **Arbejder sammen med:** `GameSession`, `AnchorState`, `BoatArea`, `BoatLighting` (bådens omrids), `SailRig` (mastens plads), `ArtworkResolver` (erstatningsbilleder), `SettingsManager` (mindre bevægelse).
- **Holder styr på:** Stævnens og mastens placering, et animationsur og eventuelle erstatningsbilleder. Intet gemmes.
- **Hvornår det kører:** På dækket.
- **Hvis du ændrer det:** Hvordan det ser ud på dækket, når båden ligger for anker.

### `src/boat/boat_area.gd`

**Formål:** Hjertet i hver dæks- og kahytsscene: den placerer Kaptajnen, sætter alt om bord op og gør "tryk på E ved noget" til ønsker, som spillet tager sig af.
- **Hvad det gør:** Ved indlæsning lægger den bådens grafik på og tilføjer lys, vejr, liv i vandet, ankertegn, ledsageren på dækket, fiskestang, ankerspil, komfur, trofætavle, kaffepladser og kahytspynt. Den styrer kameraet (bredere under sejlads, drejet efter kursen, følger dig i land), gangen ud på pontonen i havnen og den korte ankomst til kaj. Når du bruger en station, sender den et signal (en besked et objekt sender, som andre kan lytte efter), f.eks. åbn søkort, sov eller lav mad, som app'en tager sig af; den åbner aldrig selv menuer. Når du kæler for ledsageren, viser den en gang imellem et venligt ord (`CompanionRemarks`), eller et venligt blik, når hænderne er fulde. I022: dækkets vand får sin blødere farve fra WaterLook med en svag havbund i lavt vand (ShallowWater), og Starling 33's kahyt får sine vinduer (CabinWindows), kun vist med den tegnede stil. I024: den stiller Kaptajnens laptop (`LaptopProp`) på kahytsbordet ved arbejdspladsen, hvis tekst bliver "Brug laptoppen". I025: den tilføjer en node til en anden ledsager i kahytten og to på dækket (hver vises kun, mens den ledsager bor om bord), kajscenen med et dyr, der venter på pontonen (`DockEncounterScene`), parøjeblikkene, når to ledsagere bor om bord (`PairMoments`), og det falmede hav uden for kahytten (`CabinSeaBackdrop`); hver båds kahyt har nu sine vinduer. `cancel_exit` lader Kaptajnen blive på dækket efter spørgsmålet ved nedgangen. Med fulde hænder nævner det venlige blik den ledsager, man prøvede at kæle for. I026: på pontonen er der én station tilbage, gangbroen op til kajen ("To the quay"), hvor havnens forretninger nu har deres egne bygninger; de gamle butiksstationer bliver i scenerne, men bruges ikke. På hvert dæk monterer den de valgte instrumenter og kortplotteren ved roret (`CockpitInstruments`, placeret ud fra dækkets egne møbler, med en station ved plotteren) og skødespillet på cockpitsøllet (`WinchProp`, E trimmer sejlene); i hver kahyt placerer den logbogen, VHF-radioen, eltavlen, sømandskisten og det nyeste postkort (`CabinObject`). Bruges en af dem, sendes et ønske, som appen klarer, som for alle stationer.
- **Arbejder sammen med:** `GameSession`, `Player`, `Interactable`, `VesselVisual`, `SailRig`, `BoatLighting`, `ShoreAccess`, `HarbourDressing`, `WaterLife`, `LaptopProp`, `App` (som lytter efter dens ønsker). I025: også `DockEncounterScene`, `PairMoments`, `CabinSeaBackdrop`. I026: `CockpitInstruments`, `WinchProp`, `CabinObject`.
- **Holder styr på:** Kameraindstillinger, stationerne i land og ankomst-animationen; den skriver Kaptajnens position tilbage til spillets tilstand.
- **Hvornår det kører:** Når du er på dækket eller i kahytten.
- **Hvis du ændrer det:** Næsten alt om bord kan påvirkes: hvor Kaptajnen dukker op efter indlæsning, hvilke stationer der findes, og hvad de gør, kameraet og ankomsten i havn.

### `src/boat/boat_fixture.gd`

**Formål:** Den usynlige "faste form" for et møbel eller en beslagsdel, så Kaptajnen ikke kan gå igennem den.
- **Hvad det gør:** Bygger en kollisionsform ud fra et rektangel eller et selvvalgt omrids; kan markeres som noget, man kan gå på (luger, gulvplader). I spillet tegner den intet; i Godot-editoren viser den et gennemsigtigt omrids, så indretningen kan redigeres.
- **Arbejder sammen med:** `BoatArea`, `BoatLighting` (lamper og skygger følger møblernes navne), `HighlightResolver` (fremhæver møbler), placeringen i `CabinDecor`, `DeckCompanionSpots`.
- **Holder styr på:** Sin størrelse, sit omrids, og om den er fast.
- **Hvornår det kører:** Når et dæk eller en kahyt indlæses (og i editoren).
- **Hvis du ændrer det:** Hvor Kaptajnen kan gå på alle både; omdøbes møbler, kan lamper og fremhævninger også flytte sig.

### `src/boat/boat_lighting.gd`

**Formål:** Dag og nat om bord: lysets farve, kahytslamperne, lanterner og ankerlys samt bløde skygger.
- **Hvad det gør:** Følger spillets ur og bådens position og farver scenen (himmellys på dækket, dagslys gennem lugerne nedenunder). Tænder varme lamper ved bådens egne møbler, røde/grønne/hvide lanterner om natten under sejlads, et hvidt ankerlys for anker og kajlamper i havn. Tilføjer bløde skygger under møbler, Kaptajnen og ledsageren; stormvejr gør alt mørkere, og lyn giver et blidt glimt. Steady Hands / Golden Harbours: hvor overskyet vejret er, kommer nu fra én fælles funktion, som også bruges af kahyttens vinduer og havneøjeblikket.
- **Arbejder sammen med:** `BoatArea`, `Daylight`, `GameSession`, `Simulation` (vejret ved båden), `SailRig` (masten), `HarbourDressing`, `Interactable` (holder fremhævninger lyse om natten), `SettingsManager` (glimtets styrke).
- **Holder styr på:** Listen over lys, lysets nuværende farve og mørke, hvor overskyet det er, og glimtets styrke.
- **Hvornår det kører:** Når du er på dækket eller i kahytten.
- **Godt at vide:** Noden hedder altid "Lighting", på alle sprog, fordi båden finder den ved det navn.
- **Hvis du ændrer det:** Hele spillets stemning dag og nat; fejl kan gøre scener for mørke eller tænde lys på forkerte tidspunkter.

### `src/boat/cabin_sea_backdrop.gd`

**Formål:** Havet uden for skroget i kahytsvisningen (I025, A Little More Room Aboard): i stedet for et mørkt tomrum det samme hav som på dækket, men falmet.
- **Hvad det gør:** Lægger dækkets eget tegnede hav (dønningen, vinden, vejret, havnens læ og bådens fart gennem vandet) rundt om kahyttens skrog og dækker det med et slør i baggrundens natteblå farve: tyndest langs skroget, lukket til den rene baggrund et stykke ude, mørkere og gråere om natten. Fortøjet anes bådpladsens ponton meget svagt på kajsiden. Det ligger under al kahytstegningen, møblerne, ledsagerne, Kaptajnen og alle knapper, så det kun ses uden for skroget (og mellem en katamarans skrog); kahytslamperne lyser det ikke op, og solens glimt på det er dæmpet til en fjerdedel af dækkets. Det tjekker lyset én gang i sekundet og bygger kun sløret om, når lyset har ændret sig.
- **Arbejder sammen med:** `BoatArea` (tilføjer det med `CabinSeaBackdrop.attach`), `SeaSurface` (dækkets hav og dets shader), `VesselVisual` (bådens størrelse), `Daylight`, `BoatLighting` (hvor overskyet), `Simulation` (vejret), `GameSession` (tid, position, fortøjet eller ej), `data/vessels/cabin_windows.json` (hvor hver båds ponton ligger, under "sea").
- **Holder styr på:** Sine former for hav, slør og ponton, bådens halve størrelse og den sidste dagslysværdi; intet gemmes.
- **Hvornår det kører:** Når kahytten er på skærmen; aldrig på dækket.
- **Hvis du ændrer det:** Hvordan kahytten ser ud uden for skroget. Det koster tegnetid (målt med software-renderen ved 1600x900: cirka 68 til 94 ms pr. billede med det; ikke målt på et grafikkort eller på Windows), så bevar udskæringen af havet under kahytsgulvet, og byg kun sløret om, når lyset ændrer sig.

### `src/boat/cabin_windows.gd`

**Formål:** Glasset i kahytsvinduerne (I022), siden I025 i hver båds kahyt.
- **Hvad det gør:** Tegner vinduesåbningerne i den tegnede kahyts vægge som almindeligt røget glas i en anodiseret ramme: lysere ved yderkanten, hvor dagslyset kommer ind, dybere ind mod kahytten, en blød refleks hen over det, og om natten mørkt glas med et svagt varmt skær fra kahytslamperne. Hver båds kahyt har vinduer: koøjer i enkeltskrogenes og katamaranens skrogsider og katamaranens store salonvinduer, der ser fremad. Kahytstegningerne maler hver åbnings fordybning ud fra den samme datafil, så glasset altid sidder i sin ramme. Kaptajnens ændring af I025: vinduerne viser ikke længere en levende udsigt til havet, havnen, andre både eller vejret (den tegning er fjernet, ikke blot skjult). Det falmede hav omkring skroget er et separat script (`CabinSeaBackdrop`).
- **Arbejder sammen med:** `BoatArea` (tilføjer den), `Daylight` (dag eller nat), `data/vessels/cabin_windows.json` (hvor vinduerne sidder).
- **Holder styr på:** Vinduerne og hvor meget dagslys glasset viser.
- **Hvornår det kører:** Den tegner, når kahytten åbnes, og igen kun når dagslyset har ændret sig mærkbart (tjekkes hvert 20. sekund); at gå rundt tegner den aldrig om.
- **Hvis du ændrer det:** Vinduer til en anden båd kræver målte åbninger, der ligger inde i den kahyts vægtegning; testen tjekker hvert hjørne. Hold den billig: ingen udsigt til verden udenfor, ingen shader, intet arbejde i hvert billede.

### `src/boat/cabin_world_map.gd`

**Formål:** Det indrammede verdenskort på kahytsvæggen med nåle for besøgte havne og båden.
- **Hvad det gør:** Tegner et lille søkort over hele verden i træramme ud fra spillets landdata, med nåle for havnene i Logbogen og bådens position. Bruger man det, åbnes Drømmerens kort (Dreamer's Map). Det låner også sine verdensformer ud til rejsekortet.
- **Arbejder sammen med:** `GameSession` (besøgte havne, bådens position), `PortCatalog`, `MapView`/`WorldLand` (landdata), `HighlightResolver`, `VoyageMap`.
- **Holder styr på:** Verdens landformer, regnet ud én gang pr. spilkørsel og delt.
- **Hvornår det kører:** I kahytten.
- **Hvis du ændrer det:** Vægkortets udseende og rejsekortet, som genbruger dets tegning af land.

### `src/boat/cockpit_instruments.gd`

**Formål:** Bådens elektronik ved roret: kortplotteren ved rattet og en række instrumentdisplays på skottet (I026).
- **Hvad det gør:** Tegner den monterede instrumentpakke i bådens rigtige målestok: plotteren på rattets søjle (ved siden af katamaranens rat eller ved nedgangen på en båd med rorpind) og tre displays over nedgangen, med skærmene vippet mod rorgængeren og et blødt skær om natten (rødt eller dæmpet, som pakken gør det). Et klik på plotteren eller displayene åbner deres nærbilleder; plotteren har også sin egen E-station. Udseendet skifter, så snart en anden pakke monteres.
- **Arbejder sammen med:** `BoatArea` (placerer den ud fra dækkets egne møbler), `GameSession` (den monterede pakke), `InstrumentPackage`, `UiTheme` (natten), `App` (åbner `PlotterView` og `InstrumentView`).
- **Holder styr på:** Hvor plotteren og displayene står, og hvilken pakke der tegnes.
- **Hvornår det kører:** På dækket; den tegner højst nogle gange i sekundet, aldrig hvert billede.
- **Hvis du ændrer det:** Hvordan cockpittets elektronik ser ud på alle både; det er grafik plus to klik og ændrer ikke sejladsen.

### `src/boat/fender_stowage.gd`

**Formål:** Skjuler fendrene (de hvide puder på bådens side) under sejlads og viser dem i havn.
- **Hvad det gør:** Finder de hvide fenderformer, der er malet ind i dæksbilledet, laver en kopi af billedet uden dem og skifter mellem de to. De oprindelige grafikfiler ændres aldrig.
- **Arbejder sammen med:** `BoatArea` (spørger den, når sejladsen begynder eller slutter), `VesselVisual`/`VisualSlot` (dæksbillederne).
- **Holder styr på:** Hvilke fendere der er fundet i hvert billede, resten af kørslen.
- **Hvornår det kører:** På dækket, når grafikken lægges på, og når båden forlader eller når havnen.
- **Hvis du ændrer det:** Om fendrene vises rigtigt; en fejl kunne slette andre hvide dele af dæksgrafikken.

### `src/boat/laptop_prop.gd`

**Formål:** Kaptajnens laptop, tegnet åben på kahytsbordet (I024).
- **Hvad det gør:** Tegner en lille grafitgrå laptop med tastatur og en blødt oplyst skærm vendt mod arbejdspladsen, set ovenfra som resten af kahytten, i Real Horizon-farverne (skærmen lidt lysere om natten). `place()` stiller en på det bord, der er nærmest arbejdspladsen, i hver kahyt.
- **Arbejder sammen med:** `BoatArea` (stiller den frem og giver arbejdspladsen teksten "Brug laptoppen"), `BoatFixture` (bordene), `App.open_laptop()` (det, stationen åbner).
- **Holder styr på:** Kun hvor kraftigt skærmen lyser.
- **Hvornår det kører:** Når kahytten er på skærmen.
- **Hvis du ændrer det:** Kun hvordan laptoppen ser ud, og hvor den står; selve arbejdspladsen bliver, hvor den var.

### `src/boat/provision_display.gd`

**Formål:** Viser proviant og vand om bord som rigtige ting i kahytten: brød, æbler, en syltetøjskrukke, ost og fire vanddunke.
- **Hvad det gør:** Hver ting svarer til 3,5 dage; fulde ting er udfyldte, brugte er svage omrids, lave forråd bliver ravgule og tomme røde. Har bådens grafikmappe tegnede billeder af forrådet, vises de i stedet. Stationen ved siden af åbner proviantmenuen.
- **Arbejder sammen med:** `GameSession` (dage med mad og vand), `Provisions` (niveauer og kapacitet), `VesselVisualProfile` (valgfrie billeder), `Loc` (etiketten).
- **Holder styr på:** Antal dage med mad og vand, som den sidst viste.
- **Hvornår det kører:** I kahytten (den vises også i Godot-editoren).
- **Hvis du ændrer det:** Hvordan Kaptajnen med et blik ser, om forrådet er ved at slippe op.

### `src/boat/sail_rig.gd`

**Formål:** Tegner sejlene set oppefra: storsejl, fok og, på læns-kurser, spileren.
- **Hvad det gør:** Læser sejlenes tilstand fra spillet og trimmer sejlene blødt efter vinden, i læ-siden. Sejlene "ånder" lidt, kun for udseendets skyld. I havn og for anker er sejlene rullet sammen. Den kan bruge tegnede sejlbilleder og den sejldugsfarve, der er valgt hos sejlmageren, og bliver gennemsigtig, når Kaptajnen går ind under den.
- **Arbejder sammen med:** `GameSession` (fremdriftstilstand, under sejlads, for anker), `VesselVisualProfile` (sejlbilleder), `HarbourTrades` (sejldugsfarver), `BoatArea`.
- **Holder styr på:** Fastgørelsespunkter fra bådens indretning, sejlenes nuværende vinkler, og hvor meget hvert sejl er sat.
- **Hvornår det kører:** På dækket.
- **Hvis du ændrer det:** Hvordan sejlads ser ud; den ændrer aldrig, hvor hurtigt båden sejler.

### `src/boat/visuals/damage_overlay.gd`

**Formål:** Tegner slid og skader oven på bådens grafik, efterhånden som dens tilstand bliver dårligere.
- **Hvad det gør:** Intet når båden er i god stand; skrammer og rust når den er slidt; revner og skadede planker når den er skadet; mange revner og vand på kahytsgulvet når det er kritisk. Mærkerne placeres på samme måde hver gang for hver båd; tegnede skadesbilleder kan erstatte dem.
- **Arbejder sammen med:** `VesselVisual` (opretter den), `VesselCondition` (tilstandstrinene), `VesselVisualProfile` (valgfrie skadesbilleder), `ProceduralShape`.
- **Holder styr på:** Nuværende tilstand og trin samt listen over mærkernes pladser.
- **Hvornår det kører:** På dækket og i kahytten, når bådens tilstand vises.
- **Hvis du ændrer det:** Hvordan en slidt eller skadet båd ser ud.

### `src/boat/visuals/procedural_shape.gd`

**Formål:** En enkel pladsholder-tegning: en udfyldt form med omrids og eventuelt en etiket.
- **Hvad det gør:** Tegner et rektangel eller et selvvalgt omrids og en etiket i midten. Den er kun et billede; den tilhørende faste form er en `BoatFixture`.
- **Arbejder sammen med:** `VisualSlot` (har dem som pladsholder-grafik), `DamageOverlay` (bruger deres omrids).
- **Holder styr på:** Sin størrelse, sit omrids, sine farver og etikettens tekst.
- **Hvornår det kører:** Når pladsholder-grafik vises (og i Godot-editoren).
- **Hvis du ændrer det:** Udseendet af alle bådens dele, der ikke har et tegnet billede.

### `src/boat/visuals/solar_panels.gd`

**Formål:** Pyntesolpaneler agter på hver båd, kun for udseendets skyld.
- **Hvad det gør:** Tegner mørkeblå paneler med celler, ramme, skygge og stivere (og en bue ved to eller flere paneler), eller et tegnet billede fra Sprite Workshop. De giver ingen strøm, gemmes ikke og ligger uden for det dæk, man kan gå på.
- **Arbejder sammen med:** `VesselVisual` (opretter den ud fra bådens liste over paneler), `ArtworkResolver` (erstatningsbillede).
- **Holder styr på:** Panelernes rektangler.
- **Hvornår det kører:** På dækket.
- **Hvis du ændrer det:** Kun panelernes udseende.

### `src/boat/visuals/vessel_visual.gd`

**Formål:** Roden for en båds dæks- eller kahytsgrafik, som for hvert lag afgør, om der vises et tegnet billede eller pladsholder-tegningen.
- **Hvad det gør:** Lægger bådens grafikprofil på lag for lag, tillader erstatninger fra Sprite Workshop og tilføjer solpaneler og laget med slid og skader. Den har ingen kollision, så ny grafik ændrer aldrig spillet.
- **Arbejder sammen med:** `VisualSlot`, `VesselVisualProfile`, `ArtworkResolver`, `SolarPanels`, `DamageOverlay`, `BoatArea`, `BoatyardMenu` (forhåndsvisning af båden), `FenderStowage`.
- **Holder styr på:** Grafiklærredets størrelse, listen over solpaneler og den nuværende profil.
- **Hvornår det kører:** På dækket og i kahytten samt i bådeværftets forhåndsvisning.
- **Hvis du ændrer det:** Hvordan grafikken vælges og lægges i lag på alle både.

### `src/boat/visuals/vessel_visual_profile.gd`

**Formål:** En indstillingsfil, der siger, hvilken grafik hver del af en båd bruger.
- **Hvad det gør:** For hvert grafiklag ser den først efter et billede valgt i editoren, så efter en billedfil med det rigtige navn i bådens grafikmappe, og ellers beholdes pladsholder-tegningen, så en manglende fil aldrig får båden til at forsvinde. Det samme gælder skadesbilleder.
- **Arbejder sammen med:** `VesselVisual`, `VesselDefinition`, `SailRig`, `DamageOverlay`, `ProvisionDisplay`, `BoatArea`.
- **Holder styr på:** Grafikmappen, kontakten "kun pladsholdere" og de tildelte billeder (gemt i `data/vessels/*_visuals*.tres`).
- **Hvornår det kører:** Når bådgrafik vises.
- **Hvis du ændrer det:** Hvilke billeder alle både viser; omdøbes lagfilerne, holder "læg et billede i mappen"-metoden op med at virke.

### `src/boat/visuals/visual_slot.gd`

**Formål:** Ét navngivet lag af en båds grafik (skrog, dæk, ruf …), som viser enten et tegnet billede eller pladsholder-formerne.
- **Hvad det gør:** Får den et billede, skjuler den pladsholder-formerne og strækker billedet over hele grafiklærredet (med en advarsel, hvis billedets form ikke passer); ellers vises pladsholderen.
- **Arbejder sammen med:** `VesselVisual`, `VesselVisualProfile`, `FenderStowage`.
- **Holder styr på:** Lagets navn og det billede, den viser.
- **Hvornår det kører:** Når bådgrafik vises.
- **Hvis du ændrer det:** Hvordan tegnede billeder passer på plads på alle både.

### `src/boat/shallow_water.gd`

**Formål:** Et strejf af havbunden gennem lavt vand (I022).
- **Hvad det gør:** Tegner nogle få store, meget svage sandede pletter i vandet omkring en fortøjet eller ankret båd, over vandets farve og under bølgetoppene og skroget. Hver havn får altid de samme pletter. Skjult til søs, og når vandets gennemsigtighed er 0.
- **Arbejder sammen med:** `BoatArea` (tilføjer den ved vandet), `WaterLook`, `GameSession` (afgang, ankomst, ankring).
- **Holder styr på:** Mønstrets frø.
- **Hvornår det kører:** Den tegner én gang og igen kun, når båden forlader eller kommer tilbage til lavt vand.
- **Hvis du ændrer det:** Hold det svagt.

### `src/boat/water_look.gd`

**Formål:** Blødere vand, der ser mere gennemsigtigt ud (I022).
- **Hvad det gør:** Giver farven på vandet omkring båden: det gamle dybe blågrønne med en smule af en sandet havbundsfarve skinnende igennem, lidt mere i havn eller for anker, hvor vandet er lavt. Det er en almindelig farveblanding, uden shader og uden gennemsigtighed. Dagens og nattens lys, bølgetoppe og krusninger ligger stadig ovenpå. Styrken er én indstilling, adskilt fra vinduesglassets farve, og 0 giver præcis det gamle vand.
- **Arbejder sammen med:** `BoatArea` (dækkets vand), `ShallowWater`, `CabinWindows`.
- **Holder styr på:** Kun styrken.
- **Hvornår det kører:** Når en dækscene åbner, og når båden sejler, ankommer eller ankrer.
- **Hvis du ændrer det:** Hold vandet tydeligt vand; testen tjekker, at det forbliver mørkt nok, og at 0 er den gamle farve.

### `src/boat/weather_visuals.gd`

**Formål:** Viser vejret på dækket: lette vindstriber, der driver med vinden, og regn, når det regner.
- **Hvad det gør:** To gange i sekundet læser den vind og regn ved båden. Striberne bevæger sig derhen, hvor vinden blæser, hurtigere og flere i mere vind; regnen falder skråt med vinden efter samme regel som regnlyden.
- **Arbejder sammen med:** `BoatArea`, `GameSession`, `Simulation` (vejr og kurs), `WeatherAudio` (regnmængde).
- **Holder styr på:** Vindens nuværende retning og styrke, regnmængden og striberne og dråberne på skærmen (højst 40 og 260).
- **Hvornår det kører:** På dækket.
- **Hvis du ændrer det:** Hvordan vind og regn føles på dækket; kun udseendet.

### `src/boat/winch_prop.gd`

**Formål:** Genuaens skødespil på cockpitsøllet, hvor en sejler trimmer sejlene (I026).
- **Hvad det gør:** Tegner et selvskødende spil med håndtag i rigtig størrelse ved den forreste ende af styrbords cockpitbænk (på Clam 40 ved siden af rattet). E på det åbner den samme sejltrim som T og handlingshjulet; kun under sejlads, ellers siger spillet hvorfor.
- **Arbejder sammen med:** `BoatArea` (placerer det og sender ønsket videre), `Interactable`, `App` (åbner `SailTrimPanel`).
- **Holder styr på:** Kun sin station.
- **Hvornår det kører:** På dækket.
- **Hvis du ændrer det:** Hvor spillet står, og hvordan det ser ud; det har ingen kollision og står aldrig i vejen for Kaptajnen eller en ledsager.

### `src/interaction/highlight_provider.gd`

**Formål:** En lille usynlig hjælper, der fortæller fremhævningssystemet omridset af en tegnet ting (som komfuret eller ankerspillet).
- **Hvad det gør:** Gemmer et omrids og giver det videre, så stationens glød følger den rigtige ting, når Kaptajnen står tæt på. Den tegner intet selv.
- **Arbejder sammen med:** `HighlightResolver`, `BoatArea` (tilføjer én til hver del af udstyret om bord), `HarbourDressing`.
- **Holder styr på:** Omridsets punkter.
- **Hvornår det kører:** Om bord og på pontonen, når fremhævninger regnes ud.
- **Hvis du ændrer det:** Hvilke ting der gløder, når de er i fokus.

### `src/interaction/highlight_resolver.gd`

**Formål:** Afgør, hvad der skal gløde, når Kaptajnen kan bruge noget: den rigtige ting, ikke en usynlig cirkel.
- **Hvad det gør:** Leder først efter en ting, der siger, at den hører til handlingen, så efter det nærmeste passende møbel (kortbord, køje, kabys …) og ellers et lille, blødt omrids af stationens område. Giver også praktiske omrids som afrundede rektangler og cirkler.
- **Arbejder sammen med:** `Interactable`, `BoatFixture`, `HighlightProvider`, `BoatArea`, `CabinWorldMap` og udstyr om bord som `GalleyStove`.
- **Holder styr på:** Intet selv; kun faste lister over møbelnavne.
- **Hvornår det kører:** Når et dæk eller en kahyt sættes op, og når stationer ændres.
- **Hvis du ændrer det:** Hvilken ting der gløder for hver handling; hvor tæt man skal være for at bruge ting, påvirkes ikke.

### `src/interaction/interactable.gd`

**Formål:** Alt, hvad Kaptajnen kan bruge ved at stå tæt på og trykke E (en "station").
- **Hvad det gør:** Dens form bestemmer, hvor tæt man skal være. Når den bruges, sender den et signal (en besked et objekt sender, som andre kan lytte efter); scenen, der ejer den, afgør, hvad der sker, eller den viser blot en kort tekst. Mens den er i fokus, gløder den blødt rundt om sin ting og forbliver lys om natten.
- **Arbejder sammen med:** `InteractionSensor` (vælger, hvilken der er i fokus), `BoatArea` (sender handlingen videre), `HighlightResolver`, `BoatLighting`.
- **Holder styr på:** Sit handlings-id, sin tekst, om den er slået til, sin prioritet og sit fremhævningsomrids.
- **Hvornår det kører:** Når du er om bord eller i land tæt på den.
- **Hvis du ændrer det:** Alt, der kan bruges i spillet; meget bred påvirkning.

### `src/interaction/interaction_sensor.gd`

**Formål:** Kaptajnens "rækkevidde": den finder ting i nærheden, der kan bruges, og holder præcis én i fokus.
- **Hvad det gør:** Vælger den nærmeste station, men lader stationer vinde over ledsageren, medmindre du vender dig mod dyret. Tryk på E bruger altid den samme ting, som teksten viser; lige afstande afgøres forudsigeligt efter navn.
- **Arbejder sammen med:** `Interactable`, `Player` (sidder inde i spilleren og spørger, hvilken vej den vender).
- **Holder styr på:** Hvilken station der er i fokus lige nu.
- **Hvornår det kører:** Ved hvert fysiktrin, mens du er om bord.
- **Hvis du ændrer det:** Hvilken station E bruger, når flere er tæt på, også når man klapper katten eller hunden.

### `src/player/player.gd`

**Formål:** Kaptajnen om bord: går med tasterne, støder ind i møbler og bruger ting med E.
- **Hvad det gør:** Bevæger sig med en fast fart (tasterne følger skærmen, også når dæksvisningen er drejet), husker hvilken vej den vender, svinger armene, når den går, og tegner sig selv som en lille sømand, der bærer kaptajnshuen eller kaffen, når den har dem. Den ignorerer tasterne, mens menuer er åbne. I026: på kajen går den også på promenaden, og på caféen holder den caféens krus (tegnet som bådens eget, men intet i spillet ændres).
- **Arbejder sammen med:** `InteractionSensor`, `SailorDrawing`, `PlayerHat`, `GameSession` (kaffe), `BoatArea`. I026: `HarbourFront` (kajen og caféstolen).
- **Holder styr på:** Retningen den vender, gang-animationen, om tasterne er slået til, og visningens drejning.
- **Hvornår det kører:** Når du er på dækket eller i kahytten.
- **Hvis du ændrer det:** Hvordan Kaptajnen bevæger sig og føles at styre; ændres kollisionsstørrelsen, ændres også, hvor man kan gå.

### `src/player/sailor_drawing.gd`

**Formål:** Tegner Kaptajnen oppefra som en lille sømand i stribet trøje.
- **Hvad det gør:** Tegner skygge, svingende arme med hænder, den stribede krop, hår og et antydet ansigt samt kaffekruset i hånden, når kaffen bæres. De samme oplysninger giver altid den samme tegning.
- **Arbejder sammen med:** `Player` (bruger den til at tegne), `CoffeeMug` (krus-tegningen), `PlayerHat` (tegner kaptajnshuen ovenpå).
- **Holder styr på:** Intet selv; kun farver og mål.
- **Hvornår det kører:** Når Kaptajnen tegnes.
- **Hvis du ændrer det:** Kaptajnens udseende; kaptajnshuens placering afhænger af, at hovedets midte bliver, hvor det er.

### `src/vessels/vessel_catalog.gd`

**Formål:** Listen over alle de både, Kaptajnen kan eje, i bådeværftets rækkefølge.
- **Hvad det gør:** Indlæser bådlisten én gang, finder en båd ud fra dens id og udpeger startbåden (Arctic Wanderer 26), som også er den sikre reserve ved ukendte id'er.
- **Arbejder sammen med:** `VesselDefinition`, `GameSession`, `SaveManager`, `SessionState`, `BoatyardMenu`, `CaptainsLogMenu`, `App`.
- **Holder styr på:** Listen over både (fra `data/vessels/vessel_catalog.tres`).
- **Hvornår det kører:** Når spillet har brug for oplysninger om både, fra indlæsningen og frem.
- **Hvis du ændrer det:** Hvilke både der findes, og hvilken et nyt spil starter med; ændres startbådens id, påvirker det gamle gemte spil.

### `src/vessels/vessel_definition.gd`

**Formål:** Beskriver én båd: dens id, navn, beskrivelse, sejlegenskaber, dæks- og kahytsscener og grafik.
- **Hvad det gør:** Rene data, én fil pr. båd. Den vælger den illustrerede grafik, når grafik-indstillingen beder om det, giver den rigtige scene for dæk eller kahyt og tjekker, at båden er komplet. Siden I022 har hver båd en pris i euro.
- **Arbejder sammen med:** `VesselCatalog`, `GameSession`, `VesselVisualProfile`, `BoatArea`, `BoatyardMenu`, `Provisions` (forråd til Lang passage), `SettingsManager`.
- **Holder styr på:** Bådens fakta (gemt i `data/vessels/*.tres`).
- **Hvornår det kører:** Når spillet spørger om den aktive båd.
- **Hvis du ændrer det:** Opsætningen af alle både; gemte spil indeholder kun id'et, så en båds id må aldrig ændres.

### `src/water/water_life.gd`

**Formål:** Får vandet omkring båden til at leve med små bevægelser, som accenter oven på det illustrerede hav (`SeaSurface`).
- **Hvad det gør:** I havn: ringe i vandet, små bølger, glimt, vand der skvulper mod skrog og ponton, og et par drivende ting, der passer til havnen (marina, kyst eller by). Til søs: bølgetoppe styret af vinden (hvide toppe fra 20 kn), der strømmer forbi med bådens fart, og drivende tang, drivtømmer og fjer. Vises kun med den illustrerede grafikstil.
- **Arbejder sammen med:** `BoatArea`, `GameSession`, `Simulation` (vinden ved båden), `HarbourArt`, `PortCatalog`, `SettingsManager`.
- **Holder styr på:** Et fast antal bølger, drivende ting og ringe, som genbruges hele tiden, og den vind, den sidst læste.
- **Hvornår det kører:** På dækket, hvert billede (frame), mens den er synlig.
- **Hvis du ændrer det:** Følelsen af havet og havnene og måske billedhastigheden.

### `src/world/day_night_watch.gd`

**Formål:** Klarer daggry og skumring blidt: når tusmørket begynder under almindeligt spil, vises et datokort, og tusmørket får lov at gå bag det.
- **Hvad det gør:** Holder øje med solen ved båden; når den opdager, at daggry eller skumring begynder, beder den app'en vise kortet, mens tiden går helt normalt (proviant, vejr, hændelser), indtil det er fuld dag eller nat. Søvn, indlæsning og andre spring i tiden tæller aldrig med, og lange polare tusmørker får intet kort.
- **Arbejder sammen med:** `App` (viser kortet), `Daylight`, `GameSession`, `Simulation`, `TimePassage`.
- **Holder styr på:** Det tidspunkt og den solhøjde, den sidst så på.
- **Hvornår det kører:** Altid under spillet (sat på pause, når menuer sætter spillet på pause).
- **Hvis du ændrer det:** Hvor tit spillet afbrydes af kort ved daggry og skumring.

### `src/world/daylight.gd`

**Formål:** Regner ud, hvor solen står for båden, ud fra spillets ur og position.
- **Hvad det gør:** En enkel solformel: lokal soltid ud fra længdegraden, årstiden ud fra datoen og solens højde. Ud fra det giver den nat, daggry, dag eller skumring, hvor meget dagslys der er, og lysets farve udenfor og i kahytten (grårere i stormvejr).
- **Arbejder sammen med:** `BoatLighting`, `DayNightWatch`, `UiTheme`, `MusicDirector`.
- **Holder styr på:** Intet selv; kun faste farver og regler.
- **Hvornår det kører:** Når lyset, brugerfladen eller musikken tjekker tiden på dagen.
- **Hvis du ændrer det:** Hvornår det bliver mørkt og lyst overalt i spillet, og farverne i alle scener.

## Livet om bord og i land: ledsager, fiskeri, kabys, hue, havnens handlende, sejlads, pleje, lyd, udviklerværktøjer

### `src/anchor/anchor_site.gd`

**Formål:** Regelbogen for, hvor båden kan ankre, og hvor godt ankeret holder.
- **Hvad det gør:** For et sted på kortet svarer det på tre adskilte spørgsmål: kan båden komme sikkert derhen, har vandet den rigtige dybde til det almindelige anker (eller kun til Magic Anchor), og hvor godt ligger stedet i læ for dagens vind. Det regner også ud, om ankeret holder godt, rimeligt, dårligt eller slæber, og skriver de venlige beskrivelser, der vises på søkortet.
- **Arbejder sammen med:** `CoastalGeography` (land, afstand til kysten, åbent vand op mod vinden), `DepthService` (anslået dybde), `WindField`/`WeatherSample` (vinden), `AnchorState` (niveauer for ankerets hold), `Loc` (oversættelser).
- **Holder styr på:** Intet selv; kun faste regler (dybdegrænser, vindgrænser, tal for ankerets hold).
- **Hvornår det kører:** Hver gang spillet vurderer en ankerplads: på søkortet, i ankermenuen og mens båden ligger for anker.
- **Hvis du ændrer det:** Hvilke steder der regnes for gode, rimelige eller dårlige ankerpladser, hvornår ankeret slæber i hård vind, og de tekster spilleren læser om ankring.

### `src/anchor/magic_anchor_deployment.gd`

**Formål:** Det lille timingspil, man spiller, når Magic Anchor sættes.
- **Hvad det gør:** Sætter en rund skive op (den samme som fiskestangens hjul), som kræver 1–3 gode stop afhængigt af vinden, med et lidt smallere mål i hårdere vind. Tre forbiere afslutter forsøget; perfekte stop får ankeret til at bide lidt fastere.
- **Arbejder sammen med:** `TimingCheck` (selve skiven), ankermenuen og `GameSession.drop_magic_anchor`, som foretager selve ankringen.
- **Holder styr på:** Den aktuelle skive og hvor mange forsøg der er brugt.
- **Hvornår det kører:** Kun mens kaptajnen sætter Magic Anchor.
- **Hvis du ændrer det:** Hvor svært eller let det er at sætte Magic Anchor, og hvor godt det holder bagefter.

### `src/art/artwork_resolver.gd`

**Formål:** Lader en tegner bytte spillets tegnede grafik ud med egne PNG-billeder ("Sprite Workshop").
- **Hvad det gør:** Læser listerne `manifest.csv` i `art_replacements/`, og når der findes en matchende PNG med den rigtige form og størrelse, bruges den i stedet for den indbyggede grafik. Et manglende billede springes stille over; et forkert billede meldes som en advarsel, og den oprindelige grafik bliver brugt.
- **Arbejder sammen med:** Tegnekode som `HatArt`, `FishArt`, `CompanionVisualSet` og bådens grafik, som beder om et billede ved navn.
- **Holder styr på:** Listen over manifest-linjer, en hukommelse (cache) af indlæste billeder og de advarsler, det har givet.
- **Hvornår det kører:** Første gang et stykke grafik efterspørges; derefter fra hukommelsen. Nye PNG'er vises først, når spillet genstartes.
- **Hvis du ændrer det:** Om håndtegnet erstatningsgrafik dukker op i spillet, og hvilke billeder der godtages eller afvises.

### `src/audio/audio_manager.gd`

**Formål:** Spillets lydafspiller: den spiller den musik, baggrundslyd og de lydeffekter, den får udleveret.
- **Hvad det gør:** Har én afspiller til musik, én til baggrundslyd ("ambience"), otte genbrugelige afspillere til korte lyde og navngivne lyde i løkke (som vind eller motoren), der toner ind og ud uden at starte forfra. Den bestemmer aldrig selv, hvad der skal spilles; andre dele af spillet beder den om det.
- **Arbejder sammen med:** Scener og menuer som `App`, `WeatherAudio`, fiskeri-, anker- og madlavningsmenuerne og `ShipCompanion`; `MusicDirector` bruger navnet på dens musikkanal.
- **Holder styr på:** Sine lydafspillere, de løkkelyde der spiller lige nu, og deres mållydstyrker.
- **Hvornår det kører:** Altid (en autoload: et script Godot starter automatisk, og som altid findes), også mens spillet er sat på pause.
- **Hvis du ændrer det:** Alle lyde i spillet kan blive påvirket: lydstyrke, overtoninger og lyde der afbryder hinanden.

### `src/audio/music_director.gd`

**Formål:** Vælger, hvilket af de tre musikstykker der skal spille, og glider blødt mellem dem.
- **Hvad det gør:** Spiller "Lanterns Across the Water" om natten, "The Wind Knows the Way" under sejlads på dækket om dagen og "Home Upon the Waves" ellers (havn, kahyt, for anker, titelskærm). Det venter et par sekunder før et skift, overtoner langsomt, genoptager et stykke fra starten af en musikalsk frase og skifter ikke mellem dag- og natmusik, mens passagetiden kører hurtigt.
- **Arbejder sammen med:** `GameSession` (bådens position, tiden, om den sejler eller ligger for anker), `Daylight` (solens højde), `Simulation` (hurtig passagetid), `AudioManager` (musikkanalen).
- **Holder styr på:** Én afspiller pr. stykke, hvilket stykke der spiller, frasernes starttider og sine ventetimere.
- **Hvornår det kører:** Altid (en autoload), og det tjekker to gange i sekundet.
- **Hvis du ændrer det:** Hvornår og hvordan musikken skifter; for ivrige indstillinger får musikken til at hoppe frem og tilbage.

### `src/audio/weather_audio.gd`

**Formål:** Gør vejret hørbart om bord: vind, vand langs skroget, regn, storm og torden.
- **Hvad det gør:** Én gang i sekundet sætter det lydstyrken på løkkelydene for vind, vand, regn og storm ud fra vejret ved båden. Nær et tordenvejr blinker det med bådens lys og spiller torden efter en forsinkelse, der vokser med afstanden. Under dæk dæmpes alt udefra. Siden I022 spiller vinden (brise og storm) på sin egen Wind-kanal, så den har sin egen lydstyrke under Indstillinger; den dæmpes stadig under dæk.
- **Arbejder sammen med:** `AudioManager` (spiller løkkerne), `GameSession` (bådens fart og position), `WeatherSample`/`WeatherEvent` (vejret), `BoatLighting` (lynglimt), `SettingsManager` (indstillingen for færre blink). Oprettes og fodres af `App`.
- **Holder styr på:** Hvor kaptajnen er (på dækket eller indenfor), de aktuelle lydniveauer og timere for næste lyn og torden.
- **Hvornår det kører:** Mens et spil er i gang; `App` giver det vejret hvert virkeligt sekund.
- **Hvis du ændrer det:** Hvor stormfuldt eller roligt spillet lyder, lynglimtene, og regnreglen som `GameSession` også bruger til at afgøre, om katten eller hunden må være på dækket.

### `src/boat_care/boat_care.gd`

**Formål:** Alle regler for, hvordan båden slides, og hvad bådeværftet tager for at udbedre det.
- **Hvad det gør:** Følger fire plejeområder (skrog og bund, rigning og sejl, motor, udstyr), gør slid til et niveau (god, kosmetisk, service anbefales, kræver opmærksomhed) og regner det lille fartab ud, som en slidt båd får (højst nogle få procent). Det prissætter også reparationer, service og optagning (afhængigt af bådens længde), læser listen over udstyrsopgraderinger og skriver plejeteksterne til menuerne og Logbogen.
- **Arbejder sammen med:** `BoatCareState` (bådens gemte plejedata), `VesselCondition` (skrogets tilstand), `GameSession` (formatering af penge), `PortCatalog` (havnenavne), menuerne for bådeværft, skibshandel, sejlmager og bådpleje samt `PassageReadiness`.
- **Holder styr på:** Intet selv, bortset fra en kopi af opgraderingslisten fra `data/boat/equipment.json`, der indlæses én gang.
- **Hvornår det kører:** Når der lægges slid til under sejlads, når farten regnes ud, eller når en plejemenu eller et bådeværft åbnes.
- **Hvis du ændrer det:** Hvor hurtigt der gror begroning på bunden og rigningen slides, hvor meget det bremser båden, og bådeværftets priser og tider.

### `src/boat_care/passage_readiness.gd`

**Formål:** En venlig tjekliste før en sejlads: er båden klar til at tage af sted?
- **Hvad det gør:** Ser på skroget og plejeområderne, proviant og vand i forhold til den forventede sejltid, vejrudsigten langs ruten (højst 24 timer frem), sejladsens længde og bådens størrelse. Hvert fund er OK, værd at bemærke eller værd at tænke over en ekstra gang. Det giver kun råd; det forhindrer dig aldrig i at sejle.
- **Arbejder sammen med:** `GameSession` (båd, tilstand, proviant), `Simulation` (rutetid og vejrfarer), `BoatCare`, `VesselCondition`, `Provisions`, `GeoMath`; vises af `App`, `WorldMap` og `VoyageDaydream`.
- **Holder styr på:** Intet; det regner et nyt svar ud hver gang.
- **Hvornår det kører:** Når en kurs planlægges, eller en sejlads skal til at begynde.
- **Hvis du ændrer det:** Hvilke råd kaptajnen ser før afgang (for eksempel advarsler om proviant eller hårdt vejr).

### `src/companion/companion_pose_art.gd`

**Formål:** Beskriver én stilling eller ét animeret klip af en ledsager (hviler, sover, går, flyver og mere).
- **Hvad det gør:** Indeholder stillingens navn, den PNG-fil der skal vises, og små justeringer: forskydning, størrelse og spejlvending. Siden I024 kan en stilling være et klip: flere billeder efter det første, billeder pr. sekund, og om det gentages eller spilles én gang og bliver stående på sit sidste billede. Det er en byggeklods i et `CompanionVisualSet`.
- **Arbejder sammen med:** `CompanionVisualSet` (som oplister stillingerne) og gennem den `ShipCompanion`.
- **Holder styr på:** Kun disse indstillinger, der redigeres i Godots inspector eller i `.tres`-filen.
- **Hvornår det kører:** Når ledsagerens billeder indlæses.
- **Hvis du ændrer det:** Hvilket billede der vises for en stilling, og hvordan det placeres; en manglende fil får blot den stilling til at falde tilbage til en anden, og et erstatningsbillede fra Sprite Workshop erstatter hele klippet med sit ene billede.

### `src/companion/companion_remarks.gd`

**Formål:** Alt, hvad skibets ledsager "siger", eller som siges om den, samlet ét sted.
- **Hvad det gør:** Har korte bemærkninger til at kæle for katten, hunden og papegøjen ("Sikke en dejlig lille spinden."), vælger den næste, så den samme linje aldrig kommer to gange i træk, og oversætter den til det aktuelle sprog. Med det navn og køn, spilleren har valgt, bruger den linjer med navnet ("Hvem er en dygtig pige, Freja?"), sat ind præcis som det er skrevet; uden navn siger den "katten". Siden I024 giver den også teksten for at kæle, linjerne for at gå i land og blive kaldt om bord (også hvorfor båden endnu ikke kan kaste los), en linje en gang imellem, når den findes ved køjen om morgenen, og Kaptajnens snak på lange passager i tre trin (de første dage, efter to døgn, efter fem) med dyrets svar (en linje og det klip, der skal spilles). Giver også linjen om, at hænderne er fulde. I025: linjer til to ledsagere: ét afslag, der nævner begge, når begge er i land, "Kald … om bord" for begge, én morgenlinje om dem begge (aldrig to beskeder, der konkurrerer) og parlinjer på lange passager (dem med navne kun, når begge har et). Den har også linjerne til at vinde et dyrs tillid på kajen (teksten over dyret, et goddag, en godbid, lidt leg eller bare at vente stille i nærheden, og det klip, dyret svarer med), spørgsmålet ved nedgangen, når det har fulgt Kaptajnen hjem, og laptoppens historiklinje om, hvor og hvornår en ledsager kom om bord (kun ud fra dens egne oplysninger).
- **Arbejder sammen med:** `CompanionState` (hvem ledsageren er), `Loc` (engelsk eller dansk), `ShipCompanion` (som beder om en bemærkning, når der bliver kælet), `BoatArea` (som viser den), `GameSession` (land, opvågning, bedrifter) og `App` (spørgsmålet ved afgang, snakken på passager).
- **Holder styr på:** Intet; linjerne står fast i scriptet, og de, der kalder den, bestemmer hvornår.
- **Hvornår det kører:** Når du kæler for ledsageren (højst én bemærkning hvert 15. sekund) eller prøver med fulde hænder, går i land eller kaster los, vågner, eller sejler en lang passage.
- **Hvis du ændrer det:** Hvad Kaptajnen siger til og om ledsageren; nye linjer skal have en dansk oversættelse i `locale/da.po`.

### `src/companion/companion_state.gd`

**Formål:** De gemte oplysninger om skibets ledsager: hvilket dyr, dens navn, hvor den hviler, og om den er i kahytten, på dækket eller i land.
- **Hvad det gør:** Hver 2.–5. spiltime flytter ledsageren til et andet hvilested i kahytten (sofaen, kortbordet, køjen for katten; gulvet, nedgangen, siddepladsen for hunden). Valget regnes ud fra spillets ur, ikke tilfældighed, så det er det samme ved enhver hastighed og efter indlæsning. Den kan også være på dækket på et af tre steder. Siden I024 er der tre slags (gemt som `cat` for ragdoll-katten, `dog` for mopsen og `parrot` for den grønkindede parakit, som sidder ved kortbordet, på sofaen, ved køjen og på trappen), et valgfrit navn (én linje, højst 20 tegn, aldrig opfundet) og køn, og et område i land, mens båden er fortøjet. Når Kaptajnen vågner, findes den ved køjen (`wake_by_berth`). Et gemt spil indlæses aldrig med den i land: den er tilbage om bord. I025: op til to ledsagere bor om bord (`MAX_COMPANIONS`), hver med et fast nummer (`id`; aldrig et navn, så to kan hedde det samme; en ledsager fra før I025 er nummer 1) og hvordan den kom om bord (fra start eller adopteret fra en kaj). For en adopteret ledsager husker den hvornår, i hvilken havn og hvor den blev budt velkommen om bord, og intet opfindes for en ældre ledsager. Den husker også, om dens velkomst hjemme er blevet spillet. En anden ledsager har sin egen tidsplan for hvilesteder; den første beholder den, den altid har haft.
- **Arbejder sammen med:** `SessionState` (ejer og gemmer det), `GameSession` (den eneste der ændrer det), `ShipCompanion` (viser det), `GameSession.adopt_dock_animal` (adopterede ledsagere), `WelcomeHome`, `LaptopView` (dens historik), `CompanionRemarks`, `SaveManager` (giver gamle gemte spil en kat).
- **Holder styr på:** Slags, navn, køn, hvilested, tidspunktet for næste flytning, antal flytninger, område (kahyt/dæk/land) stedet på dækket eller pontonen og siden I025 dens nummer, oprindelse, adoptionsoplysninger, og om den er budt velkommen hjem.
- **Hvornår det kører:** Hele tiden i et spil, efterhånden som uret går.
- **Hvis du ændrer det:** Hvor ledsageren dukker op, og gemte spil (forkerte navne eller tal får et gemt spil til ikke at kunne indlæses).

### `src/companion/companion_visual_set.gd`

**Formål:** Billedsættet for én slags ledsager: stillinger, størrelse, placering og tider for, hvad den laver i ro.
- **Hvad det gør:** Indlæser hvert stillingsbillede, gør det mindre for at spare hukommelse og skærer en ensfarvet papirbaggrund væk, hvis tegningen ikke har gennemsigtighed. Det regner ud, hvor billedet tegnes på hvilestedet, og holder styr på, hvor længe dyret hviler, sover, strækker sig og kigger op. Et erstatningsbillede fra Sprite Workshop bruges, når det findes. Siden I024 kan hver stilling være et animeret klip (`get_frames`, med sin egen hastighed og gentagelse), der er mange flere klip (gå, vende, sidde, lægge sig, vågne, pleje pelsen, falde til ro og papegøjens hop, letten, flugt, landing, pjusken og fjerpleje), og sættet angiver gang- og flyvefarten, der passer til skridtet, så fødderne ikke glider.
- **Arbejder sammen med:** `CompanionPoseArt` (hver stilling), `ArtworkResolver` (erstatningsgrafik), `ShipCompanion` (tegner det); sættene ligger i `data/companions/cat_visuals.tres`, `dog_visuals.tres` og `parrot_visuals.tres`.
- **Holder styr på:** Sine indstillinger og en fælles hukommelse (cache) af færdigbehandlede billeder.
- **Hvornår det kører:** Når en ledsager vises i kahytten, på dækket, på kajen (I025) eller i et værktøj til forhåndsvisning.
- **Hvis du ændrer det:** Hvordan ledsagerne ser ud, bevæger sig og opfører sig i ro; uden et brugbart hvilebillede tegner spillet i stedet et enkelt indbygget dyr.

### `src/companion/deck_companion_spots.gd`

**Formål:** Finder sikre steder på dækket, hvor katten eller hunden kan ligge, og sikre ruter at gå imellem dem.
- **Hvad det gør:** Ud fra hver båds egen indretning vælger det tre hvilesteder (agter, midtskibs, forude) og vejen op ved nedgangen. Stederne ligger inden for søgelænderne, fri af beslag som masten og bænkene og et stykke fra rattet og de andre stationer. Gåturene følger linjer, der aldrig går ud over siden.
- **Arbejder sammen med:** `BoatArea` (som bygger det), `BoatFixture` og `Interactable` (beslag og stationer), `ShipCompanion` (som går ruterne).
- **Holder styr på:** Dækkets omrids, beslagene, de markører det har sat, og et gitter der bruges til at finde vej.
- **Hvornår det kører:** Én gang, når dækket bygges; derefter når ledsageren går.
- **Hvis du ændrer det:** Hvor ledsageren ligger på dækket, og om den kunne havne ude over vandet eller i vejen for kaptajnen.

### `src/companion/dock_box.gd`

**Formål:** Den lille papkasse på kajen, hvor det fundne dyr venter (I025).
- **Hvad det gør:** Tegner en åben kasse set ovenfra og lidt forfra, ligesom dyrene: flapperne foldet ud, en stribe brun tape og en blød skygge. Den tegnes i to dele, bagsiden og indersiden under dyret og forvæggen over det, så katten kan sidde i den; parakitten sidder på forkanten. Den er aldrig lukket og aldrig et bur. Den tegner også kassen, når den lille pige bærer den i armene.
- **Arbejder sammen med:** `DockEncounterScene` (placerer de to dele), `GirlDrawing` (den bårne kasse).
- **Holder styr på:** Kun hvilken del den tegner.
- **Hvornår det kører:** Mens et dyr venter på kajen.
- **Hvis du ændrer det:** Kun kassens udseende; hold størrelsen afpasset efter dyrene.

### `src/companion/dock_encounter_scene.gd`

**Formål:** Viser dyret på kajen på dækket af en fortøjet båd (I025, A Little More Room Aboard) og spiller den lille piges farvel, når Kaptajnen siger "Ikke nu".
- **Hvad det gør:** Stiller en lille åben papkasse på pontonen, et stykke fra landgangen og havnens tjenester, med ragdoll-katten siddende i den, mopsen ved siden af eller parakitten på kanten; dyret bruger de samme billeder og klip som en ledsager. Et tryk på E er en venlig gestus (et goddag, en godbid fra Kaptajnens lomme, lidt leg), og bare at vente stille i nærheden et stykke tid tæller også, én gang. Efter tre følger det Kaptajnen: katten går rask til, mopsen traver, parakitten tager korte hop. Ved nedgangen spørger spillet, om det skal bydes velkommen om bord. "Ikke nu": det går tilbage til sin kasse, en lille pige kommer gående ad pontonen og vinker, dyret går hen til hende (katten spinder, mopsen logrer, parakitten op på hendes skulder), hun tager kassen op, og de går sammen. Ingen ord og ingen straf.
- **Arbejder sammen med:** `GameSession` (mødets tilstand, venlige gestus, nej tak), `DockEncounters`, `ShipCompanion` (dyret), `DockBox` (kassen), `DockGirl` (pigen), `CompanionRemarks` (tekst og linjer), `ShoreAccess` (pontonen), `DeckCompanionSpots`, `BoatArea` (bygger det og viser dets beskeder), `App` (stiller spørgsmålet om adoption), `SessionLog`.
- **Holder styr på:** Kun det, der er på skærmen: kassen, dyret, pigen, om dyret følger efter, og om farvellet spilles. Selve mødet holder `GameSession` styr på.
- **Hvornår det kører:** På dækket af en båd med en kaj, mens et dyr venter i den havn.
- **Hvis du ændrer det:** Hvordan dyret på kajen ser ud og opfører sig, og pigens farvel. Hold det fri for ord og for enhver straf for at sige "Ikke nu".

### `src/companion/dock_encounters.gd`

**Formål:** De gemte oplysninger om dyr, man finder på en kaj (I025, A Little More Room Aboard): om et venter lige nu, og hvad der holder møderne sjældne og retfærdige.
- **Hvad det gør:** En gang imellem, når båden ankommer til en havn, står der en lille åben papkasse på pontonen med en ragdoll-kat, en mops eller en grønkindet parakit i eller ved siden af (hver slags lige sandsynlig). Om en ankomst bringer et dyr, afgøres én gang, ved ankomsten, ud fra spillets vindfrø, havnen og ankomsttidspunktet, så det aldrig slås om, når man indlæser et gemt spil eller går ind og ud af kahytten. Chancen starter på 10 % og vokser med 8 % for hver ankomst uden et dyr, op til 60 % (i gennemsnit omkring hver femte ankomst). Der venter intet dyr, mens to ledsagere bor om bord. Tillid har ingen måler: tre venlige gestus, og dyret følger Kaptajnen. Det venter kun, mens båden ligger i den havn; når der kastes los, slutter mødet stille. Den husker også de sidste otte møder og tæller, hvor mange der blev tilbudt, adopteret og takket nej til.
- **Arbejder sammen med:** `SessionState` (ejer og gemmer det), `GameSession` (den eneste der ændrer det: lodtrækningen ved ankomst, venlige gestus, adoption, nej tak, afgang), `DockEncounterScene` (viser det), `CompanionState` (de tre slags).
- **Holder styr på:** Ankomster siden sidste møde, dyret der venter nu (havn, slags, siden hvornår, venter eller følger, tillid), de seneste møder og de tre tællere. Et dyr, der fulgte efter Kaptajnen, gemmes som ventende ved sin kasse, med tilliden bevaret.
- **Hvornår det kører:** Ved hver ankomst til en havn, og mens et dyr venter på kajen.
- **Hvis du ændrer det:** Hvor ofte man finder dyr, og gemte spil (afsnittet er valgfrit: alt, der mangler eller er forkert, indlæses blot som "intet dyr venter").

### `src/companion/dock_girl.gd`

**Formål:** Den lille pige på pontonen, der henter et dyr, Kaptajnen ikke tog om bord (I025).
- **Hvad det gør:** Kommer gående i et barns rolige tempo, stopper, vinker, tager kassen op og går igen; parakitten kan sidde på hendes venstre skulder. Hun tegnes af `GirlDrawing`. Hun er ikke en rigtig person i spillet: ingen handling, ingen samtale og intet gemt, kun dette korte øjeblik.
- **Arbejder sammen med:** `DockEncounterScene` (flytter hende), `GirlDrawing` (tegner hende), `DockBox` (kassen hun bærer).
- **Holder styr på:** Hvor hun går hen, hvilken vej hun vender, om hun vinker eller bærer kassen, og om hun har vinket (til testene).
- **Hvornår det kører:** Kun under farvellet efter "Ikke nu".
- **Hvis du ændrer det:** Kun farvellets udseende og tempo.

### `src/companion/girl_drawing.gd`

**Formål:** Tegner den lille pige set ovenfra, i samme stil som Kaptajnen (I025).
- **Hvad det gør:** Tegner hende med form i toner, en blød blækstreg og lys fra øverst til venstre, ligesom `SailorDrawing`: et barns proportioner ved siden af Kaptajnen (smallere skuldre, et lidt større hoved i forhold til hendes størrelse), to korte fletninger med sløjfer og en dæmpet rød regnfrakke med hætten nede. Kun det, hendes korte øjeblik kræver: at gå, at stå, et vink med den ene arm løftet og kassen båret i begge arme. De samme tal giver altid den samme tegning.
- **Arbejder sammen med:** `DockGirl` (beder den tegne), `SailorDrawing` (fælles formhjælpere), `DockBox` (den bårne kasse).
- **Holder styr på:** Intet; det er en samling tegnefunktioner.
- **Hvornår det kører:** Under pigens farvel.
- **Hvis du ændrer det:** Kun hvordan hun ser ud; hold hende som et barn ved siden af Kaptajnen og i spillets tegnede stil.

### `src/companion/pair_moments.gd`

**Formål:** To ledsagere om bord lægger en gang imellem mærke til hinanden (I025, A Little More Room Aboard).
- **Hvad det gør:** Højst hvert halvandet til tredje minut i virkelig tid, når begge hviler synligt, Kaptajnen er vågen, og tiden går med normal fart, spiller den et lille øjeblik, der passer til parret: et besøg og en hilsen, et blik på tværs af kahytten eller en lur på samme tid. Hvert par har sine egne øjeblikke og hilsner (kat og hund, kat og parakit, hund og parakit eller to af samme slags). Katten holder øje med fuglen, den lurer aldrig på den. Besøg sker kun i kahytten; på dækket bliver de på deres sikre pladser og hilser derfra. Ingen målere og ingen behov; intet gemmes.
- **Arbejder sammen med:** `BoatArea` (bygger den, når der er to ledsager-noder), `ShipCompanion` (gang og klip), `GameSession` (antal ledsagere, søvn, tidens fart), `CompanionState`, `CompanionVisualSet`, `WelcomeHome` (bruger dens hilsner), `SessionLog`.
- **Holder styr på:** Kun tiden til næste øjeblik, og om et øjeblik er i gang.
- **Hvornår det kører:** I kahytten og på dækket, mens to ledsagere bor om bord.
- **Hvis du ændrer det:** Hvordan to ledsagere opfører sig sammen. Hold øjeblikkene sjældne og blide og aldrig som jæger og bytte.

### `src/companion/ship_companion.gd`

**Formål:** Katten, hunden eller papegøjen, som du ser og kan kæle for, i kahytten, på dækket eller på pontonen.
- **Hvad det gør:** Viser ledsageren på dens hvilested med stillingsbilleder (hviler, sover, strækker sig, kigger op) eller et enkelt tegnet dyr, hvis der ikke er billeder. Tryk på E kæler for den: katten spinder og viser hjerter, hunden pruster og logrer, og en gang imellem (højst hvert 15. sekund) siger Kaptajnen et venligt ord, valgt af `CompanionRemarks`. Når den skifter mellem kahyt og dæk, mens du ser på, går den derhen. På en rolig ankerplads krøller den sig sammen og tager lange lure. I024: stillingerne er animerede klip med korte overgange imellem (lægge sig, vågne, vende, falde til ro); den vender sig, hvor den går hen, og går i sit eget skridts tempo, også når tidsplanen flytter den, mens du ser på. Papegøjen flyver mellem sine pinde (letter, flyver, lander) og hopper korte stykker. Fortøjet følger den Kaptajnen ned ad landgangen til en plads på pontonen, og på lange passager svarer den på Kaptajnens ord med et lille klip (`respond`). I025: hver kahyt og hvert dæk har en node til hver af op til to ledsagere (`slot` 0 eller 1); en plads uden nogen viser intet, og en anden ledsager på samme sted i kahytten ligger ved siden af den første, aldrig oven på den. Det samme script viser også det herreløse dyr, der venter på kajen (`stray`: sin egen handling "vind tillid" i stedet for kæl, og ingen tilstand i spillet), som går hurtigere end sin rolige gang, mens det følger Kaptajnen (`pace`; gåklippet går også hurtigere, så fødderne aldrig glider). `walk_to` lader kajscenen, velkomsten hjemme og parøjeblikkene få den til at gå hvorhen som helst. En nyadopteret ledsager spiller sin velkomst hjemme, første gang kahytten viser den. Rettet: dyr, der vendte mod venstre, blev tegnet én bredde for langt til højre.
- **Arbejder sammen med:** `GameSession` og `CompanionState` (hvor den skal være), `CompanionVisualSet` (billeder), `DeckCompanionSpots` (steder og ruter på dækket), `ShoreAccess` (landgangen og pontonen), `CompanionRemarks` (tekst og bemærkninger), `AudioManager` (lyde), `Interactable` og `HighlightResolver` (kæl og glød), `SessionLog`. Placeret i hver kahyts scene (den anden ledsagers node tilføjes af `BoatArea`) og bygget på dækket af `BoatArea`; `DockEncounterScene` (det herreløse dyr), `WelcomeHome` og `PairMoments` får den til at gå.
- **Holder styr på:** Kun hvordan den ser ud lige nu (stilling, klip og billede, retning, gåtur eller flugt, reaktion); intet gemmes.
- **Hvornår det kører:** Når kahytten eller dækket er på skærmen.
- **Hvis du ændrer det:** Hvordan ledsageren ser ud, bevæger sig og reagerer på kæl.

### `src/companion/welcome_home.gd`

**Formål:** Det første minut om bord for en nyadopteret ledsager (I025, A Little More Room Aboard).
- **Hvad det gør:** Første gang kahytten viser en ledsager, der lige er kommet om bord, spiller den et kort, stille øjeblik efter slags: katten udforsker lidt, ser sig forsigtigt omkring, strækker sig og falder til ro; mopsen traver rundt, logrer og snuser; parakitten flagrer op på en pind, kvidrer, puffer fjerene og falder til ro. Bor der allerede en ledsager om bord, som er i kahytten, går den nye først hen til den, og de hilser på hinanden, før begge falder til ro. Det spilles én gang og aldrig igen (heller ikke hvis det bliver afbrudt); forlader man kahytten, slutter det bare. Intet ved ledsagernes tilstand ændres.
- **Arbejder sammen med:** `ShipCompanion` (starter det og går), `GameSession` (markerer ledsageren som budt velkommen), `CompanionState`, `PairMoments` (hilsnerne), `CompanionVisualSet`, `SessionLog`.
- **Holder styr på:** Intet; det er en kortlivet hjælper, der fjerner sig selv.
- **Hvornår det kører:** Én gang for hver adopteret ledsager, første gang den ses i kahytten.
- **Hvis du ændrer det:** Kun velkomstøjeblikket; mærket for "spillet én gang" gemmes med ledsageren.

### `src/dev/dev_guides.gd`

**Formål:** Finder udviklerguiderne (Markdown-filerne i `DEV_GUIDES/`), så de kan læses inde i spillet.
- **Hvad det gør:** Oplister guidefilerne med indekset `README.md` først, læser en guides tekst og tager hver guides titel fra dens første overskrift. Guiderne tilbydes kun i udviklingsversioner (debug), hvor filerne findes.
- **Arbejder sammen med:** `DevGuidesMenu` (fremviseren i spillet), `MainMenu` (viser knappen) og `App`.
- **Holder styr på:** Kun hvilken mappe der læses fra (tests kan pege et andet sted hen).
- **Hvornår det kører:** Når hovedmenuen afgør, om guide-knappen skal vises, og når guidefremviseren åbnes.
- **Hvis du ændrer det:** Hvilke guider der vises i fremviseren og i hvilken rækkefølge; spillere af det færdige spil ser det aldrig.

### `src/dev/dev_test_panel.gd`

**Formål:** Udviklerens testpanel (F10): knapper til bevidst at afprøve vejr, skader, redning, proviant og tid.
- **Hvad det gør:** Viser knapper til teststorme og kuling, til at sætte bådens tilstand, en redningstest, til at sætte mad og vand og til at springe tiden frem, plus en løbende statuslinje om båden og vejret. Spillet står på pause, mens panelet er åbent.
- **Arbejder sammen med:** `DevTools` (gør selve arbejdet), `GameSession`, `Simulation`, `Provisions`, `VesselCondition`; åbnes af `App` (F10) eller pausemenuen.
- **Holder styr på:** Kun sine egne knapper og statuslinjen.
- **Hvornår det kører:** Kun når en udvikler åbner det, i versioner der køres fra Godot-editoren.
- **Hvis du ændrer det:** Kun udviklerens testværktøjer; intet i det normale spil.

### `src/dev/dev_tools.gd`

**Formål:** Genveje kun for udviklere, der får sjældne situationer til at ske med det samme, så de kan afprøves.
- **Hvad det gør:** Laver testvejr (kuling, storm, tordenbyge eller en storm på kursen forude), sætter bådens tilstand eller proviant, forbereder en redningstest og flytter tiden frem gennem den normale simulation. Testvejr gemmes aldrig og fjernes, når et spil startes, indlæses eller afsluttes.
- **Arbejder sammen med:** `WeatherFixtures` (laver testvejret), `GameSession`, `Simulation`, `GeoMath`; bruges af `DevTestPanel`, `App` og pausemenuen.
- **Holder styr på:** Hvilket testvejr der er aktivt, og en kontakt som tests bruger til at slå værktøjerne til eller fra.
- **Hvornår det kører:** Kun i debug-versioner der køres fra Godot-editoren (og ikke med `--no-dev-tools`).
- **Hvis du ændrer det:** Kun udviklertest, men en fejl kunne lade testvejr slippe ind i et rigtigt spil.

### `src/dev/weather_fixtures.gd`

**Formål:** Laver håndplaceret vejr (kuling, tordenvejr, cykloner) til tests og udviklerværktøjer.
- **Hvad det gør:** Bygger vejrhændelser på et valgt sted, tidspunkt og med en valgt styrke, som opfører sig præcis som spillets naturlige vejr, og lægger dem ind i vejrmodellen, eventuelt med det normale tilfældige vejr slået fra. `clear()` sætter alt tilbage til normalt.
- **Arbejder sammen med:** `WeatherModel` og `WeatherEvent` (vejrsystemet), `Simulation` (rydder sine overslag), `DevTools` og mange testsuiter.
- **Holder styr på:** Intet selv; det ændrer vejrmodellens liste over testvejr.
- **Hvornår det kører:** Kun i automatiske tests og udviklerværktøjer, aldrig i normalt spil.
- **Hvis du ændrer det:** Mange automatiske tests kan begynde at fejle, fordi de bygger på netop dette vejr.

### `src/fishing/fish_art.gd`

**Formål:** Finder de malede billeder af hver fisk, haj og hvert stykke skrald.
- **Hvad det gør:** Læser `data/fishing/fish_art.json` for at kende hvert billedes størrelse, halens drejepunkt og om det bevæger sig, og indlæser billedlagene (krop, hale, lukket øje, eller ét billede for skrald) samt et lille miniaturebillede. En erstatning fra Sprite Workshop vinder, hvis den findes.
- **Arbejder sammen med:** `FishPortrait`, fiskerimenuen, trofæmenuen og trofætavlen samt `ArtworkResolver`.
- **Holder styr på:** En kopi af billedoplysningerne, der indlæses én gang.
- **Hvornår det kører:** Hver gang en fangst vises: under indhaling, ved resultatet, i køleboksen og på trofætavlen.
- **Hvis du ændrer det:** Hvordan fangster ser ud overalt i spillet.

### `src/fishing/fish_portrait.gd`

**Formål:** Viser en fanget fisk stort og levende: den blinker, slår med halen og vipper blidt.
- **Hvad det gør:** Lægger fiskens billedlag oven på hinanden og animerer dem med uregelmæssig timing, så to fisk aldrig blinker samtidig. Skrald ligger bare stille. Med "reducér bevægelse" slået til er det kun blinket, der bliver.
- **Arbejder sammen med:** `FishArt` (billederne), `SettingsManager` (reducér bevægelse); bruges af fiskerimenuen.
- **Holder styr på:** Hvilken fisk den viser, og sine animationstimere.
- **Hvornår det kører:** Mens en fisk vises stort i fiskeriskærmene; den holder op med at arbejde, når den er skjult.
- **Hvis du ændrer det:** Hvordan fangne fisk ser ud, og hvor levende de virker.

### `src/fishing/fishing_catalog.gd`

**Formål:** Fiskeriets regelbog: blink og agn, fiskearter, skrald, hvor fiskene bider, og hvad de er værd.
- **Hvad det gør:** Læser `data/fishing/fishing.json` og afgør, hvilke fisk der kan bide hvor (ud fra den nærmeste havns område, og kystfisk kun nær land), chancen for et bid (lavere i hård vind, ingen ved slæbefiskeri i for høj fart), fisken og dens vægt, størrelsesgrader (bronze, sølv, guld), hvor svær indhalingen er efter sjældenhed, trofæpoint og salgspris. Valgene bruger et terningkast, som spillet sætter fast, så samme øjeblik altid giver samme bid.
- **Arbejder sammen med:** `PortCatalog` og `GeoMath` (områder), `HatStory` (afstand til åbent vand), `FishingState`, `GameSession`, `Simulation` og menuerne for fiskeri, fiskehandler, købmand, skibshandel og trofæer.
- **Holder styr på:** De indlæste fiskeridata (én fælles kopi).
- **Hvornår det kører:** Når nogen fisker, sælger fisk eller ser på fangster.
- **Hvis du ændrer det:** Hvilke fisk spillerne fanger hvor, hvor ofte, hvor store, hvor svært, og hvor meget de tjener.

### `src/fishing/fishing_sounds.gd`

**Formål:** En lille liste over korte lydsignaler til fiskeri, kabyssen og ankeret.
- **Hvad det gør:** Udleverer lydene for kast, bid, hjul, plask, knækket line, stegning, ankerkæde og advarselsbip, som alle spilles stille. Hver lyd har også noget, man kan se, så ingen behøver at høre den.
- **Arbejder sammen med:** `AudioManager` (spiller dem), `App` og menuerne for fiskeri, madlavning og anker.
- **Holder styr på:** Intet; det indlæser bare lydfilerne.
- **Hvornår det kører:** Når de handlinger sker.
- **Hvis du ændrer det:** Hvilke lyde der spilles ved fiskeri, madlavning og ankring.

### `src/fishing/reel_timing.gd`

**Formål:** Indhalingsspillet for en fangst: tryk, mens nålen er inde i målbuen.
- **Hvad det gør:** Det er den fælles timingskive (`TimingCheck`), brugt til fiskeri. Sjældnere fisk kræver flere gode tryk og har et smallere mål; et perfekt tryk gør den landede fisk lidt tungere. Tre forbiere taber fisken, og gør man ingenting i et minut, smutter den. Filen tilføjer kun fiskerinavnet og beskrivelsen; selve skiven ligger i `TimingCheck`.
- **Arbejder sammen med:** `TimingCheck`, `FishingCatalog` (hvor mange tryk og hvor bred), fiskerimenuen og `ReelDial` (tegner den).
- **Holder styr på:** Det samme som skiven: nålens position, målet, træffere, perfekte tryk og forbiere.
- **Hvornår det kører:** Mens et bid hales ind.
- **Hvis du ændrer det:** Ændringer i selve skiven sker i `TimingCheck` og påvirker også Magic Anchor.

### `src/galley/recipes.gd`

**Formål:** Kabyssens enkle retter, og hvad hver af dem giver.
- **Hvad det gør:** Oplister fem retter (grød, brød og suppe, stegt fisk, fiskegryde, en sømandsaftensmad) med hvor mange fisk og hvor meget mad de bruger, tilberedningstid, og hvor længe besætningen er "godt mæt". Fiskeretter gør fisk til ekstra dages mad, højst tre dage pr. ret.
- **Arbejder sammen med:** `GameSession` (som står for madlavningen) og madlavningsmenuen.
- **Holder styr på:** Intet ud over den faste opskriftsliste.
- **Hvornår det kører:** Når kaptajnen laver mad i kabyssen.
- **Hvis du ændrer det:** Hvor nyttigt fiskeri og madlavning er for proviantbeholdningen.

### `src/harbour/business_hours.gd`

**Formål:** Åbningstiderne for kajens forretninger (I026).
- **Hvad det gør:** Læser tiderne for hver slags forretning fra `data/harbours/business_hours.json`: caféen åbner tidligt, sejlmageren sent, bådeværftet holder arbejdstid og holder fri om søndagen. En kaj ved Middelhavet åbner lidt senere og holder åbent ind i aftenen, en lille havn har kortere åbningstid og en stor havn længere. Alt følger havnens egen soltid og spillets ene ur, så en butik har åbent præcis, når lyset siger, at det er morgen eller aften dér. Den svarer på, om en dør er åben, hvornår den næste gang åbner eller lukker, og skriver ordene til døren og prompten ("open until 17:00", "closed · opens 09:00 (in 3 h 10 min)"). Havnekontorets luge uden for åbningstid er altid bemandet. Intet gemmes.
- **Arbejder sammen med:** `HarbourFront` (døre og prompter), `App` (tilbuddet om at vente, til en butik åbner), `HarbourNotes`, `HarbourLife`, `HarbourDressing` (egnen), `HarbourFacilities` (havnens størrelse), `Daylight`, `GameSession`, `PortCatalog`.
- **Holder styr på:** Tabellen med åbningstider, indlæst én gang.
- **Hvornår det kører:** På kajen, når en dør, en prompt eller opslagstavlen skal bruge åbningstiderne.
- **Hvis du ændrer det:** Hvornår butikkerne har åbent; man kan altid vente på en lukket butik, og det nødvendige kan stadig klares ved lugen.

### `src/harbour/harbour_art.gd`

**Formål:** Valgfri ekstra grafik til én bestemt havn: op til tre billeder af vartegn og vandets stemning.
- **Hvad det gør:** Leder efter en fil `data/harbours/<port_id>.tres` (indtil videre har kun København en). Findes den, giver den de vartegnsbilleder, der tegnes bag gæstebroen (højst tre), og fortæller, om vandet skal føles som en lystbådehavn, en kyst eller en by. Havne uden fil får bare den normale tegnede havn.
- **Arbejder sammen med:** `HarbourLandmark` (hvert billede), `HarbourDressing` (tegner dem), `WaterLife` (bruger vandets stemning).
- **Holder styr på:** Havnens id, dens vartegn og indstillingen for vandets stemning.
- **Hvornår det kører:** Når båden ligger i en havn, og havnens kulisse tegnes.
- **Hvis du ændrer det:** Hvordan en særlig havn ser ud; vartegn er kun billeder og spærrer aldrig for gang eller fortøjning.

### `src/harbour/harbour_dressing.gd`

**Formål:** Tegner den illustrerede havn omkring den fortøjede båd: flydebro, fortøjninger, klamper, stenkaj, krusninger i vandet, skilte for havnens tilbud og vartegn.
- **Hvad det gør:** Læser, hvor den eksisterende flydebro, fortøjningerne og stationerne er, og maler havnen oven på dem set fra oven (Real Horizon): en flydebro, marinaskilte for købmanden, bådeværftet og Gå i land, kajen og byen i en af fire regionale typer og naboer fortøjet på den anden side af løbet; havnens udseende eller eget vartegn (HarbourLooks) dækker byen, hvor den har et. Står indstillingen Grafik på "Classic", skjuler den sig, og den gamle enkle tegning vises. Den fortæller også belysningen, hvor kajens lygter og broens lys er. Siden I021 kommer udsigten bag kajen fra HarbourLooks: havnens eget vartegn eller illustrationen for dens udseende. I025: havnen tegnes i bådens rigtige målestok (100 scene-enheder pr. meter, `METRE`). Byens huse har rigtige facadebredder og dybder for deres egn (`TOWNS`): træhuse og bådskure med gavlen ud mod vandet i den nordiske havn, granitrækkehuse med skifertage og skorstene ved Atlanterhavet, pudsede huse med skodder, vingetegl og tagterrasser ved Middelhavet, lave huse med verandaer under malet bølgeblik mellem palmer i troperne, med stræder, tilbagetrækninger og træer imellem, og byens bagerste del falmer lidt ind i disen. Hvor havnen har sit eget billede, starter husrækkerne fra billedets ender, så intet hus skæres over. På den anden side af løbet ligger nabobåde i deres rigtige størrelse og fra egnens egen flåde (`FLEETS`, `BOAT_SIZES`: tursejlere og større lystbåde, små sejlbåde, motorbåde, katamaraner, fiskekuttere og krabbebåde, små åbne både og joller), fortøjet med stævnen ind, eller med agterenden mod kajen ved Middelhavet, og let disede. I026: tilbuddene er flyttet op på kajen, så pontonens eneste skilt nu er gangbroens ("To the quay", med sit eget lille ikon af trin op til et hus), og den tegner aluminiumsgangbroen med trin og håndlister, der går fra bagkanten af pontonen op på kajen.
- **Arbejder sammen med:** `BoatArea` (som tilføjer den), `HarbourArt` og `HarbourLandmark`, `SettingsManager` (grafikstil), `GameSession` (hvilken havn), `HighlightProvider`/`HighlightResolver` (skiltenes glød), `Interactable`-stationer.
- **Holder styr på:** Former den har læst fra dækket, de aktuelle skilte og vartegn samt de klassiske skilttekster, så den kan skifte tilbage.
- **Hvornår det kører:** Når båden ligger fortøjet i en havn, og dækket vises; opdateres når havnen eller indstillingen skifter.
- **Hvis du ændrer det:** Udseendet af alle havne; det er kun grafik og ændrer ikke gang, fortøjning eller knapper.

### `src/harbour/harbour_facilities.gd`

**Formål:** Fortæller, hvilke tilbud en havn har: købmand, bådeværft, optagningsværft, Gå i land og de håndværk, der følger med.
- **Hvad det gør:** Bruger en fil i `data/harbours/facilities/`, hvis havnen har en; ellers får alle havne det hele, og store havne kan også tage både på land. Det inddeler havnene i små, større eller store servicehavne og skriver oversigten over tilbud, der vises på søkortet.
- **Arbejder sammen med:** `PortCatalog` (hvilke havne er store), `HarbourTrades` (skibshandel, sejlmager, fiskehandler), `BoatArea` (stationerne på land), `GameSession`, `WorldMap` og butiksmenuerne.
- **Holder styr på:** Fire til/fra-kontakter pr. havn plus en hukommelse (cache) af indlæste havnefiler.
- **Hvornår det kører:** Ved ankomst til en havn, når en butik åbnes, eller når man ser på et mål på søkortet.
- **Hvis du ændrer det:** Hvor spilleren kan købe mad, reparere, få båden taget op eller besøge håndværkerne.

### `src/harbour/harbour_front.gd`

**Formål:** Kajen: den kajstrækning ved enden af gæstebroen, man kan gå på, hvor hver af havnens forretninger har sin egen bygning (I026).
- **Hvad det gør:** Bygger kajen til den havn, båden ligger i: vandet og broens ende forneden, promenaden med bænke og lygter og butiksfacaderne langs toppen (kun de forretninger, havnen har, i egnens stil), med sine folk og de ledsagere, der er i land med Kaptajnen. Kameraet følger Kaptajnen langs kajen i rigtig målestok. Hver dør, havnekontorets luge uden for åbningstid, opslagstavlen, stræden ind til byen og bådliften lyser op og har en prompt, der siger, om stedet har åbent. Bruges en af dem, beder den appen åbne menuen; går man ned ad gangbroen igen (eller trykker E for enden af den), kommer man tilbage til båden. På caféen sætter Kaptajnen sig ved et bord på terrassen med en kop kaffe og rejser sig igen med E eller en bevægelsestast. Lyset følger timen: oplyste vinduer og lygter i skumringen, mørke butikker om natten. Det er en skærm ligesom søkortet, ikke et sted i det gemte spil: gemmer man her, indlæses spillet om bord, ved gangbroen. Rejser Kaptajnen sig fra caféen, er det ud på det første frie sted ved stolen, aldrig ind i nabobordet. I027: et tankanlægs pumpe ved gangbroens ende, med literprisen i prompten.
- **Arbejder sammen med:** `QuayLayout` (hvor alt står), `QuayDrawing`, `StorefrontDrawing`, `HarbourLife`, `QuayCompanion`, `BusinessHours`, `Interactable`, `Player`, `GameSession`, `App` (åbner menuerne og klarer at gå tilbage), `SceneRouter`.
- **Holder styr på:** Layoutet, tegningerne og stationerne, ledsagerne på kajen og den caféstol, der er i brug; intet i spillets tilstand.
- **Hvornår det kører:** Mens Kaptajnen er på kajen.
- **Hvis du ændrer det:** Hvordan man går og gør ting på kajen; butikkernes menuer og det gemte spil ændres ikke af den.

### `src/harbour/harbour_landmark.gd`

**Formål:** Ét billede af et vartegn til en havn (for eksempel Nyhavn i København).
- **Hvad det gør:** Indeholder en titel, billedet, hvor det står i forhold til kajen, og hvor bredt det tegnes.
- **Arbejder sammen med:** `HarbourArt` (oplister det) og `HarbourDressing` (tegner det).
- **Holder styr på:** Kun de fire indstillinger.
- **Hvornår det kører:** Når havnens kulisse tegnes.
- **Hvis du ændrer det:** Størrelsen og placeringen af et vartegnsbillede; det påvirker aldrig spillet.

### `src/harbour/harbour_life.gd`

**Formål:** Folkene på kajen: en håndfuld byboere med små vaner, så en havn føles beboet (I026).
- **Hvad det gør:** Bestemmer, hvem der er ude, ud fra havnen, dagen og timen, altid de samme for det samme øjeblik: spadserende, der standser ved et butiksvindue, en bænk eller vandkanten; kunder, der går ind i en åben butik og kommer ud igen; cafégæster, der sidder, læser eller snakker, mens caféen har åbent; en fisker med sine net om morgenen; en handlende, der låser af ved lukketid; og en sen spadserende om natten. En større havn er mere travl, en lille er stille, og der er få eller ingen om natten og i dårligt vejr. Intet sker, mens Kaptajnen er væk: efter en søvn viser kajen bare, hvem der er ude på den nye time. Folk går i roligt tempo, står aldrig i en døråbning eller for enden af gangbroen og går uden om Kaptajnen.
- **Arbejder sammen med:** `HarbourFront` (tilføjer den), `QuayLayout`, `BusinessHours`, `TownsfolkDrawing` (hvordan de ser ud), `Simulation` (vejret), `GameSession` (uret).
- **Holder styr på:** De folk, der er på kajen nu, og de caféstole, Kaptajnen har taget.
- **Hvornår det kører:** På kajen; hvert par sekunder sammenligner den, hvem der burde være ude, med hvem der er.
- **Hvis du ændrer det:** Hvor livlige havnene føles; folkene er kun kulisse og ændrer intet i spillet.

### `src/harbour/harbour_looks.gd`

**Formål:** Bestemmer, hvordan hver havn ser ud bag gæstebroen, og hvilke havne der er særlige (I021).
- **Hvad det gør:** Læser tabellen over havnenes udseende (`data/harbours/harbour_looks.json`). Hver havn har et udseende, valgt efter hvordan stedet virkelig ser ud: nordisk træhavn, havneby med gavlhuse, stenhavn ved Atlanterhavet, middelhavsby, ø-havn i Det Ægæiske Hav, gammel stenby, tropisk havneby, tropisk ø eller vulkanø. En havn med sit eget billede (som Nyhavn i København eller bastionerne i Valletta) viser det i stedet, og de få havne er de særlige havne, der får en stjerne på søkortet. Den giver også billedet til ankomstkortet.
- **Arbejder sammen med:** `HarbourArt` og `HarbourLandmark` (billederne), `HarbourDressing` (tegner dem), `MapView` og `WorldMap` (stjernen og linjen "Særlig havn"), `App` (ankomstkortet), `Loc` (navne på dansk).
- **Holder styr på:** Tabellen, den har læst, og hvert udseendes billede, når det først er brugt (så mange havne med samme udseende ikke koster ekstra).
- **Hvornår det kører:** Når du fortøjer, ankommer eller ser på en havn på søkortet.
- **Hvis du ændrer det:** Hvordan havnene ser ud, og hvilke der er mærket som særlige; mangler et billede, vises blot den almindelige kaj, aldrig en fejl.

### `src/harbour/harbour_notes.gd`

**Formål:** Det, havnekontoret og opslagstavlen på kajen fortæller (I026).
- **Hvad det gør:** Skriver ud fra data, spillet allerede har, havnens størrelse og tilbud, åbningstiderne for alle forretningerne på kajen, havnens egen beskrivelse og hvorfor den er særlig, vejrudsigten i ord for nu og om 6, 12 og 24 timer ("This evening: wind SW 14 kn, gusts 22 · fair") og nogle få små opslag for ugen fra `data/harbours/notices.json`. Kun oplysninger: ingen opgaver, intet at tjene, og aldrig en erstatning for vejr- og trafikadvarslerne, som kommer som altid.
- **Arbejder sammen med:** `HarbourOfficeMenu`, `NoticeboardMenu`, `HarbourFacilities`, `BusinessHours`, `PortData`, `HarbourLooks`, `Simulation` (vejrudsigten).
- **Holder styr på:** Filen med opslag, indlæst én gang.
- **Hvornår det kører:** Når havnekontoret eller opslagstavlen åbnes.
- **Hvis du ændrer det:** Ordene på kontorets side og på opslagstavlen.

### `src/harbour/harbour_trades.gd`

**Formål:** Havnens håndværk og butikker: skibshandlen, sejlmageren og fiskehandleren samt de små ting, man kan købe til kahytten.
- **Hvad det gør:** Læser kataloget `data/harbours/trades/trades.json`. En havn med købmand har en fiskehandler; en havn med bådeværft har en skibshandel og en sejlmager. Det giver kahyttens pynt, sejldugens farver og priser, skibshandlens opgraderinger, prisen på Magic Anchor og et navn på fiskehandleren, som er det samme ved hvert besøg.
- **Arbejder sammen med:** `HarbourFacilities`, `GameSession`, `HomeState`, `CabinDecor`, `SailRig` (sejlfarver), `BoatArea` og menuerne for skibshandel, sejlmager, fiskehandler, bådpleje og kahytten.
- **Holder styr på:** En kopi af håndværkskataloget, der indlæses én gang.
- **Hvornår det kører:** Når håndværkernes menuer åbnes, kahytten pyntes, eller sejlene tegnes.
- **Hvis du ændrer det:** Hvad håndværkerne sælger og til hvilken pris, og hvordan sejlene ser ud; alt her er valgfrit for sejladsen.

### `src/harbour/quay_companion.gd`

**Formål:** En ledsager i land på kajen, der følger Kaptajnen (I026).
- **Hvad det gør:** Viser en ledsager, der er i land med Kaptajnen, på kajen med sine egne tegnede gå- og hvilebilleder; den trisser efter Kaptajnen i lidt afstand (to holder afstand til hinanden) og hviler, når Kaptajnen står stille. På caféen slår den sig ned ved Kaptajnens bord: katten og hunden lægger sig ved siden af, papegøjen sætter sig på stoleryggen. Den ændrer intet i ledsagerens tilstand, har ingen kollision og kan ikke klappes her (det gør man om bord).
- **Arbejder sammen med:** `HarbourFront` (tilføjer én for hver ledsager i land), `CompanionState`, `CompanionVisualSet`.
- **Holder styr på:** Hvilken ledsager den viser, dens plads i rækken, dens billede og hvor den hviler ved caféen.
- **Hvornår det kører:** På kajen, mens ledsageren er i land.
- **Hvis du ændrer det:** Hvordan ledsagerne ser ud på kajen; deres rigtige tilstand røres ikke.

### `src/harbour/quay_drawing.gd`

**Formål:** Tegner kajens underlag set oppefra: promenaden, stenkanten langs vandet, vandet og broens ende (I026).
- **Hvad det gør:** Maler promenaden i havnens egnsstil (brosten i nord, kalkstensfliser i syd), granitkanten med pullerter, lygtepæle og bænke, havnebassinet og enden af gæstebroen med gangbroen, der kommer op fra den, byen i disen bag den forreste husrække og, hvor bådeværftet tager både på land, bådliften over sin dok. Opslagstavlen står ved enden af gangbroen. Den tegnes én gang; kajen ændrer sig ikke, mens Kaptajnen er der. I027: den tegner tankanlæggets pumpe på kajkanten.
- **Arbejder sammen med:** `HarbourFront` (tilføjer den og bruger dens bænke, lygter og omrids), `QuayLayout`, `HarbourDressing` (egnsstilene).
- **Holder styr på:** Layoutet og den stil, den tegner.
- **Hvornår det kører:** På kajen.
- **Hvis du ændrer det:** Hvordan kajens underlag ser ud; mure og stationer hører til `HarbourFront`.

### `src/harbour/quay_layout.gd`

**Formål:** Hvor alt står på en havns kaj, altid det samme for den samme havn (I026).
- **Hvad det gør:** Lægger kajen ud alene ud fra havnens id, så testene kan læse den uden en scene: fra arbejdsenden til byenden bådeværftet (med bådliften, hvor værftet tager både op), sejlmageren og skibshandelen, havnekontoret med opslagstavlen ved gangbroen, så caféen, købmanden, fiskehandlerens bod og stræden ind til byen (Gå i land). Kun de forretninger, havnen faktisk har, står der (håndværkerne følger deres hovedforretning), og almindelige huse fylder resten; caféen, havnekontoret og opslagstavlen findes i alle havne. Den placerer også caféens terrasseborde og stole og ved, hvor folk ikke må blive stående (foran en dør og for enden af gangbroen). I027: den placerer også tankanlægget ved gangbroens ende på hver kaj.
- **Arbejder sammen med:** `HarbourFront`, `QuayDrawing`, `StorefrontDrawing`, `HarbourLife`, `HarbourFacilities`, `HarbourTrades`, `HarbourDressing` (egnen).
- **Holder styr på:** Facaderne, opslagstavlens og liftens pladser, kajens ender og caféens borde og stole.
- **Hvornår det kører:** Når kajen bygges, og i testene.
- **Hvis du ændrer det:** Rækkefølgen og størrelsen af kajens bygninger i alle havne.

### `src/harbour/shore_access.gd`

**Formål:** Lader kaptajnen gå i land: en landgangsbro fra båden ned til flydebroen og et stykke bro at gå på.
- **Hvad det gør:** Ud fra hver båds egen indretning placerer det landgangen, åbner et hul i søgelænderet præcis dér og bygger vægge, så båd, landgang og flydebro bliver ét område at gå på. Det tilbyder pladser langs broen til servicestationerne. Under sejlads lukkes søgelænderet igen, og landgangen forsvinder.
- **Arbejder sammen med:** `BoatArea` (ejer det og placerer stationerne), `GameSession` og `SessionLog` (noterer, når spilleren går over).
- **Holder styr på:** Formen på flydebroen og landstrimlen, landgangens placering, de ekstra vægge, og om spilleren er i land.
- **Hvornår det kører:** På dæk med en fortøjning; slået til i havn og fra på havet.
- **Hvis du ændrer det:** Om spilleren kan komme af og på båden, eller sidder fast ved søgelænderet.

### `src/harbour/shore_events.gd`

**Formål:** Det lille bibliotek af hyggelige "Gå i land"-øjeblikke i en havn.
- **Hvad det gør:** Indeholder korte scener som en havnecafé, en venlig sejler eller måger der kigger på din sandwich, hver med ét eller to valg, der koster nogle få euro og lidt tid. Nogle havne (København, Lohals) og områder (Atlanterhavsøerne, Caribien, Mellemamerika, Stillehavet) har deres egne. Første gang du træffer et valg i en havn, kan det give lidt ry og kommer i Logbogen.
- **Arbejder sammen med:** `GameSession` (udfører valget og belønningen), `PortCatalog` (havnens område), menuen Gå i land.
- **Holder styr på:** Intet ud over de faste tekster; hvilke øjeblikke du har haft, gemmes et andet sted.
- **Hvornår det kører:** Når kaptajnen vælger Gå i land i en havn.
- **Hvis du ændrer det:** Tekster, priser og ry for havneudflugter; omdøbes en hændelse, kan den tælle som ny igen.

### `src/harbour/storefront_drawing.gd`

**Formål:** Tegner én facade på kajen: en forretnings butiksfacade, et almindeligt hus eller stræden ind til byen (I026).
- **Hvad det gør:** Maler facaden opret over kajen i havnens egnsstil (nordisk træ, atlantisk granit og puds, middelhavsstuk med skodder, tropiske malede brædder under bølgeblik), med det, der står udenfor, set oppefra. Hver forretning kan kendes på sin bygning, sit skilt og sine ting udenfor: bådeværftets værkstedsskur med et skrog på bukke, sejlmagerens hejsebom og rullet sejldug, skibshandelens vinduer med tovværk og bøjer og fendere ved døren, købmandens stribede markise og kasser, fiskehandlerens bod med fisk på is, caféens markise og terrasse, havnekontorets ur, flagstang og luge uden for åbningstid. Døren har et åben/lukket-skilt og en plade med åbningstiderne; åbne butikker har lysende vinduer i skumringen og om natten, lukkede er mørke, og husene tænder et vindue eller to om aftenen. Ingen rigtige mærker: skiltene siger, hvad stedet er.
- **Arbejder sammen med:** `HarbourFront` (tilføjer dem og sætter timens tilstand), `QuayLayout`, `HarbourDressing` (egnsstilene), `BusinessHours` (gennem HarbourFront).
- **Holder styr på:** Sin facade, om der er åbent, hvor mørkt det er, pladen med åbningstider og sine vinduer.
- **Hvornår det kører:** På kajen; den tegner igen, når timens tilstand ændrer sig.
- **Hvis du ændrer det:** Hvordan kajens bygninger ser ud; det er kun grafik.

### `src/harbour/townsfolk_drawing.gd`

**Formål:** Tegner havnens folk set oppefra, i samme stil som Kaptajnen og den lille pige (I026).
- **Hvad det gør:** Tegner en person med form i toner, en blød blækstreg og naturlige voksne proportioner: en frakke, skuldre, arme der svinger lidt, hår eller en hat og stort set intet ansigt. Tøjet følger egnen (olietøj og uld i nord, voksbomuld og marineblåt ved Atlanterhavet, hør ved Middelhavet, let bomuld og stråhatte i troperne). Hver persons udseende laves én gang ud fra et tal, så den samme person altid ser ens ud. Stillinger: stående eller gående, siddende ved et bord eller bærende på en indkøbspose, en avis, en kop eller nøgler.
- **Arbejder sammen med:** `HarbourLife` (hver byboer), `SailorDrawing` og `GirlDrawing` (den fælles stil).
- **Holder styr på:** Intet (farvepaletterne ligger fast).
- **Hvornår det kører:** Hver gang en person på kajen tegnes.
- **Hvis du ændrer det:** Hvordan byboerne ser ud.

### `src/hat/hat_art.gd`

**Formål:** Billederne af kaptajnshuen: på knagen, på hovedet og når den tumler af sted i vinden.
- **Hvad det gør:** For hvert af de tre udseender bruger det i denne rækkefølge: et billede angivet i indstillingsfilen, derefter en PNG med navnet `hat_<udseende>.png` i grafikmappen, derefter den enkle tegnede hue. En erstatning fra Sprite Workshop vinder, hvis den findes. Det tegner også det valgte billede i den rigtige størrelse og drejet den rigtige vej.
- **Arbejder sammen med:** `HatDrawing` (den tegnede reserve), `ArtworkResolver`, `HatHook`, `PlayerHat`, `HatBlowAway`, huemærket; indstillinger i `data/hat/hat_art.tres`.
- **Holder styr på:** Hvilke billeder der bruges, deres størrelser og en kontakt, der tvinger den tegnede hue frem.
- **Hvornår det kører:** Hver gang huen tegnes.
- **Hvis du ændrer det:** Hvordan huen ser ud; det ændrer aldrig, om du har huen.

### `src/hat/hat_blow_away.gd`

**Formål:** Den korte "din hue er væk!"-animation på dækket.
- **Hvad det gør:** Huen tumler med vinden, løfter sig lidt, efterlader vindstriber og falmende ekkoer og forsvinder efter omkring 2,8 sekunder. Den er kun til pynt; selve tabet håndteres af `GameSession`.
- **Arbejder sammen med:** `HatArt` (billedet af den tumlende hue); oprettes af `BoatArea`, når huen blæser væk.
- **Holder styr på:** Sin retning og hvor langt animationen er nået.
- **Hvornår det kører:** Kun i de få sekunder, efter huen er tabt på dækket.
- **Hvis du ændrer det:** Hvor tydeligt og sjovt øjeblikket er, når huen blæser væk.

### `src/hat/hat_config.gd`

**Formål:** Balancetallene for kaptajnshuen: prisen og hvordan vinden belaster en hue, man har på.
- **Hvad det gør:** Læser `data/hat/hat_config.json`. Det regner ud, hvor meget belastning en hue på hovedet samler pr. spilminut i en given vind og vindstød (halvt så meget i en havn i læ), og hvor meget hver hue kan tåle, før den blæser væk (fast for hver hue, mellem to grænser).
- **Arbejder sammen med:** `Simulation` (tjekker huen hvert spilminut), `GameSession` og `HatState` (bruger resultatet).
- **Holder styr på:** Prisen, vindintervallerne, intervallerne for vindstød, hvor hurtigt huen kommer sig, timingen af advarsler og belastningsgrænserne.
- **Hvornår det kører:** Hver gang spillet tjekker huen i vinden.
- **Hvis du ændrer det:** Hvor ofte huer blæser væk, og hvad en ny koster hos købmanden.

### `src/hat/hat_drawing.gd`

**Formål:** Den enkle indbyggede tegning af kaptajnshuen set ovenfra.
- **Hvad det gør:** Tegner en hvid puld, et marineblåt bånd, en blank sort skygge og et lille messingmærke med en tynd, gennemsigtig kontur i Real Horizon-udtrykket. Bruges, når der ikke er et billede af huen.
- **Arbejder sammen med:** `HatArt` (kalder den som reserve).
- **Holder styr på:** Intet; kun farver.
- **Hvornår det kører:** Hver gang huen tegnes uden et billede.
- **Hvis du ændrer det:** Standardhuens udseende overalt.

### `src/hat/hat_hook.gd`

**Formål:** Knagen i rustfrit stål i kahytten, hvor kaptajnshuen hænger.
- **Hvad det gør:** Tegner knagen, og huen på den, mens huen er hængt op. Den lyser op, når kahyttens hue-station er valgt.
- **Arbejder sammen med:** `GameSession` (huens tilstand), `HatArt`, `HighlightResolver`; placeres ved hver kahyts `Layout/HatSpot` af `BoatArea`.
- **Holder styr på:** Kun om huen hænger der lige nu.
- **Hvornår det kører:** Mens kahytten er på skærmen.
- **Hvis du ændrer det:** Hvordan knagen og den ophængte hue ser ud i kahytten.

### `src/hat/hat_story.gd`

**Formål:** Ordene omkring kaptajnshuen: beskeder og linjer i Logbogen, når en hue blæser væk.
- **Hvad det gør:** Navngiver stedet ud fra spillets faktiske tilstand ("i Københavns havn", "ca. 12 sm ud for Skagen"), vælger en munter tabsbesked og skriver loglinjen med den faktiske vind og vindstød. Det måler også, hvor langt åbent vand der er omkring et punkt, hvilket fiskeriet også bruger.
- **Arbejder sammen med:** `PortCatalog`, `GeoMath`, `SeaRouter`/`NavGrid` (søkortet), `WeatherSample`/`WeatherModel`; bruges af `GameSession` og `FishingCatalog`.
- **Holder styr på:** Intet ud over sine faste beskeder.
- **Hvornår det kører:** Når en hue tabes, og når fiskeriet spørger, om et sted ligger nær kysten.
- **Hvis du ændrer det:** De huetekster spillerne læser, og hvilke fisk der tæller som kystfisk.

### `src/hat/player_hat.gd`

**Formål:** Huen på kaptajnens figur: på hovedet eller under armen.
- **Hvad det gør:** Følger huens tilstand i spillet og tegner den på hovedet, drejet den vej kaptajnen vender, eller båret i hånden. Det er kun et billede; kaptajnen bevæger sig og støder ind i ting på samme måde med eller uden den.
- **Arbejder sammen med:** `GameSession` (huens tilstand), `HatArt`, `HatState`; sættes på kaptajnen af `Player`.
- **Holder styr på:** Hvad den viser lige nu, og hvilken vej kaptajnen vender.
- **Hvornår det kører:** Når kaptajnen er på skærmen.
- **Hvis du ændrer det:** Hvordan huen ser ud på kaptajnen.

### `src/sailing/course_maker.gd`

**Formål:** Afgør, hvilken vej båden skal pege for at komme bedst frem ad et ben: lige, når det kan sejles, ellers krydsning op mod vinden eller bomning med vinden (I027).
- **Hvad det gør:** Ud fra benets retning og vinden prøver den kurser til begge sider og vælger den, der giver mest fremdrift mod benets ende (farten "made good"), med den samme sejlmodel som alt andet. Den siger, om det kan betale sig at krydse, hvor bredt bæltet om kurslinjen er (smallere, jo nærmere waypointet er), hvor mange vendinger et stræk tager, og hvordan der styres tilbage mod linjen bagefter.
- **Arbejder sammen med:** `VesselProfile` (sejlmodellen), `WindField`, `Simulation` (båden), ankomstestimatet og instrumenterne.
- **Holder styr på:** Intet; den regner kun.
- **Hvornår det kører:** Ved hvert tjek af sejlene under sejlads og i hvert ankomstestimat.
- **Hvis du ændrer det:** Hvordan bådene sejler op mod vinden, og hvor lang tid ture mod vinden tager.

### `src/sailing/propulsion_controller.gd`

**Formål:** Afgør automatisk, om båden sejler eller bruger motoren.
- **Hvad det gør:** Regner ud, hvor hurtigt båden kunne sejle i denne vind og kurs, tager et gennemsnit over omkring en spiltime og skifter til motor, når sejlads er for langsom (eller båden ligger i vindstille), og tilbage til sejl, når vinden er god igen. Minimumstider forhindrer, at den skifter frem og tilbage. En kursændring kan få den til at beslutte sig med det samme. I027: mens båden krydser op mod vinden, stoppes motoren, når sejlene på halsen klarer sig tydeligt bedre end tærsklen for at starte motoren (en båd på bidevind når aldrig sin fart på slør). I027 trin 2: uden brændstof forbliver motoren slukket, hvad reglerne end ville vælge.
- **Arbejder sammen med:** `PropulsionState` (dens hukommelse), `VesselProfile` (bådens tal), `WindField` (vinden), `SailTrim` (sejltrim gør kun sejlene hurtigere eller langsommere); kaldes af `Simulation`.
- **Holder styr på:** Intet selv; den returnerer en opdateret kopi af `PropulsionState`.
- **Hvornår det kører:** Ved hvert simulationstrin under sejlads.
- **Hvis du ændrer det:** Hvornår motoren starter og stopper, og bådens fart for sejl.

### `src/sailing/propulsion_state.gd`

**Formål:** Den gemte oversigt over, hvad der driver båden lige nu: sejl eller motor, fart og styringens hukommelse.
- **Hvad det gør:** Indeholder tilstanden (sejl eller motor), hvorfor motoren kører, det gennemsnitlige sejlpotentiale, timere, vind og kurs ved sidste tjek, og om spilakeren er sat. Det skriver HUD-linjen, fx "Under sail · broad reach · 6.8 kn", og kontrollerer gemte data ved indlæsning. I027: motoren kan også køre, fordi Kaptajnen valgte at gå for motor op mod vinden, og siger det.
- **Arbejder sammen med:** `PropulsionController` (opdaterer det), `SessionState` (gemmer det), `Simulation`, `GameSession`, `SaveManager`, HUD'en (skærmens informationsfelter), instrumenterne, `SailRig` og `WorldMap`.
- **Holder styr på:** Tilstand, motorårsag, farter, timere, kurs, vind og spilaker.
- **Hvornår det kører:** Hele tiden under sejlads; gemmes med spillet.
- **Hvis du ændrer det:** Gemte spil (felterne skal kunne læses) og hvad HUD'en siger om sejladsen.

### `src/sailing/sail_trim.gd`

**Formål:** Den lille færdighed i sejltrim: overlad det til besætningen, eller sæt skøderne selv.
- **Hvad det gør:** Regner den bedste skødeindstilling ud for vindens vinkel (stramt på kryds, slækket på læns, lidt fladere i hård vind). En god indstilling gør båden op til 6 % hurtigere, en dårlig op til 10 % langsommere. Det ændrer aldrig, om motoren kører. Det giver også feedback som "Well trimmed" eller "Too loose".
- **Arbejder sammen med:** `Simulation` og `PropulsionController` (bruger farten), `GameSession`/`SessionState` (gemmer indstillingen), panelet for sejltrim og instrumenterne.
- **Holder styr på:** Intet; kun regler.
- **Hvornår det kører:** Ved hvert sejladstrin, og når kaptajnen flytter trim-skyderen.
- **Hvis du ændrer det:** Hvor givende det er at trimme sejlene selv.

### `src/sailing/weather_damage.gd`

**Formål:** Regner ud, hvor meget hårdt vejr slider båden ned.
- **Hvad det gør:** Almindelig vind og frisk vind gør intet; over ca. 28 kn vind eller 45 kn vindstød mister båden tilstand, lidt i kuling og meget i storm. Det tjekker vejret én gang hvert spilminut, så resultatet er det samme ved enhver spilhastighed eller mens man sover. Hver båds robusthedsfaktor skalerer skaden.
- **Arbejder sammen med:** `WeatherModel` (vejret), `Simulation` (kalder det), `GameSession` (ejer bådens tilstand), `VesselProfile` (robusthedsfaktor).
- **Holder styr på:** Intet; kun reglerne.
- **Hvornår det kører:** Ved hvert simulationstrin under sejlads.
- **Hvis du ændrer det:** Hvor farlige storme er, og hvor ofte reparationer og redninger sker.

### `src/skills/timing_check.gd`

**Formål:** Den fælles timingskive: en nål kører rundt, og du trykker, mens den er inde i målbuen.
- **Hvad det gør:** Nålen kører altid med samme fart. Hvert godt tryk tæller; efter nok af dem lykkes det. En mindre "Perfect"-zone ligger inde i buen. Forbiere er tilladt op til en grænse (som standard tre), at lade være med at trykke koster intet, og et minut uden tryk afslutter det. Intet afhænger af held, bortset fra hvor målet dukker op, og det er bestemt af et fast startnummer (seed).
- **Arbejder sammen med:** `ReelTiming` (fiskeri), `MagicAnchorDeployment` (Magic Anchor), `ReelDial` (tegner den), fiskeri- og ankermenuerne.
- **Holder styr på:** Nålens position, målet, antal træffere, perfekte tryk og forbiere samt resultatet.
- **Hvornår det kører:** Mens en fisk hales ind, eller Magic Anchor sættes.
- **Hvis du ændrer det:** Fornemmelsen i både fiskeriets og Magic Anchors minispil.

## Brugerfladen: menuer, paneler og informationslinjen

### `src/ui/aboard_badge.gd`

**Formål:** De små lydløse statuslinjer på skærmen (HUD'en, spillets faste skærmvisning) under huebadget, så du aldrig er afhængig af at høre en lyd.
- **Hvad det gør:** Viser op til fire linjer: "Fish on! Reel in R" (pulserende), hvordan ankeret holder (eller et rødt "Anchor dragging!"), "Line out · trolling" (gul, når du sejler for hurtigt til at trolle) og "Well fed" efter et varmt måltid.
- **Arbejder sammen med:** `Hud` (som opretter det), `GameSession`, `AnchorSite`, `AnchorLife`, `FishingCatalog`, `UiTheme`.
- **Holder styr på:** Intet selv; det læser spillet igen hvert billede (frame) og gemmer intet.
- **Hvornår det kører:** Altid mens HUD'en er på skærmen, hvert billede.
- **Hvis du ændrer det:** Advarslerne på skærmen om bid, ankeret der slæber og trolling-fart ændres, og det betyder noget for spillere, der spiller uden lyd.

### `src/ui/academy_guide.gd`

**Formål:** Skipperskolen i spillet (I022): ét lille kort i nederste højre hjørne til den første sejlads og tipsene.
- **Hvad det gør:** Under den første sejlads viser den det aktuelle trin og krydser det af, når spilleren faktisk gør det (går, åbner hjulet og logbogen, går på dæk, åbner kortet, lægger en kurs, sætter sejl, lader tiden gå), altid med Spring over. Bagefter viser den korte tips første gang, noget sker (første gang undervejs, en havn, en vejradvarsel, et bid, trafik, kahytten ...), hver én gang, med Læs mere og Forstået. Kortet træder til side, når et vindue, en advarsel, en tidspassage eller rejsekortet er fremme, og ved kortet holder det sig fri af kortets knapper.
- **Arbejder sammen med:** `App` (vinduer, skærme og håndbogen), `Academy`, signaler fra `GameSession` og `Simulation`, `SettingsManager` (tips til eller fra), `HUD` (advarsler).
- **Holder styr på:** De ventende tips, det viste tip, om spilleren har gået.
- **Hvornår det kører:** Nogle gange i sekundet, mens spillet kører; ellers intet.
- **Hvis du ændrer det:** Hold reglen: aldrig over et vindue eller en advarsel, og altid til at lukke.

### `src/ui/action_wheel.gd`

**Formål:** Ringen af handlinger, der åbner med Q.
- **Hvad det gør:** Lægger de handlinger, der giver mening, hvor du er (ved roret, i kahytten, for anker, i havn), i en ring; piletaster eller A/D flytter rundt, E/Enter vælger, Q eller Esc lukker. Tænd/sluk-punkter viser et afkrydsningsfelt. I027: hjulet vokser med antallet af punkter (under sejlads kan det rumme et dusin), så ingen to nogensinde overlapper, og det bliver på skærmen ved alle grænsefladestørrelser.
- **Arbejder sammen med:** `App` (som giver listen fra `App.get_wheel_actions()`), `ModalPanel` / modal-stakken (stakken af åbne vinduer), `UiTheme`.
- **Holder styr på:** Kun listen af handlinger, den har fået, og hvilken der er valgt.
- **Hvornår det kører:** Når du trykker Q (eller åbner det) under spillet.
- **Hvis du ændrer det:** Hvordan spilleren når mange hverdagshandlinger; det tilføjer aldrig selv nye handlinger, det tilbyder kun eksisterende.

### `src/ui/adoption_dialog.gd`

**Formål:** Spørgsmålet ved nedgangen, når et dyr fra kajen har fulgt Kaptajnen hjem (I025, A Little More Room Aboard).
- **Hvad det gør:** Fortæller, at dyret har fulgt efter dig, og tilbyder "Adoptér" eller "Ikke nu". "Adoptér" beder om et navn, og om det er en hun eller en han (begge valgfrie, de samme valg som for ledsagerne fra I024), og "Velkommen om bord" bekræfter (Enter i navnefeltet gør det samme, og "Tilbage" går tilbage til spørgsmålet). "Ikke nu" lader det gå tilbage til kajen. Esc beslutter intet: under navngivningen går den tilbage til spørgsmålet, ved spørgsmålet lukker den, og dyret bliver ved med at følge efter, så et tastetryk ved et uheld aldrig sender det væk.
- **Arbejder sammen med:** `App` (spørger den, før man går ned, og handler på svaret), `CompanionRemarks` (spørgsmålets tekst), `CompanionState` (navnets længde, køn), `SimplePanel` (rammen), `Loc`.
- **Holder styr på:** Dyrets slags, navnet og kønnet der skrives, og om den allerede har svaret.
- **Hvornår det kører:** På dækket, når Kaptajnen vil ned, mens et dyr fra kajen følger efter.
- **Hvis du ændrer det:** Om og hvordan fundne dyr kommer om bord; ny tekst skal have en dansk oversættelse og passe på begge sprog.

### `src/ui/anchor_menu.gd`

**Formål:** Ankerpanelet ved ankerspillet på fordækket.
- **Hvad det gør:** Før du ankrer, vurderer det ankerpladsen her i denne vind og lader dig vælge, hvor meget kæde der skal ud (3, 5 eller 7 gange dybden); derefter sætter et lille timingspil ankeret. For anker viser det, hvordan ankeret holder, og lader dig ændre kæden, sætte det igen, kvittere for alarmen eller lette anker. Det styrer også Magic Anchor'ens timingskive.
- **Arbejder sammen med:** `GameSession`, `AnchorState`, `AnchorSite`, `DepthService`, `MagicAnchorDeployment`, `ReelDial`, `App` (bruger den tid, hvert arbejde tager), `AudioManager`, `SessionLog`.
- **Holder styr på:** Kun tilstanden af sættespillet og af et Magic Anchor-forsøg, mens panelet er åbent; selve ankeret ligger i `GameSession`.
- **Hvornår det kører:** Når du bruger ankerspillet (eller vælger ankeret på handlingshjulet).
- **Hvis du ændrer det:** Hvordan det føles at ankre, og hvor lang spiltid det tager; hvor godt ankeret holder, afhænger af, hvor godt du rammer "Set it now".

### `src/ui/anchorage_prompt.gd`

**Formål:** Spørgsmålet "We've arrived at our anchorage. Ready to drop anchor?", når båden når et ankerplads-rutepunkt på sin kurs.
- **Hvad det gør:** Giver tre valg: kast anker (åbner det almindelige ankerpanel), ikke endnu (båden venter) eller sejl videre ad kursen. Det ankrer aldrig af sig selv.
- **Arbejder sammen med:** `App` (viser det og håndterer valgene), `GameSession`, `AnchorMenu` (indirekte, via App).
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Én gang, når båden ankommer til et ankerplads-rutepunkt; ikke igen efter indlæsning af et spil.
- **Hvis du ændrer det:** Hvordan det føles at nå en planlagt ankerplads, og hvad kaptajnen får tilbudt der.

### `src/ui/boat_care_menu.gd`

**Formål:** Panelet "Boat care" på bådeværftet: reparationer, service, optagning og udstyr.
- **Hvad det gør:** Viser bådens stand og derefter kun det arbejde, dette værft kan udføre, hver med pris og tid (eller hvorfor det ikke kan lade sig gøre). Viser det udstyr, værftet kan montere; udstyr, der sælges over disken, hører i stedet til skibshandelen. Steady Hands: den monterede opgraderings navn vises på det valgte sprog.
- **Arbejder sammen med:** `BoatCareView`, `GameSession`, `BoatCare`, `HarbourFacilities`, `HarbourTrades`, `App` (bruger tiden i land og åbner optagningspanelet).
- **Holder styr på:** Intet selv; alle ændringer går gennem `GameSession`.
- **Hvornår det kører:** Når du vælger "Boat care…" på bådeværftet, mens du ligger fortøjet i havn.
- **Hvis du ændrer det:** Priser, ventetider og hvilket arbejde værfterne tilbyder; penge og bådens stand i gemte spil ændres kun af `GameSession`.

### `src/ui/boat_care_view.gd`

**Formål:** Bådens stand med ét blik: én række pr. plejeområde (skrog og bund, rigning og sejl, motor, udstyr).
- **Hvad det gør:** Viser hvert områdes niveau i ord og farve, en kort beskrivelse og, når det er vigtigt, hvad du kan gøre ved det.
- **Arbejder sammen med:** `BoatCareMenu` og `CaptainsLogMenu` (begge viser det), `GameSession`, `BoatCare`, `UiTheme`.
- **Holder styr på:** Intet selv; det læser kun spillet.
- **Hvornår det kører:** Når Boat care-panelet eller fanen "Boat" i Logbogen er åben.
- **Hvis du ændrer det:** Hvordan bådens slid vises, to steder på én gang.

### `src/ui/boatyard_menu.gd`

**Formål:** Bådeværftets vindue, hvor du ser bådene igennem og flytter om bord på en anden.
- **Hvad det gør:** Viser hver båd med et billede af dækket, dens data og en tabel, der sammenligner farten, og lader dig skifte båd (gratis; tid, havn, ledsager og fremskridt bevares). Det har også en knap til Boat care. Siden I026 har købmanden, skibshandelen og sejlmageren deres egne bygninger på kajen, så værftet har ikke længere knapper til dem. Siden I022 viser den hver båds pris, eller at den er din, og tilbyder at købe en båd, du ikke ejer endnu. Steady Hands: bådene, detaljerne og sammenligningen ruller, når skærmen er for lav (ved 130 % brugerflade var den højere end skærmen).
- **Arbejder sammen med:** `App`, `VesselCatalog`, `VesselDefinition`, `VesselVisual`, `GameSession`, `BoatCare`, `HarbourFacilities`, `ShopCounter` (dens ramme på kajen); layoutet kommer fra `boatyard_menu.tscn`.
- **Holder styr på:** Kun hvilken båd der er valgt i listen.
- **Hvornår det kører:** Når du bruger bådeværftets dør på kajen, mens du ligger fortøjet i havn (I026).
- **Hvis du ændrer det:** Hvordan både vælges og sammenlignes, og vejen til Boat care.

### `src/ui/build_label.gd`

**Formål:** Viser, hvilken version der kører, med lille skrift i vinduets nederste højre hjørne.
- **Hvad det gør:** Viser udviklingsversionens id ("BH · i024 · DEV" med den korte commit) fra `GameVersion` på sit eget lag over alle skærme, i grænsefladens størrelse; neutral grå med en blød kontur og uden panel; den reagerer ikke på mus eller tastatur. Laves ikke, når versionsmærket er slået fra (en offentlig eksport).
- **Arbejder sammen med:** `GameVersion`, `UiScaleLayer`, `App` (tilføjer den én gang).
- **Gemmer:** Intet.
- **Hvornår det kører:** Fra opstart til lukning, på alle skærme.

### `src/ui/cafe_menu.gd`

**Formål:** Caféens disk på kajen: bestil en kop kaffe og sæt dig med den på terrassen (I026).
- **Hvad det gør:** Viser prisen på en kop kaffe og dine penge og en knap til at bestille. En bestilling koster en lille pris, og Kaptajnen sætter sig ved et ledigt bord på terrassen med caféens krus; tiden går som sædvanlig, og E eller en bevægelsestast rejser Kaptajnen igen. Intet at tjene: ingen præstation, ingen energi, bare en kop kaffe ved vandet. Er alle borde optaget, siger den det, og intet betales.
- **Arbejder sammen med:** `App` (betaler gennem `GameSession` og sætter Kaptajnen ved bordet), `HarbourFront` (terrassen), `ShopCounter` (dens ramme), `GameSession` (prisen).
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Ved caféens dør på kajen, mens caféen har åbent.
- **Hvis du ændrer det:** Caféens disk; selve prisen ligger i `GameSession`.

### `src/ui/cabin_home_menu.gd`

**Formål:** "Make it home": vælg hvilke af dine ting til kahytten der vises om bord på denne båd.
- **Hvad det gør:** Viser kahyttens pynt; ting, du ejer, kan vises eller lægges væk og dukker straks op i kahytten ved siden af panelet (intet dæmpes). Ting, du endnu ikke har købt, fortæller, at de findes i skibshandelen. Steady Hands: panelets kolonne til højre er lige så bred som panelet faktisk er, så det aldrig er delvist uden for skærmen.
- **Arbejder sammen med:** `TradePanel` (det fælles butiksudseende), `HarbourTrades`, `GameSession`, `App` (åbner det fra handlingshjulet i kahytten), `CabinDecor` (indirekte; placerer tingene).
- **Holder styr på:** Intet selv; hver båds valg gemmes af `GameSession`.
- **Hvornår det kører:** I kahytten, fra handlingshjulet.
- **Hvis du ændrer det:** Hvordan kahyttens pynt vises; valgene er en del af det gemte spil.

### `src/ui/captains_log_menu.gd`

**Formål:** Logbogen (tryk L): din statistik, dit ry, sejladser, havne, mål og bådens stand.
- **Hvad det gør:** Fire faner: Log (statistik, ry, knappen "Publish travel update", seneste sejladser og mindeværdige øjeblikke), Harbours (havne grupperet efter land, med filtre), Objectives (åbne, gennemførte og hemmelige præstationer, som forbliver skjulte, til du finder dem) og Boat (stand og værftshistorik). I024: mål, der er taget ud af samlingen af bedrifter, tilbydes ikke længere, og en linje henviser til laptoppen, hvor bedrifterne er.
- **Arbejder sammen med:** `GameSession`, `CaptainsLog`, `PortCatalog`, `ObjectiveCatalog`, `VesselCatalog`, `BoatCareView`, `BoatCare`, `Simulation`, `App` (åbner den og udgivelsesvinduet).
- **Holder styr på:** Kun havnefilteret og hvilke lande der er foldet ud, så længe spillet kører (gemmes ikke).
- **Hvornår det kører:** Når du trykker L eller åbner den fra pausemenuen eller handlingshjulet.
- **Hvis du ændrer det:** Hvad spilleren ser af sine fremskridt; den ændrer aldrig selve spillet.

### `src/ui/catch_badge.gd`

**Formål:** Et lille mærke, der viser en fisks sjældenhed og størrelsesgrad.
- **Hvad det gør:** Viser sjældenhed som 1–4 udfyldte ruder med navnet ("Rare") og graden som en farvet medalje med navnet ("Silver"), så farve aldrig er det eneste fingerpeg. Skrald viser ingen af delene.
- **Arbejder sammen med:** `FishingCatalog`, og bruges af `FishingMenu` og `TrophyMenu`.
- **Holder styr på:** Kun den sjældenhed og grad, det viser lige nu.
- **Hvornår det kører:** Når fiskepanelet eller trofætavlen viser en fisk.
- **Hvis du ændrer det:** Udseendet af sjældenhed og medaljer ved fiskeri og på trofætavlen.

### `src/ui/chandlery_menu.gd`

**Formål:** Skibshandelen: butikken for bådudstyr, Magic Anchor, fiskeblink og ting til kahytten.
- **Hvad det gør:** Viser udstyr til båden (monteres én gang pr. båd), Magic Anchor (én gang, til alle både), blink og pynt til kahytten, hver med en prisknap. I026: en afdeling for elektronik sælger instrumentpakkerne (Modern Cruiser, Offshore Navigator), købt én gang og monteret med det samme i båden om bord; en pakke, du ejer, kan monteres igen her gratis, og den monterede er markeret. Et køb er alt eller intet og aldrig mere, end du har råd til.
- **Arbejder sammen med:** `TradePanel`, `GameSession`, `HarbourTrades`, `BoatCare`, `FishingCatalog`, `App` (bruger monteringstiden). I026: `InstrumentPackage`, `ShopCounter`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Når du bruger skibshandelens dør på kajen (I026), i havne der har en.
- **Hvis du ændrer det:** Hvad der kan købes, og til hvilken pris; købene havner i det gemte spil via `GameSession`.

### `src/ui/chart_plotter.gd`

**Formål:** Kortplotterens skærm: din båd, den nærmeste kyst, din kurs, næste sving og vinden.
- **Hvad det gør:** Tegner et kort med nord opad omkring båden med fire afstandsområder (5–80 sm) og bygger kystlinjen lidt ad gangen ud fra det samme vand/land-gitter, som ruteplanlæggeren bruger, dæmpet om natten. Siden I026 er den ikke længere et panel i HUD'en: den er skærmen i kortplotteren ved roret, vist forstørret i nærbilledet `PlotterView` (P, handlingshjulet eller selve plotteren ved roret), inde i den monterede instrumentpakkes hus. Den giver også næste sving, kurs, vind og afstandsområde i ord.
- **Arbejder sammen med:** `PlotterView` (rummer den), `App`, `GameSession`, `Simulation`, `SeaRouter` / `NavGrid`, `WorldMap`, `WindLayer`, `GeoMath`, `UiTheme` (natten). `TrafficModel` låner også to af dens små kortberegnings-hjælpere.
- **Holder styr på:** Hvilket afstandsområde der er valgt (kun for denne spilgang, gemmes ikke), samt et lille billede af kysten.
- **Hvornår det kører:** Kun mens den er på skærmen i plottervisningen.
- **Hvis du ændrer det:** Navigationshjælpen ved roret og muligvis billedhastigheden; ændrer du kortberegnings-hjælperne, påvirkes også de andre både i trafikken.

### `src/ui/confirm_dialog.gd`

**Formål:** Den generelle ja/nej-spørgeboks ("Overwrite?", "Load this game?").
- **Hvad det gør:** Viser en titel, en besked og to knapper, svarer præcis én gang og lukker. Esc tæller som "nej", og annuller-knappen får fokus først.
- **Arbejder sammen med:** `ModalStack` (som åbner den gennem `confirm()`), og bruges af `App`, `SettingsMenu` og `SaveLoadMenu`; layoutet kommer fra `confirm_dialog.tscn`.
- **Holder styr på:** Kun sine tekster, og om den har svaret.
- **Hvornår det kører:** Hver gang spillet beder dig bekræfte noget.
- **Hvis du ændrer det:** Alle bekræftelser i spillet, også ved indlæsning og overskrivning af gemte spil.

### `src/ui/cooking_menu.gd`

**Formål:** Kabyssen: vælg en ret og lav den, eller lav kaffe.
- **Hvad det gør:** Viser, hvad hver opskrift kræver (fisk fra køleboksen, dagligvarer), og hvad den giver (mad til forrådet, at være mæt), spiller en kort animation af panden eller kaffekanden og laver så maden. Komfuret virker i havn og for et anker, der holder, og under sejlads kun i moderat vejr. Steady Hands: opskriftens tekst og navn vises på det valgte sprog.
- **Arbejder sammen med:** `GameSession` (`cook()`, `make_coffee()`), `Recipes`, `Provisions`, `App` (bruger tilberedningstiden), `AudioManager`, `SessionLog`.
- **Holder styr på:** Kun animationstimerne og det seneste resultat, mens panelet er åbent.
- **Hvornår det kører:** Når du bruger komfuret i kabyssen.
- **Hvis du ændrer det:** Madlavning, proviant og bonussen for at være mæt; intet ændres, når en ret afvises.

### `src/ui/dev_guides_menu.gd`

**Formål:** En læser til udviklerguiderne (filerne i `DEV_GUIDES/`); ikke en del af selve spillet.
- **Hvad det gør:** Viser guiderne efter titel og den valgte som formateret tekst og bevarer din plads, når farvestemningen skifter.
- **Arbejder sammen med:** `DevGuides`, `MarkdownLite`, `UiTheme`, `App` (åbner den fra hovedmenuen); layoutet kommer fra `dev_guides_menu.tscn`.
- **Holder styr på:** Hvilken guide der er åben.
- **Hvornår det kører:** Kun i udviklerudgaver af spillet, fra hovedmenuen.
- **Hvis du ændrer det:** Kun hvordan udviklere læser guiderne; spillet påvirkes ikke.

### `src/ui/difficulty_menu.gd`

**Formål:** Pausemenuens dialog for sværhedsgrad (I022).
- **Hvad det gør:** Viser de tre niveauer med, hvad hvert ændrer, og en bemærkning om, at en ændring gælder fra nu af; Anvend sætter det nye niveau og siger det, Annuller lader det være.
- **Arbejder sammen med:** `DifficultyPicker`, `GameSession.set_difficulty`, `PauseMenu` (åbner den), `App`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Når "Sværhedsgrad…" vælges i pausemenuen.
- **Hvis du ændrer det:** Kun hvordan niveauet ændres undervejs i et spil.

### `src/ui/difficulty_picker.gd`

**Formål:** Tre knapper (Afslappet, Standard, Erfaren skipper) og en linje, der siger, hvad det valgte niveau ændrer (I022).
- **Hvad det gør:** Viser valget på det aktuelle sprog, husker det valgte niveau og melder ændringer.
- **Arbejder sammen med:** `Difficulty`, `NewGameMenu`, `DifficultyMenu`.
- **Holder styr på:** Det valgte niveau.
- **Hvornår det kører:** I menuen Nyt spil og i dialogen for sværhedsgrad.
- **Hvis du ændrer det:** Begge steder ændres.

### `src/ui/fishing_menu.gd`

**Formål:** Panelet for fiskestangen, med tre sider: stangen, indhalingen og fangsten.
- **Hvad det gør:** Ved stangen vælger du blink, sætter linen ud eller hiver den ind, venter på bid, vælger hvilke fisk du beholder og ser køleboksen (sæt fri eller sælg). Når en fisk bider, starter en indhaling med en timingskive; bagefter vises fangsten, dens vægt og grad, og om den blev beholdt. Steady Hands: blinknavne vises på det valgte sprog.
- **Arbejder sammen med:** `GameSession`, `FishingCatalog`, `FishingState`, `ReelTiming`, `ReelDial`, `FishPortrait`, `FishArt`, `CatchBadge`, `App` (bruger ventetiden), `AudioManager`, `SessionLog`.
- **Holder styr på:** Kun den igangværende indhaling og det seneste resultat, mens panelet er åbent; fangsten ligger i `GameSession`.
- **Hvornår det kører:** Når du bruger fiskestangen på hækrælingen (eller trykker R, når en fisk har bidt).
- **Hvis du ændrer det:** Hvor svært og hvordan fiskeri føles, reglerne for hvad du beholder, og køleboksen; fangsten gemmes via `GameSession`.

### `src/ui/fishmonger_menu.gd`

**Formål:** Fiskehandleren: stedet, hvor din fangst sælges.
- **Hvad det gør:** Viser hver fisk i køleboksen med sin pris, solgt én ad gangen eller alle på én gang. Trofæer og rekorder bliver i Logbogen.
- **Arbejder sammen med:** `TradePanel`, `GameSession`, `HarbourTrades`, `FishingCatalog`, `App`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Ved fiskehandlerens bod på kajen (I026; før fra købmandens knap), i havne der har en fiskehandler.
- **Hvis du ændrer det:** Hvor mange penge fiskeri giver, og hvordan det føles at sælge.

### `src/ui/fit_scroll.gd`

**Formål:** Et rulleområde, der holder et højt vindue på skærmen (Steady Hands).
- **Hvad det gør:** Er præcis så højt som sit indhold, når der er plads på skærmen, og kun så højt som skærmen tillader, når der ikke er, så indholdet ruller, mens vinduets titel og knapper bliver synlige. Bruges af Indstillinger og Bådeværftet, som var blevet højere end en skærm på 1080 linjer (Indstillingers titel og Anvend / Tilbage var skåret af).
- **Arbejder sammen med:** `SettingsMenu`, `BoatyardMenu`, `SettingsManager` (brugerfladens størrelse).
- **Holder styr på:** Vinduespanelet, den hører til.
- **Hvornår det kører:** Når vinduets størrelse, brugerfladens størrelse eller indholdet ændres; aldrig i hvert billede.
- **Hvis du ændrer det:** Hold titel og knapper uden for det; kun midten af et vindue skal rulle.

### `src/ui/focus_frame.gd`

**Formål:** Rammen, der får en menu til at ligne den genstand, den blev åbnet fra (I026).
- **Hvad det gør:** Når et vindue åbnes fra en fysisk genstand, tegner den genstandens materiale rundt om vinduets panel: en indbunden bogs stofbind og sider til logbogen, en radios grafitgrå ramme med et oplyst kanalvindue til VHF-radioen, lakeret teak til proviantskabet, trofætavlen, sømandskisten, postkortet og køjen, børstet stål til komfuret og en offwhite eltavle til systemvisningen. Panelet vokser kort frem. Selve vinduet er uændret; rammen tegner kun og tager aldrig musen eller tasterne.
- **Arbejder sammen med:** `App` (sætter den på), vinduerne af typen `ModalPanel`/`SimplePanel` (`CaptainsLogMenu`, `VhfSetView`, `SystemsView`, `ProvisionsMenu`, `CookingMenu`, `TrophyMenu`, `CabinHomeMenu`, `ScrapbookMenu`, `SleepMenu`), `CabinObject`.
- **Holder styr på:** Hvilket materiale den tegner.
- **Hvornår det kører:** Mens et vindue med ramme er åbent.
- **Hvis du ændrer det:** Hvordan nærbillederne ser ud; menuerne virker ens med og uden.

### `src/ui/game_dev_menu.gd`

**Formål:** En spiludvikler til søs: skipperens lille spil, åbnet fra kahyttens Q-hjul (I022).
- **Hvad det gør:** Viser spillets fremskridt mod næste milepæl og udviklerdagbogen med de nåede milepæle, lader spilleren vælge en opgave (hver viser sine 2 til 4 timer), svare på dens ene lille spørgsmål og begynde at arbejde; timerne vises før start. En afbrudt arbejdsøkt venter her med resten af tiden.
- **Arbejder sammen med:** `App` (bruger tiden og melder resultatet), `GameSession`, `Pastimes`.
- **Holder styr på:** Det valgte svar.
- **Hvornår det kører:** Mens dialogen er åben.
- **Hvis du ændrer det:** Hold det lille; svarene skifter rækkefølge, så det kloge ikke altid står først.

### `src/ui/go_ashore_menu.gd`

**Formål:** "Go Ashore": et lille øjeblik i havnen med et lille tegnet billede og et eller to valg.
- **Hvad det gør:** Viser havnens begivenhed (eller "en hyggelig gåtur", hvis du lige har været her), hvert valg med pris og tid, og fortæller bagefter, hvad der skete. Valg, du ikke har råd til, er gråtonede. Steady Hands: valgene og "gratis" vises på det valgte sprog.
- **Arbejder sammen med:** `GameSession`, `ShoreEvents`, `App` (afgør valget og bruger tiden i land).
- **Holder styr på:** Kun den begivenhed, der vises.
- **Hvornår det kører:** Når du går i land i en havn, der tilbyder det. Siden I026 fra stræden ind til byen ved kajens byende.
- **Hvis du ændrer det:** Begivenhederne i land, hvad de koster, og det ry og de mindeværdige øjeblikke, de kan give.

### `src/ui/grocery_menu.gd`

**Formål:** Havnens købmand: mad og vand, ekstra proviant til en Lang passage, en ny kaptajnshue og fiskeblink.
- **Hvad det gør:** Fylder mad og vand op til 14 dage hver i ét køb eller ud over det til en lang passage (op til hvad båden kan stuve). Sælger også en ny kaptajnshue og blink og fortæller, hvad din fangst er værd hos fiskehandlerens bod på kajen (I026: fiskehandleren har sin egen bod, så knappen dertil er væk). Steady Hands: blinknavne vises på det valgte sprog.
- **Arbejder sammen med:** `GameSession`, `Provisions`, `FishingCatalog`, `HarbourFacilities`, `App` (åbner den), `ShopCounter` (dens ramme på kajen).
- **Holder styr på:** Intet selv. Den opdaterer sig selv, når dine penge eller din fangst ændrer sig.
- **Hvornår det kører:** I havn, fra købmandens dør på kajen (I026) eller kahyttens proviantskab.
- **Hvis du ændrer det:** Prisen på proviant og hvor langt du kan sejle, før den slipper op; købene gemmes via `GameSession`.

### `src/ui/handbook_menu.gd`

**Formål:** Vinduet Skipperens håndbog (I022).
- **Hvad det gør:** Viser alle sider efter kapitel med et søgefelt, viser den valgte side med de rigtige taster udfyldt og tilbyder at begynde den første sejlads igen eller vise tipsene igen. Åbner med F1 eller fra pausemenuen, eller på en bestemt side fra et tips Læs mere.
- **Arbejder sammen med:** `Academy`, `App` (åbner den), `AcademyGuide` (Læs mere).
- **Holder styr på:** Den viste side og de viste sider på listen.
- **Hvornår det kører:** Mens den er åben.
- **Hvis du ændrer det:** Behold Luk-knappen; Esc og F1 lukker den også.

### `src/ui/harbour_moment.gd`

**Formål:** Det gyldne havneøjeblik: et lille illustreret rejseminde ved første ankomst til en havn, der har et billede.
- **Hvad det gør:** Viser et kort i beskedkolonnen med havnens eget billede sat ind i en himmel og et hav, der passer til tidspunktet. Om dagen er billedet, som det er tegnet; ved daggry er himlen bleg med lidt dis; i skumringen er himlen varm, billedets egne vinduer begynder at gløde, og lanterner står langs kajen; om natten er billedet dæmpet, og vinduerne er tændt. Under billedet står havnens navn, dens beskrivelse, linjen fra logbogen og et "Første besøg"-stempel ("Særlig havn" for havnene med deres egen tegning). Et klik lægger det væk, og det toner selv ud; det sætter aldrig spillet på pause og tager aldrig tastaturet. De tændte vinduer er maleriets egne mørke vinduesformer, fundet én gang pr. billede og husket.
- **Arbejder sammen med:** `App` (bestemmer, hvornår det vises), `Toasts` (viser det), `HarbourLooks` (billedet), `Daylight`, `BoatLighting` (overskyet), `WaterLook` (havets farve).
- **Holder styr på:** Havnen, solens højde og skydækket ved ankomsten; et lager af vinduespletter pr. billede.
- **Hvornår det kører:** Kun mens kortet er på skærmen; det tegnes én gang (og ved ændret størrelse), ikke i hvert billede.
- **Hvis du ændrer det:** Hold det stille og kort; at vende tilbage til en kendt havn skal stadig give det lille kort, og at indlæse et spil eller gå under dæk må ikke vise det.

### `src/ui/harbour_office_menu.gd`

**Formål:** Havnekontoret på kajen og dets luge uden for åbningstid (I026).
- **Hvad det gør:** Viser havnens størrelse og tilbud, åbningstiderne for alle forretninger på kajen, nogle få ord om stedet og vejrudsigten i ord. Uden for åbningstid viser lugen de samme oplysninger plus det nødvendige, der ikke kan vente til morgenen: mad og vand til båden (hvor havnen har en købmand) og en nødreparation af et beskadiget skrog (hvor den har et bådeværft; værftets egen reparation, med pris og tid som altid). Ingen strander på grund af uret. I027: et afsnit "Driftsomkostninger": havnepengene her, brændstof her og rækkevidden, og de sidste 30 dages udgifter.
- **Arbejder sammen med:** `HarbourNotes` (ordene), `QuayLayout`, `GameSession` (proviant, reparationstilbud), `BoatCare`, `HarbourFacilities`, `App` (udfører reparationen og lader tiden gå), `ShopCounter`.
- **Holder styr på:** Om det er lugen, og kajens layout.
- **Hvornår det kører:** Ved havnekontorets dør (i åbningstiden) eller ved lugen (når som helst).
- **Hvis du ændrer det:** Hvad kontoret fortæller, og hvad der stadig kan klares om natten.

### `src/ui/hat_badge.gd`

**Formål:** Et lille mærke i HUD'en (skærmoverlayet under spillet), der viser, når kaptajnshuen er i fare eller er blæst væk.
- **Hvad det gør:** Tjekker huen hvert billede. Er huen i fare på dækket, vises en blafrende hue, "Hold onto your hat!" og tasten H. Er huen tabt, vises en falmet hue med et spørgsmålstegn og "Hat missing". Ellers er mærket skjult. Det kan også pulsere et par sekunder lige efter, at huen er blæst væk.
- **Arbejder sammen med:** `GameSession` (huens status), `HatArt` (tegner huen), `UiTheme` (farver), `Hud` (opretter det), `App` (bruger dets visningstider og beder det pulsere).
- **Holder styr på:** Kun hvad det viser lige nu og en lille animationstimer. Intet gemmes.
- **Hvornår det kører:** Altid under spillet som en del af HUD'en (skjult på søkortet).
- **Hvis du ændrer det:** Advarslen om huen på skærmen ændres, og det samme gør visningstiden for huens beskeder (`WARNING_SECONDS`, `LOST_SECONDS`) og overskriften "Hat overboard!", som spillet og huetestene også bruger.

### `src/ui/haul_out_panel.gd`

**Formål:** Dialogen for optagning på et bådeværft: båden løftes op, bunden renses, og du kan vælge ekstra arbejde.
- **Hvad det gør:** Viser prisen for en optagning og afkrydsningsfelter til ekstra opgaver (service af motor eller rigning, når den er nødvendig, og hård bundmaling). Når du bekræfter, betales der via `GameSession.haul_out()`, en kort animation viser løft og skrubning, spillet bliver bedt om at bruge én dag, og til sidst står der, hvad der blev gjort, inklusive +2 ry for din første optagning. Steady Hands: opgraderingens navn vises på det valgte sprog.
- **Arbejder sammen med:** `GameSession`, `BoatCare`, `HaulOutScene` (billedet), `SessionLog`, `App` (åbner den og bruger dagen).
- **Holder styr på:** De valgte ekstraopgaver og resultatet af optagningen, mens dialogen er åben.
- **Hvornår det kører:** Når du vælger optagning på et værft, der kan løfte både.
- **Hvis du ændrer det:** Priser for bådpleje, tiden på land og Logbogens notat om optagninger kan blive påvirket.

### `src/ui/haul_out_scene.gd`

**Formål:** Den lille tegning af båden, der løftes op af vandet, i optagningsdialogen.
- **Hvad det gør:** Tegner himmel, vand, kajer og bådliften (kranen, der løfter både) i kode. Båden hæver sig med `lift`, og algerne på bunden forsvinder med `fouled`. Katamaraner tegnes som to skrog. Der drypper vand, mens hun kommer op.
- **Arbejder sammen med:** `HaulOutPanel`, som opretter og animerer den.
- **Holder styr på:** Hvor højt båden er løftet, hvor beskidt bunden er, og om det er en katamaran.
- **Hvornår det kører:** Kun mens optagningsdialogen er åben.
- **Hvis du ændrer det:** Kun udseendet af optagningsbilledet ændres. Spillet påvirkes ikke.

### `src/ui/hud.gd`

**Formål:** Det overlay, du ser under spillet: hvor du er, uret, ruten, instrumenterne og advarsler.
- **Hvad det gør:** Opdaterer sin tekst hvert billede ud fra spillet: område og havn, uret og PAUSED-mærket, den planlagte rute i havn, bådens tilstand, penge og proviant, og vinden. Det viser vejradvarsler og "tryk E"-beskeden, og det rummer huemærket, mærket for livet om bord, passagepanelet, bådens instrumenter og radaren. I026: under sejlads viser instrumenterne (`InstrumentCluster`, i den monterede pakkes udseende) fart, kurs, vind, ruten, distancen og ankomsttiden, så rutepanelet kun beholder sin Menu-knap, og intet vises to gange; de afløste sejlpanelet, og kortplotteren er nu et apparat ved roret i stedet for et HUD-panel. Et klik på instrumenterne åbner deres nærbillede. På kajen kalder det stedet "The quay". På søkortet viser det kun urbjælken. Steady Hands: højre kolonne (rutepanelet, instrumenterne, vejradvarslen) stables, så en advarsel aldrig flytter instrumenterne og får den højde, dens tekst kræver; rutepanelet bliver smallere i stedet for at gå ind under uret ved en stor brugerflade; prompten flytter til højre for radaren; "Moored at" / "Arrived at" oversættes. Advarselsboksen siger, hvad den advarer om: "Vejradvarsel" eller "Trafikadvarsel" for et skib på kollisionskurs.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `PortCatalog`, `HatBadge`, `AboardBadge`, `PassagePanel`, `InstrumentCluster`, `RadarPanel`, `App`.
- **Holder styr på:** Intet eget ud over et gemt tidsoverslag for ruten, og om det er i søkortstilstand.
- **Hvornår det kører:** Altid under spillet (en del af appens hovedscene).
- **Hvis du ændrer det:** Alt, hvad spilleren læser med et hurtigt blik, ændres. Flere andre paneler genbruger også dens vindtekst (`Hud.describe_wind`).

### `src/ui/instrument_cluster.gd`

**Formål:** Bådens instrumenter i HUD'en, i den monterede pakkes udseende (I026).
- **Hvad det gør:** Viser under sejlads, på dækket og i kahytten, fart, kurs, den sande vind og dens vinkel, ruten (destination, distance, ankomsttid), næste sving og, til ankers, ankeret: tre runde skiver og en LCD-repeater for Classic, tre displays hver på sin egen side for Modern Cruiser eller multifunktionsdisplayet i sin opstilling for Offshore Navigator, med en statuslinje under dem. Den afløste sejlpanelet og rutepanelets linjer om sejladsen. Den aflæser instrumenterne nogle gange i sekundet og tegner kun igen da. En ny kurs på mere end 5° giver kursen et enkelt, roligt lys (et enkelt blink med Reduce flashing slået til). Et klik på den (eller I eller handlingshjulet) åbner nærbilledet `InstrumentView`. I027: kursen lyser også kort op, når autopiloten vender eller drejer tilbage mod kurslinjen.
- **Arbejder sammen med:** `Hud` (rummer den og stabler den i højre kolonne), `InstrumentData`, `InstrumentPackage`, `InstrumentFace`, `GameSession` (den monterede pakke og siderne), `SettingsManager` (Reduce flashing), `App`.
- **Holder styr på:** Den seneste aflæsning, den kurs den sidst så, og lysets tilstand.
- **Hvornår det kører:** Under spillet, når båden sejler.
- **Hvis du ændrer det:** Den vigtigste information om sejladsen på skærmen.

### `src/ui/instrument_view.gd`

**Formål:** Instrumenterne tæt på, som de ser ud ved roret, med deres sider og valget af pakke (I026).
- **Hvad det gør:** Viser den monterede pakkes enheder forstørret på et stykke af cockpitskottet (lys gelcoat om dagen, dæmpet om natten): Classics tre skiver med repeateren, hvis knapper vælger rute, næste sving, vejr eller sejltrim; Modern Cruisers tre displays, hver med sine egne sideknapper; eller Offshore Navigators multifunktionsdisplay med knapper til opstillingerne (oversigt, sejlads, navigation, vejr). Under enhederne skriver den aflæsningerne i ord (vejrudsigten for næste strækning, trimmet, udsigten). En vælger viser de pakker, Kaptajnen ejer, og monterer straks den valgte i båden om bord; skibshandelen sælger de andre. Esc lukker. I027: en linje "Krydsning" viser fremdriften og næste vending, mens båden krydser.
- **Arbejder sammen med:** `InstrumentData`, `InstrumentPackage`, `InstrumentFace`, `GameSession` (montering og sider), `App` (åbner den med I, handlingshjulet, et klik på HUD'ens instrumenter eller på enhederne ved roret).
- **Holder styr på:** Classic-repeaterens side (for denne spilgang) og den seneste aflæsning.
- **Hvornår det kører:** Mens den er åben.
- **Hvis du ændrer det:** Hvordan spillerne aflæser og bladrer i instrumenterne; de valgte sider gemmes via `GameSession`.

### `src/ui/language_picker.gd`

**Formål:** Spørgsmålet ved første opstart: English eller Dansk?
- **Hvad det gør:** Viser en lille dialog på begge sprog med én knap pr. sprog. Når du vælger, gemmes valget i indstillingerne, og dialogen lukker. Esc gør ingenting, for du skal vælge.
- **Arbejder sammen med:** `SettingsManager`, `Loc` (listen over sprog), `App` (viser den én gang fra hovedmenuen).
- **Holder styr på:** Intet. Valget gemmes i indstillingsfilen, ikke i et gemt spil.
- **Hvornår det kører:** Kun første gang spillet starter, før der er valgt et sprog.
- **Hvis du ændrer det:** Oplevelsen ved første opstart ændres. En fejl her kan blokere hovedmenuen ved første opstart.

### `src/ui/laptop/laptop_view.gd`

**Formål:** Kaptajnens laptop, åbnet helt tæt på (I024): det ene hjem for ry og udgivelser.
- **Hvad det gør:** Dæmper kahytten og tegner den illustrerede laptop (låg, skærmkant, tastatur), så den fylder billedet; alt foregår på dens skærm. Fire apps i faner: Hjem (ry, fjernarbejde, det lille spil), Udgivelser (postkort, scrapbogen og rejseopdateringer), Bedrifter (samlingen efter kategori, de låste op først; låste mærker gjort grå af en lille shader, `greyed_badge.gdshader`, med en hængelås; hvornår, hvor og på hvilken båd) og Rejsehistorik (tal i alt, bedste time og bedste døgn for sejl, de seneste sejladser, tidligere hædersbevisninger). De eksisterende dialoger genbruges uændret og vises på skærmen (`SimplePanel.embedded`), så deres regler, tid og belønninger forbliver deres egne. Esc lukker en åben opgave og derefter laptoppen. I025: rejsehistorikken viser under "Om bord", hvem der sejler med: for hver ledsager hvor og hvornår den blev budt velkommen om bord (ud fra dens egne oplysninger), eller at den har været med fra start; overskriften vises kun, når en ledsager bor om bord.
- **Arbejder sammen med:** `App` (åbner den og gør det, der tager spiltid eller penge, når den beder om det), `AchievementCatalog`, `GameSession`, `CaptainsLog`, `ObjectiveCatalog`, `PostcardMenu`, `ScrapbookMenu`, `PublishMenu`, `WorkMenu`, `GameDevMenu`, `Loc`.
- **Holder styr på:** Kun den åbne app, den åbne opgave og den valgte kategori af bedrifter (gemmes ikke).
- **Hvornår det kører:** Når du bruger arbejdspladsen ved kahytsbordet eller vælger Laptop på handlingshjulet.
- **Hvis du ændrer det:** Hvor spillerne finder deres bedrifter, udgivelser og fjernarbejde; testene finder dens dele ved navn.

### `src/ui/loading_screen.gd`

**Formål:** Spillets egen indlæsningsskærm med logoet over et roligt hav.
- **Hvad det gør:** Viser logoet, en undertitel og en animeret scene (bølger, et fyrtårn med drejende lys, en vuggende sejlbåd), mens havnelisten, rutekortene (i en baggrundstråd, dvs. sideløbende arbejde) og bådkataloget indlæses. Den nævner hvert trin og glider derefter over i hovedmenuen. Siden I022 bruger den altid hovedmenuens dybe marineblå, så starten ligner den menu, den glider over i; Godots opstartsbillede før den er også marineblåt, med logoet i dets egen størrelse (skarpt, ikke strakt).
- **Arbejder sammen med:** `UiTheme` (dens natfarver, uanset tidspunktet), `PortCatalog`, `SeaRouter`, `VesselCatalog`, `App` (opretter den).
- **Holder styr på:** Hvilket trin den er nået til, og om den allerede er vist i denne kørsel.
- **Hvornår det kører:** Én gang pr. opstart, lige efter start (aldrig uden skærm, så aldrig i test).
- **Hvis du ændrer det:** Opstartstiden og spillets første indtryk ændres.

### `src/ui/main_menu.gd`

**Formål:** Titelskærmen.
- **Hvad det gør:** Viser knapperne (Nyt spil, Fortsæt, Indlæs, Indstillinger, Afslut samt udviklerguider og import, når de findes) og melder kun, hvilken du trykkede på. Fortsæt er kun aktiv, når der findes et gyldigt gemt spil, og viser pladsen, datoen og stedet for det.
- **Arbejder sammen med:** `SaveManager`, `SettingsManager`, `SaveLoadMenu` (datoformat), `GameVersion`, `LegacySaves`, `DevGuides`, `App` (gør det egentlige arbejde).
- **Holder styr på:** Intet eget.
- **Hvornår det kører:** Når spillet viser titelskærmen.
- **Hvis du ændrer det:** At starte, fortsætte og indlæse spil fra titelskærmen kan blive påvirket.

### `src/ui/markdown_lite.gd`

**Formål:** En lille hjælper, der laver Markdown-tekst om til formateret tekst, som Godot kan vise.
- **Hvad det gør:** Omsætter overskrifter, lister, fed, kursiv, kode, links, tabeller og streger til BBCode (Godots formateringskoder) til visningen af udviklerguiderne. Det er ikke en fuld Markdown-implementering.
- **Arbejder sammen med:** `DevGuidesMenu` (bruger den), `UiTheme` (farver til kode og links).
- **Holder styr på:** Intet; det er en ren hjælper.
- **Hvornår det kører:** Når udviklerguiderne åbnes (udviklingsbuilds).
- **Hvis du ændrer det:** Kun hvordan udviklerguiderne ser ud i spillet. Spillere ser det aldrig.

### `src/ui/modal_panel.gd`

**Formål:** Grundlaget for alle pop op-dialoger i spillet.
- **Hvad det gør:** Giver hver dialog en fælles måde at lukke på, reagere på Esc, vælge hvilken knap der får tastaturfokus, og bede spillet vise en kort besked.
- **Arbejder sammen med:** `ModalStack` (som viser dialogerne) og alle dialoger bygget på den (pausemenu, indstillinger, gemme/indlæse og mange flere).
- **Holder styr på:** Kun en henvisning til den stak, der holder den.
- **Hvornår det kører:** Når en dialog er åben.
- **Hvis du ændrer det:** Alle menuer og dialoger i spillet påvirkes.

### `src/ui/modal_stack.gd`

**Formål:** Holder styr på åbne dialoger, så kun den øverste vises, og Esc altid går ét skridt tilbage.
- **Hvad det gør:** Lægger nye dialoger øverst og skjuler den nedenunder. Når den øverste lukker, kommer den nedenunder frem igen med tastaturfokus. Den tilbyder også en færdig "Er du sikker?"-bekræftelse.
- **Arbejder sammen med:** `ModalPanel`, `ConfirmDialog`, `App` (sætter spillet på pause, mens en dialog er åben, og viser deres beskeder).
- **Holder styr på:** Listen over åbne dialoger.
- **Hvornår det kører:** Altid (en del af appens hovedscene).
- **Hvis du ændrer det:** Menunavigation, pause under menuer og bekræftelser overalt kan gå i stykker.

### `src/ui/new_game_menu.gd`

**Formål:** Dialogen til nyt spil: hvor tilgivende havet skal være, og så Start.
- **Hvad det gør:** Spørger om sværhedsgraden (Standard valgt på forhånd, siden I022) og melder Start med den. Siden I025 (A Little More Room Aboard) begynder et nyt spil uden ledsager: kun Kaptajnen, båden og havet. Dyr møder man undervejs (en lille kasse på en kaj), og de kan bydes velkommen om bord, så her er ingen ledsager at vælge, og intet andet i stedet.
- **Arbejder sammen med:** `DifficultyPicker`, `App` (starter spillet uden ledsager).
- **Holder styr på:** Kun valget af sværhedsgrad, indtil du trykker Start.
- **Hvornår det kører:** Når du trykker Nyt spil på titelskærmen.
- **Hvis du ændrer det:** Hvordan et nyt spil begynder; at tilbyde en ledsager ved start igen ville gå imod I025's idé.

### `src/ui/noticeboard_menu.gd`

**Formål:** Kajens opslagstavle, læst tæt på (I026).
- **Hvad det gør:** Viser vejrudsigten i ord, nogle få små opslag og havnens egne ord; åbningstiderne står på hver dør og på havnekontoret. Kun oplysninger: ingen opgaver, og vejr- og trafikadvarslerne kommer stadig som altid.
- **Arbejder sammen med:** `HarbourNotes`, `HarbourFront`, `App` (åbner den), `ShopCounter`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Når opslagstavlen ved gangbroen bruges.
- **Hvis du ændrer det:** Kun hvad opslagstavlen viser.

### `src/ui/passage_panel.gd`

**Formål:** Et kompakt panel på dækket under lange sejladser, med knapper til hurtig tid.
- **Hvad det gør:** Viser hvor båden er, dagen på havet, vejrudsigten langs ruten, om provianten rækker, og bådpleje der trænger. Knapperne lader tiden gå med 1, 4 eller 12 timer pr. sekund, åbner søkortet eller gemmer. Når hurtig tid stopper af sig selv, står der hvorfor (og hvor mange fisk der nappede imens). I026: farten og vinden står på instrumenterne ved siden af.
- **Arbejder sammen med:** `GameSession`, `Simulation` (passageuret), `Hud` (rummer det), `BoatCare`, `Provisions`, `VoyageMap` (genbruger dets knaptekster).
- **Holder styr på:** Kun gemt udsigtstekst og den seneste "stoppet"-besked.
- **Hvornår det kører:** Under sejlads på ture på 60 sm eller mere, når båden ikke ligger for anker.
- **Hvis du ændrer det:** Lang passage og dens knapper til hurtig tid påvirkes.

### `src/ui/pause_menu.gd`

**Formål:** Pausemenuen under spillet.
- **Hvad det gør:** Viser Genoptag, Logbogen, Gem, Indlæs, Indstillinger og Hovedmenu og melder kun, hvad der blev trykket på. I udviklingsbuilds tilføjer den en knap til "Developer tests". Siden I022 har den en knap til Sværhedsgrad…. I022: den har også Skipperens håndbog (F1).
- **Arbejder sammen med:** `App` (udfører valget), `DevTools`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Når du trykker Esc eller menuknappen under spillet.
- **Hvis du ændrer det:** At gemme, indlæse og forlade spillet kan blive påvirket.

### `src/ui/plotter_view.gd`

**Formål:** Kortplotteren ved roret, tæt på (I026).
- **Hvad det gør:** Viser plotterens skærm (kysten, kursen, næste sving og vinden, fra `ChartPlotter`) i den monterede pakkes hus, med knapper til afstandsområdet på rammen og en kolonne med data ved siden af kortet: fart, kurs, næste sving, vind og afstandsområde. Det er cockpittets plotter til sejladsen lige nu; kurser planlægges stadig ved kortbordet eller med Charts på handlingshjulet. Åbnes med P, handlingshjulet eller ved plotteren ved roret, om bord, i havn eller til søs; Esc lukker.
- **Arbejder sammen med:** `ChartPlotter` (skærmen), `InstrumentData`, `InstrumentPackage`, `InstrumentFace` (huset), `GameSession`, `App`.
- **Holder styr på:** Den seneste aflæsning; det valgte afstandsområde huskes af `ChartPlotter` for spilgangen.
- **Hvornår det kører:** Mens den er åben.
- **Hvis du ændrer det:** Plotteren tæt på; ruteplanlægningen påvirkes ikke.

### `src/ui/postcard_menu.gd`

**Formål:** Dialogen Postkort fra havet, åbnet fra kahyttens Q-hjul (I022).
- **Hvad det gør:** Lader spilleren vælge, hvad kortet viser, ordene og layoutet, viser kortet som det kommer til at se ud, og siger før start, at det tager omkring to timer spiltid at lave og udgive det, og om det giver ry. Et kort, der blev afbrudt undervejs, kommer tilbage som det var, med den resterende tid, og kan gøres færdigt eller smides ud. Den åbner også scrapbogen.
- **Arbejder sammen med:** `App` (bruger tiden), `GameSession` (kladden), `Pastimes`, `PostcardView`, `ScrapbookMenu`.
- **Holder styr på:** De tilbudte motiver og de valg, der er truffet.
- **Hvornår det kører:** Mens dialogen er åben.
- **Hvis du ændrer det:** Beskeden om de to timer skal være synlig, før spilleren starter.

### `src/ui/postcard_view.gd`

**Formål:** Tegner ét postkort: forhåndsvisningen mens man laver et, og hver side i scrapbogen (I022).
- **Hvad det gør:** Maler et papirkort i et af tre layouts (klassisk, øjebliksbillede, banner) med billedteksten og stedet, det blev sendt fra. Billedet bruger spillets egne tegninger: havnens vartegn, fisken, følgesvenden der hviler; til sejladser, vejr og aftenlys maler den et lille hav og en himmel med en sejlbåd.
- **Arbejder sammen med:** `PostcardMenu`, `ScrapbookMenu`, `Pastimes`, `HarbourLooks`, `FishArt`, `CompanionVisualSet`.
- **Holder styr på:** Kortet der vises, og dets billede.
- **Hvornår det kører:** Når et kort vælges, eller en side vendes.
- **Hvis du ændrer det:** Hold det til almindelig tegning (ingen shaders); ordene kommer fra `Pastimes`, så de forbliver oversat.

### `src/ui/provisions_menu.gd`

**Formål:** Proviantskabet: hvor meget mad og vand der er om bord, og hvor længe det rækker.
- **Hvad det gør:** Viser dage med mad og vand, deres niveau og den samlede rækkevidde, og forklarer, hvor man køber mere. I en havn med købmand er der en knap dertil.
- **Arbejder sammen med:** `GameSession`, `Provisions`, `HarbourFacilities`, `App` (åbner købmanden).
- **Holder styr på:** Intet; den læser spillet igen, mens den er åben.
- **Hvornår det kører:** Når du bruger proviantstationen i kahytten.
- **Hvis du ændrer det:** Hvordan spilleren ser og køber proviant.

### `src/ui/publish_menu.gd`

**Formål:** Dialogen til at offentliggøre en rejseopdatering online og gøre ry til penge.
- **Hvad det gør:** Viser dit ikke-offentliggjorte ry, satsen, indtjeningen og dine penge før og efter, og beder dig bekræfte. Selve handlen sker i `GameSession`.
- **Arbejder sammen med:** `GameSession`, `App` (offentliggør, når du bekræfter).
- **Holder styr på:** Intet.
- **Hvornår det kører:** Når du vælger "Publish travel update" i Logbogen eller ved arbejdsstationen.
- **Hvis du ændrer det:** Hvordan spilleren tjener penge på sit ry.

### `src/ui/radar_panel.gd`

**Formål:** En lille radarskærm på dækket, der viser andre skibe i nærheden.
- **Hvad det gør:** Tegner din båd i midten, afstandsringe og nærliggende skibe farvet efter fare, og skriver op til tre linjer om de vigtigste (hvor tæt de passerer, og hvad du skal gøre). Du kan zoome mellem 3, 6 og 12 sm. Den vises, når du tænder den, eller af sig selv, når et skib udgør en risiko under sejlads. Den vises kun under sejlads, hvor dens punkt i Q-menuen findes: tændt på havet forsvinder den ved fortøjning og kommer igen på næste sejlads. I026: den står alene i nederste venstre hjørne, da kortplotteren ikke længere er et HUD-panel.
- **Arbejder sammen med:** `Simulation` (trafikrisici), `GameSession`, `TrafficModel`, `Hud` (rummer den), `App` (handlingshjulet tænder den).
- **Holder styr på:** Om den er tændt, og zoomniveauet (kun for denne kørsel, ikke gemt).
- **Hvornår det kører:** Under spillet, på dækket. Den tjekker trafikken et par gange i sekundet.
- **Hvis du ændrer det:** Hvordan spillerne opdager skibe og undgår kollisioner.

### `src/ui/reel_dial.gd`

**Formål:** Den runde skive, du bruger, når du hiver en fisk ind (og ved det magiske anker).
- **Hvad det gør:** Tegner en ring med en grøn målbue, en mindre "perfekt" zone, en drejende viser, de klarede tjek og linens resterende greb. Den blinker efter hvert tryk, og et klik tæller som handlingstasten.
- **Arbejder sammen med:** `FishingMenu` og `AnchorMenu` (som opretter den), `ReelTiming`/`TimingCheck` (den timing, den tegner), `SettingsManager` (mindre blink).
- **Holder styr på:** Kun en kort blinktimer.
- **Hvornår det kører:** Mens et indhalings- eller magisk-anker-timingspil vises.
- **Hvis du ændrer det:** Udseendet og følelsen i fiskeminispillet.

### `src/ui/rescue_dialog.gd`

**Formål:** Fortæller, hvad der skete, efter din båd blev for skadet, og du blev reddet.
- **Hvad det gør:** Forklarer, at et redningshold slæbte jer tilbage, og viser hjemhavnen, redningsgebyret og de resterende penge. Selve redningen er allerede sket. I025: de sidste ord passer til, hvem der er om bord: din ledsager og dine forsyninger, dine ledsagere og dine forsyninger, eller kun dine forsyninger, når man sejler alene.
- **Arbejder sammen med:** `GameSession`, `PortCatalog`, `App` (viser den efter en redning).
- **Holder styr på:** De redningsoplysninger, den fik.
- **Hvornår det kører:** Lige efter en redning på havet.
- **Hvis du ændrer det:** Kun redningsbeskeden ændres.

### `src/ui/sail_trim_panel.gd`

**Formål:** Dialogen til sejltrim: slæk eller skød sejlene i med hånden, eller lad besætningen gøre det.
- **Hvad det gør:** Har en skyder fra Eased (slækket) til Sheeted in (skødet hjem), en skitse af båden set oppefra med vinden og bommen, og et ord om hvor godt sejlene er trimmet med virkningen på farten i procent. A/D ændrer trimmet, mellemrum overlader det til besætningen, T eller Esc lukker. Ændringer gælder med det samme.
- **Arbejder sammen med:** `GameSession` (gemmer trimmet), `SailTrim` (reglerne), `PropulsionState`, `UiTheme`, `App` (åbner den).
- **Holder styr på:** Intet eget; trimmet ligger i spillets tilstand.
- **Hvornår det kører:** Under sejlads, når du trykker T (ikke for anker).
- **Hvis du ændrer det:** Hvordan spillerne styrer sejlfarten.

### `src/ui/sailmaker_menu.gd`

**Formål:** Sejlmagerens butik (siden I026 sit eget sejlmagerloft på kajen, ved siden af bådeværftet).
- **Hvad det gør:** Tilbyder to ting: service af rigning og sejl (den samme som værftets, som får båden til at sejle bedre) og nye sejldugsfarver (kun udseende; de ændrer ikke farten). En dug, der allerede er købt til denne båd, kan sættes på igen gratis.
- **Arbejder sammen med:** `TradePanel` (dens layout), `GameSession`, `BoatCare`, `HarbourTrades`, `SessionLog`, `App` (åbner den og bruger tiden).
- **Holder styr på:** Intet eget.
- **Hvornår det kører:** Når du besøger sejlmageren i en havn, der har en.
- **Hvis du ændrer det:** Priser på rigningsservice og sejlfarver, som gemmes pr. båd.

### `src/ui/save_load_menu.gd`

**Formål:** Listen over pladser til at gemme eller indlæse et spil.
- **Hvad det gør:** Viser hver plads med dato, sted og rute. I gemmetilstand gemmer den på den valgte plads (og spørger, før den overskriver). I indlæsningstilstand melder den den valgte plads, så spillet kan indlæse den. Hurtiggemningen kan også indlæses her.
- **Arbejder sammen med:** `SaveManager`, `GameSession`, `ModalStack` (spørgsmålet om at overskrive), `App`, `MainMenu` (bruger dens datoformat).
- **Holder styr på:** Om den er i gemme- eller indlæsningstilstand.
- **Hvornår det kører:** Når du vælger Gem eller Indlæs i pausemenuen eller på titelskærmen.
- **Hvis du ændrer det:** At gemme og indlæse. En fejl her kan få en spiller til at miste sine fremskridt.

### `src/ui/scrapbook_menu.gd`

**Formål:** Scrapbogen med de postkort, der er lavet (I022).
- **Hvad det gør:** Viser kortene én side ad gangen, nyeste først, med hvornår hvert blev sendt; pileknapperne eller Venstre/Højre bladrer. Uden kort endnu fortæller den, hvordan man laver et. I026: den åbnes også fra det nyeste postkort, der står på salonbordet i kahytten, i en teakramme; uden kort henviser den til laptoppen i kahytten (Publications).
- **Arbejder sammen med:** `PostcardView`, `GameSession` (kortene), `PostcardMenu` (åbner den). I026: `CabinObject` (postkortet), `FocusFrame`.
- **Holder styr på:** Den viste side.
- **Hvornår det kører:** Mens den er åben.
- **Hvis du ændrer det:** Behold en Luk-knap; Esc lukker den altid også.

### `src/ui/settings_menu.gd`

**Formål:** Indstillingsdialogen, både fra titelskærmen og pausemenuen.
- **Hvad det gør:** Lader dig ændre lydstyrker (med testlyde), vinduestilstand, VSync, grænsefladens størrelse, grafikstil, sejlvisning, mindre blink, lynets lysstyrke, mindre bevægelse, grænsefladens dag/nat-lys og sprog. Ændringer ses med det samme; Apply gemmer dem, og forlader du uden at gemme, bliver du spurgt, før de fortrydes. Siden I022 har den en skyder for vind med sin egen testlyd (et par sekunders brise). I022: et Tips-afkrydsningsfelt slår Skipperskolens tips til eller fra. Steady Hands: lyd- og skærmafsnittene ruller, når skærmen er for lav, så titel, status og knapper altid er synlige.
- **Arbejder sammen med:** `SettingsManager`, `AudioManager`, `MusicDirector`, `SessionLog` (logmappen), `ModalStack`.
- **Holder styr på:** En kopi af de senest gemte indstillinger, så den kan se ikke-gemte ændringer.
- **Hvornår det kører:** Når du åbner indstillinger.
- **Hvis du ændrer det:** Alle spillerens indstillinger, som gemmes i indstillingsfilen.

### `src/ui/shop_counter.gd`

**Formål:** Butiksdisk-rammen: en forretnings menu vist, så den tydeligt hører til den butik (I026).
- **Hvad det gør:** Bag menuens panel tegner den butikkens indre: bagvæggen og hylderne med det, den sælger (tovværk og fendere i skibshandelen, ruller af sejldug hos sejlmageren, dåser og frugt hos købmanden, kasser på is hos fiskehandleren, kopper og kaffemaskinen på caféen, værktøj og en halvmodel på værftet, søkort og nøgler på havnekontoret), disken foran og butikkens eget skilt ovenover, i havnens egnsfarver. Menuens knapper, priser, fokus og Esc er nøjagtig som før. Kahyttens proviantskab, som også åbner købmanden, får ingen disk.
- **Arbejder sammen med:** `App` (sætter den på menuer åbnet fra kajen), `BoatyardMenu`, `BoatCareMenu`, `HaulOutPanel`, håndværkernes menuer, `GroceryMenu`, `CafeMenu`, `HarbourOfficeMenu`, `NoticeboardMenu`, `GoAshoreMenu`, `HarbourFront` (skiltenes navne), `HarbourDressing` (egnene).
- **Holder styr på:** Forretningen, egnen og skiltets tekst.
- **Hvornår det kører:** Mens en menu åbnet fra kajen er åben.
- **Hvis du ændrer det:** Hvordan butikkerne ser ud indvendig; butikkernes menuer røres ikke.

### `src/ui/simple_panel.gd`

**Formål:** Et byggesæt til enkle dialoger: en titel, noget tekst og en række knapper.
- **Hvad det gør:** Bygger i kode et centreret panel over en dæmpet baggrund og giver hurtige måder at tilføje tekster og knapper på. I024: den kan også vises indlejret på laptoppens skærm, uden baggrund og ramme.
- **Arbejder sammen med:** `ModalPanel` (bygger videre på den) og mange dialoger, der bruger den (arbejde, købmand, optagning, butikker, VHF-radio og andre) samt `LaptopView`, som viser nogle af dem på sin skærm.
- **Holder styr på:** Kun henvisninger til sin boks og sin knaprække.
- **Hvornår det kører:** Når en af de dialoger er åben.
- **Hvis du ændrer det:** Udseendet og layoutet af mange dialoger på én gang.

### `src/ui/sleep_menu.gd`

**Formål:** Dialogen, hvor du vælger, hvor længe du vil sove.
- **Hvad det gør:** Lader dig vælge 1 til 12 timer (knapper eller venstre/højre-tasterne), viser hvornår du vågner, og melder valget. Den husker den sidste varighed.
- **Arbejder sammen med:** `SettingsManager` (husker timerne), `GameSession`, `Simulation` (vågnetid), `App` (står for selve søvnen).
- **Holder styr på:** Det valgte antal timer.
- **Hvornår det kører:** Når du går til køjen eller vælger Sov fra søkortet.
- **Hvis du ændrer det:** Hvordan spillerne springer tid over ved at sove.

### `src/ui/systems_view.gd`

**Formål:** Bådens eltavle, tæt på: hvad båden faktisk holder øje med, samlet ét sted (I026).
- **Hvad det gør:** Viser skrogets stand og plejeoversigten for skrog, rig, motor og udstyr (de samme ord som i værftets gennemgang), hvad værftet har monteret, sejldugen, mad og vand om bord og de monterede instrumenter. Kun til at læse: intet her er en ny pligt eller en ny måler, og de tjenester, der ændrer tingene, er hvor de plejer (bådeværftet, sejlmageren, købmanden). Den er indrammet som en eltavle. I027: eltavlen viser brændstoffet, nu hvor spillet holder styr på det (stadig intet opfundet batteri).
- **Arbejder sammen med:** `CabinObject` (eltavlen), `App`, `FocusFrame`, `GameSession`, `BoatCare`, `HarbourTrades`, `InstrumentPackage`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Når eltavlen i kahytten bruges.
- **Hvis du ændrer det:** Kun hvad tavlen viser.

### `src/ui/theme/ui_theme.gd`

**Formål:** Spillets udseende for alle menuer og paneler, med en dagstemning og en natstemning.
- **Hvad det gør:** Bygger farver og former for knapper, paneler og tekst ud fra en palet (Real Horizon-marineelektronik: trækulsblå paneler, hvide tal, cyan accenter, rav til advarsler; et sollyst display om dagen, det samme dæmpet om natten). Det følger solen, der hvor båden er: dag indtil midten af aftenens tusmørke, nat indtil midten af morgenens, med et roligt skift på et par sekunder imellem (eller det bliver ved dag eller nat, hvis indstillingerne siger det). Det står ikke længere halvvejs gennem hele tusmørket, hvor tekst og panel blev samme grå, og tekstfarver blandes aldrig: de skifter midt i skiftet (Steady Hands). Andre skærme spørger det om farver.
- **Arbejder sammen med:** `SettingsManager` (grænsefladens lys), `GameSession`, `Daylight` og næsten alle skærme, der tegner deres egne billeder.
- **Holder styr på:** Den nuværende blanding af dag og nat og de temadele, det har bygget.
- **Hvornår det kører:** Altid (en autoload: et script Godot starter automatisk, og som altid findes).
- **Hvis du ændrer det:** Hele grænsefladens udseende ændres.

### `src/ui/time_controls.gd`

**Formål:** Knapperne Pause / 1× / 5× / 20× i urbjælken.
- **Hvad det gør:** Lader dig sætte tiden på pause eller skrue op for den, og holder knapperne i takt med spillets faktiske tilstand. Knapperne tager aldrig tastaturfokus, så de ikke forstyrrer bevægelsestasterne.
- **Arbejder sammen med:** `GameSession` (pause og tidshastighed), `SessionState` (listen over hastigheder), HUD-scenen (hvor de sidder).
- **Holder styr på:** Intet eget.
- **Hvornår det kører:** Altid under spillet, i HUD'ens urbjælke.
- **Hvis du ændrer det:** Hvordan spillerne styrer tidens gang.

### `src/ui/time_passage.gd`

**Formål:** Den blide overgang til mørke med datoen, når du sover, eller når daggry eller skumring går.
- **Hvad det gør:** Toner skærmen ned til mørkeblå, viser dato og ugedag (og ved søvn et ur, der tæller frem time for time), lader spillet gøre sit arbejde nedenunder og toner så op igen. Enhver tast eller klik springer frem.
- **Arbejder sammen med:** `App` (starter den ved søvn og nyt lys), `DayNightWatch`, `Loc` (datoord), `VoyageMap` (bruger dens farve).
- **Holder styr på:** Kun om den kører, og om du har sprunget frem.
- **Hvornår det kører:** Når du sover, eller daggry/skumring kommer, med en skærm. Den er slået fra i test.
- **Hvis du ændrer det:** Hvordan tidsspring føles. Selve spiltiden bestemmes andetsteds.

### `src/ui/toasts.gd`

**Formål:** De korte beskeder, der dukker op og forsvinder af sig selv.
- **Hvad det gør:** Viser en besked i et lille panel, højst tre ad gangen, og toner den ud efter et par sekunder. Det virker også, mens spillet er på pause, så menuer kan melde resultater. Siden I021 kan den også vise ankomstkortet: et billede af havnen med to linjer, som forsvinder af sig selv. Steady Hands / Golden Harbours: den viser også kortet med det gyldne havneøjeblik i et stykke tid (længere end en besked), før det toner ud.
- **Arbejder sammen med:** `App` (sender alle beskeder igennem den).
- **Holder styr på:** De beskeder, der er på skærmen lige nu.
- **Hvornår det kører:** Altid (en del af appens hovedscene).
- **Hvis du ændrer det:** Alle beskeder i spillet påvirkes. Mange test læser disse beskeder.

### `src/ui/trade_panel.gd`

**Formål:** Det fælles layout for havnens butikker.
- **Hvad det gør:** Bygger et butiksvindue med titel, en indledning, en rulleliste af rækker (navn, beskrivelse og en prisknap), dine penge og en Luk-knap. Det opdateres, når dine penge eller din båd ændrer sig.
- **Arbejder sammen med:** `SimplePanel`, `GameSession` og de butikker, der bygger på det: `ChandleryMenu` (skibshandel), `SailmakerMenu` (sejlmager), `FishmongerMenu` (fiskehandler), `CabinHomeMenu`.
- **Holder styr på:** Listen af rækker og deres knapper.
- **Hvornår det kører:** Mens en af de butikker er åben.
- **Hvis du ændrer det:** Alle havnens butikker ændres på én gang.

### `src/ui/trophy_menu.gd`

**Formål:** Trofætavlen: dine fem bedste fangster og din fiskerekord.
- **Hvad det gør:** Viser hver trofæfisk på en plade med billede, sjældenhed og kvalitet, og opgør totaler (fanget, genudsat, solgt, hajer sat fri, bedste pr. art).
- **Arbejder sammen med:** `GameSession` (fiskerekorden), `FishingCatalog`, `FishArt`, `CatchBadge`, `App` (åbner den).
- **Holder styr på:** Intet; den læser fiskerekorden.
- **Hvornår det kører:** Når du ser på trofætavlen i kahytten.
- **Hvis du ændrer det:** Kun hvordan trofæerne vises.

### `src/ui/ui_scale_layer.gd`

**Formål:** Får menuer og paneler til at følge indstillingen for grænsefladens størrelse.
- **Hvad det gør:** Skalerer sit lag og strækker sine direkte børn (elementerne lige under det), så de fylder skærmen i skalerede enheder, og layoutet stadig passer. Selve spilverdenen skaleres ikke.
- **Arbejder sammen med:** `SettingsManager`, appscenens HUD-, dialog- og beskedlag, verdenskortets scene og `MainMenu` (bygger på den).
- **Holder styr på:** Intet eget.
- **Hvornår det kører:** Altid, hvor sådan et lag bruges.
- **Hvis du ændrer det:** Størrelsen og pasformen af hele grænsefladen.

### `src/ui/vhf_dialog.gd`

**Formål:** Et opkald på VHF-radioen og dit svar.
- **Hvad det gør:** Viser hvad du hører på kanal 16, og hvad det kræver at svare, med Svar eller Afvis. Det er altid i orden at afvise. Svarer du på et kald om assistance, ligger båden standby et stykke tid.
- **Arbejder sammen med:** `VhfRadio` (tekster til opkaldet), `GameSession` (håndterer svaret), `App` (viser den og resultatet).
- **Holder styr på:** Det opkald, den viser.
- **Hvornår det kører:** Når et radioopkald kommer ind, og ingen anden dialog er åben.
- **Hvis du ændrer det:** Hvordan spillerne svarer på radioopkald.

### `src/ui/vhf_set_view.gd`

**Formål:** VHF-radioen ved navigationspladsen, tæt på (I026).
- **Hvad det gør:** Viser, hvad radioen faktisk har: kanal 16 på lytning; et opkald, der er kommet ind og ikke besvaret endnu, som kan besvares her med den samme dialog, som når det dukker op; og vejrmeldingen: vinden ved båden nu og, under sejlads med en kurs, de farer, vejrudsigten allerede ser forude. Advarslerne bliver i HUD'en og afhænger aldrig af, at radioen åbnes. Intet her er ny simulering, og intet gemmes. Den er indrammet som radioen.
- **Arbejder sammen med:** `CabinObject` (radioen og dens lampe), `App` (det ventende opkald, `VhfDialog`), `FocusFrame`, `VhfRadio`, `GameSession`, `Simulation`.
- **Holder styr på:** Det ventende opkald, hvis der er et.
- **Hvornår det kører:** Når VHF-radioen ved kortbordet bruges.
- **Hvis du ændrer det:** Hvad radioen viser; opkald giver stadig besked som før.

### `src/ui/voyage_map.gd`

**Formål:** Det illustrerede atlas, der vises under Lang passage i hurtig tid.
- **Hvad det gør:** Toner bådvisningen ud og viser et kort over sejladsen: ruten, båden, start og destination, dato, distance og forventet ankomst. Der er knapper til passagens hastigheder og "Take the helm" (tag roret). Når passagen stopper af sig selv, står der hvorfor, med valgene "Back aboard" eller "Sail on". Mens atlasset vises, er bådscenen og HUD'en skjult og sat på pause for at spare arbejde.
- **Arbejder sammen med:** `Simulation` (passageuret), `GameSession`, `CabinWorldMap` (landformer), `UiTheme`, `PassagePanel`, `TimePassage`, `App` (åbner det).
- **Holder styr på:** Ruten som tegnet, og hvad det har skjult.
- **Hvornår det kører:** Når en passage i hurtig tid starter under sejlads (med skærm, ikke i almindelige test).
- **Hvis du ændrer det:** Hvordan lange passager ser ud, og hvordan man kommer tilbage om bord.

### `src/ui/work_menu.gd`

**Formål:** Dialogen til fjernarbejde ved arbejdsstationen i kahytten.
- **Hvad det gør:** Lader dig vælge 1 til 8 timers arbejde, viser lønnen, sluttidspunktet og den mad og det vand, der bruges, og melder valget. Den tilbyder også "Publish travel update".
- **Arbejder sammen med:** `GameSession` (løn og grænser), `Simulation` (tidsformat), `Provisions`, `App` (står for selve arbejdet).
- **Holder styr på:** Det valgte antal timer.
- **Hvornår det kører:** Når du bruger arbejdsstationen, mens båden ligger i havn.
- **Hvis du ændrer det:** Hvordan spillerne tjener penge ved at arbejde.

## Automatiske testsuiter

### `tests/career/career_sim.gd`

**Formål:** Spiller hurtige karrierer efter spillets rigtige regler for at måle økonomien (karrieretest, metode A; I027).
- **Hvad det gør:** Starter et nyt spil på et frø og spiller det efter en enkel strategi (sparsom, krydstogtsejler, arbejder): fjernarbejde, proviant og brændstof i havn, nætter ved kaj, rigtige rejser mellem rigtige havne i det rigtige vejr. Skriver hver karrieres regnskab og daglige øjebliksbilleder som JSON og en samlet CSV. Den holder tre ure adskilt: hvor lang tid kørslen tog, hvor meget spiltid der gik, og et skøn (tydeligt mærket) over en spillers aktive tid. Den giver aldrig penge, rejser eller udmærkelser, som spillet ikke ville give.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `PortCatalog`, `CareerLedger`.
- **Holder styr på:** Intet; den skriver rapportfiler (kun testgemmer).
- **Hvornår det kører:** Kun i hånden: `res://tests/career/career_sim.tscn -- [--out=DIR] [--seeds=1,2] [--days=60] [--policies=frugal] [--level=standard]`.
- **Hvis du ændrer det:** Kun rapporterne.

### `tests/screenshots_horizon.gd`

**Formål:** Tager Real Horizon-skærmbillederne fra det kørende spil.
- **Hvad det gør:** Starter et spil og tager titelbilledet, havnen, kahytten dag og nat, søkortet, sejlads i let luft, frisk brise og kuling, skumring og nat, sejltrim og en ankomst til Kiel; eventuelt for én båd (`--vessel=`) eller nogle billeder (`--only=`).
- **Arbejder sammen med:** `App`, `GameSession`, `Simulation`, `WindField`, `WeatherFixtures`, `SeaSurface`.
- **Holder styr på:** Intet mellem kørsler; bruger testens gemte spil og indstillinger.
- **Hvornår det kører:** Kun når det køres i hånden (se scriptets hoved).
- **Hvis du ændrer det:** Kun skærmbillederne.

### `tests/suites/test_academy.gd`

**Formål:** Tester Skipperskolen (I022).
- **Hvad det gør:** Tester håndbogens data (hver side i et kapitel, alle henvisninger gyldige, alle taster rigtige bindinger, ingen tastebogstaver skrevet i teksterne, alt på dansk), søgning på engelsk og dansk, fremskridtet i indstillingerne, tilbuddet ved første nye spil (kan lukkes, spørges én gang, aldrig ved et indlæst spil), den første sejlads krydset af ved rigtige handlinger, tipsene (aldrig over et vindue eller en advarsel, én gang, slået fra i Indstillinger, Læs mere) og håndbogen (F1, pausemenuen, søgning, begynd den første sejlads igen).
- **Arbejder sammen med:** `Academy`, `AcademyGuide`, `HandbookMenu`, `App`, `SettingsManager`.
- **Holder styr på:** Intet (den nulstiller Skipperskolens fremskridt bagefter).
- **Hvornår det kører:** Sammen med de andre testsæt (`test_runner.tscn`).
- **Hvis du ændrer det:** Kun testene ændres.

### `tests/suites/test_anchor_life.gd`

**Formål:** Tjekker, at en stille aften for anker føles hyggelig, og at morgenkaffen virker (revision 0.102b).
- **Hvad det gør:** Starter det rigtige spil og laver kaffe i havn (ingen belønning). Derefter sejler den fra København mod Malmø og ankrer. Så tjekker den, at båden "falder til ro": ledsageren tager en lur, der kommer én stille besked, aftenlyset bliver varmt, og lampen tændes i kahytten. Den tjekker også at vågne for anker, at morgenkaffen giver et Logbogen-øjeblik (+2 ry) kun én gang, at gemme/indlæse ikke gentager noget, og at en frisk vind gør en ende på hyggen. I025: den finder kahyttens første ledsager ved nodens navn, `Companion` (en kahyt har nu også en node til en anden).
- **Arbejder sammen med:** `GameSession`, `Simulation`, `AnchorLife`, `CookingMenu`, `ShipCompanion`, `SaveManager` og app-scenen.
- **Holder styr på:** Intet af sit eget; den samler bare de ankerbeskeder, den ser under testen.
- **Hvornår det kører:** Kun i test (testkøreren).
- **Hvis du ændrer det:** Kun de automatiske tjek ændrer sig. Fejler et tjek her, så kig på livet for anker, kaffen eller ledsagerens lur. Den tager også skærmbilleder med navnene `0102b_*`.

### `tests/suites/test_anchorage.gd`

**Formål:** Tjekker ankerplads-rutepunkter: at markere et stop på søkortet, hvor båden skal ankre (Iteration 18).
- **Hvad det gør:** På søkortet markerer den et rutepunkt som ankerplads (knap eller M). Steder på land eller i for dybt vand bliver afvist med en forklaring, og et sted i nærheden bliver foreslået i stedet. Den sejler derhen med Lang passage og tjekker, at båden stopper og spørger "Ready to drop anchor?" én gang, og derefter ankrer eller sejler videre. Den tjekker også gemme/indlæse, kursskift på havet, datolinjen og gamle gemte spil. I026: mens båden venter ved ankerpladsen, siger instrumenterne det ("waiting at the anchorage" og hvordan man sejler videre).
- **Arbejder sammen med:** `WorldMap`, `GameSession`, `Simulation`, `SeaRouter`, `AnchoragePrompt`, `PlannedRoute`, `SaveManager`.
- **Holder styr på:** Intet af sit eget; den husker bare den valgte ankerplads.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl her peger på ankerplads-rutepunkterne, spørgsmålet ved ankomst eller måden ruter gemmes på.

### `tests/suites/test_anchorage_overlay.gd`

**Formål:** Tjekker søkortets farvede ankerzoner: blågrøn til det almindelige anker, ravgul til det magiske anker (Magic Anchor) (revision 0.105b).
- **Hvad det gør:** Den tjekker, at intet bliver regnet ud, når hele verden er vist. Når man zoomer ind på Antigua, bliver kun de synlige felter regnet ud, inden for et lille tidsbudget pr. billede, og de bliver gemt til senere. Farverne skal passe med reglen for at ankre, datolinjen ved Fiji skal virke, og når musen holdes over et sted, skal det forklares. Den tjekker også rutepunkter i blågrønne og ravgule zoner (med og uden det magiske anker), og rutepunkter der trækkes ind på land.
- **Arbejder sammen med:** `WorldMap`, `MapView`, `AnchorageLayer`, `CoastalGeography`, `GameSession`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Nogle tjek måler hastighed, så en langsom computer kan få dem til at fejle. Skærmbillederne hedder `rb_*`.

### `tests/suites/test_atmosphere.gd`

**Formål:** Tjekker det vejr, man hører og ser om bord: vind, vand, regn, lyn og torden (Iteration 17).
- **Hvad det gør:** Den tjekker, at lydfilerne findes og fortæller, hvor de kommer fra, og at lydkanalerne er sat rigtigt op. Regnen skal passe til vejret, en kuling skal lyde kraftigere, og lyden skal være dæmpet i kahytten. Lyn skal blinke (mildere med tilgængeligheds-indstillingerne), og torden skal komme senere fra fjerne uvejr. På dækket tjekker den vindstriber og regndråber. Siden I022 tjekker den, at vinden spiller på sin egen Wind-kanal, som føder den dæmpede Outside-kanal.
- **Arbejder sammen med:** `WeatherAudio`, `AudioManager`, `WeatherFixtures` (opdigtet testvejr), `WeatherVisuals`, `SettingsManager` og app-scenen.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på vejrlyden, lynene eller vejreffekterne på dækket.

### `tests/suites/test_boat_care.gd`

**Formål:** Tjekker vedligehold af båden: langsom slitage, bådeværftets ydelser, optagning, udstyr og Passage Readiness (om båden er klar til turen) (Iteration 14).
- **Hvad det gør:** Den tjekker, at der gror ukrudt på skroget dag for dag, at rigningen slides med sømilene, og at motoren tæller sine timer, altid forudsigeligt. Værfterne tilbyder kun det arbejde, de kan udføre, og prisen stiger med skaden og bådens størrelse. Nyt udstyr har en rigtig virkning, men gør aldrig båden hurtigere. "Klar til turen" er kun et råd. Den indlæser også et gammelt gemt spil (format 11) og klikker sig gennem panelerne for vedligehold, optagning og Logbogen. I026: i Stege, en lille havn, går den op på kajen og tjekker, at der hverken er en værftsbygning eller en bådlift.
- **Arbejder sammen med:** `BoatCare`, `GameSession`, `PassageReadiness`, `DevTools`, `BoatCareMenu`, `HaulOutPanel`, `CaptainsLogMenu`, `SaveManager`. I026: `HarbourFront`, `QuayLayout`, kaj-hjælperen.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på slitagen, værftspriserne eller indlæsning af gamle gemte spil. Skærmbillederne hedder `14_*`.

### `tests/suites/test_boat_of_your_own.gd`

**Formål:** Tjekker havnens forretninger, og at man kan gøre båden til sin egen (I020).
- **Hvad det gør:** Den tjekker, hvilke havne der har fiskehandler, skibshandel eller sejlmager. Den sælger fisk (aldrig to gange, og købmanden nedenunder viser straks de nye penge), køber udstyr og ting til kahytten (aldrig så pengene går under nul) og bestiller sejl i en ny farve (kun udseendet ændres). Ting til kahytten bliver stillet ind på alle fire både uden at spærre for noget. Den tjekker også, at gamle og mærkelige gemte spil kan indlæses, og at de danske tekster kan være på skærmen. Siden I021 accepterer den, at en lang butiksliste ruller: en række, der er rullet ud af syne, tæller ikke som uden for skærmen. Siden Operation Paperwork tjekker den også, at messingkompasset hænger i hver kahyt og hedder "Kompas i messing" på dansk.
- **Arbejder sammen med:** `HarbourFacilities`, `HarbourTrades`, `TradePanel`, `GameSession`, `CabinDecor`, `SessionState`, `SettingsManager`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på butikkerne, pengene, sejlfarverne eller pynten i kahytten.

### `tests/suites/test_branding.gd`

**Formål:** Tjekker spillets navn, versionsnummer, skrifttyper, mappen til gemte spil og kopiering af gamle gemte spil fra Next Harbor.
- **Hvad det gør:** Den tjekker, at spillet hedder "Little Captain's Hat", at versionen er 0.113a overalt, og at logo- og ikonfilerne findes. Den tjekker, at gemte spil ligger i spillets egen mappe, og at den kondenserede skrifttype Patrick Hand kun bruges til overskrifter (Barlow til alt andet). Den tjekker også, at gamle gemte spil fra Next Harbor bliver kopieret (aldrig flyttet eller overskrevet) over i ledige pladser, også via importknappen i hovedmenuen.
- **Arbejder sammen med:** `GameVersion`, `SaveManager`, `LegacySaves`, `MainMenu`, `ConfirmDialog`, `CaptainsLogMenu`, `Hud`, `SettingsManager`.
- **Holder styr på:** Intet af sit eget (den laver en midlertidig, opdigtet Next Harbor-mappe og fjerner den igen).
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Den tjekker den nøjagtige version ("0.113a", "0.113.1") og gemmeformat 12, så en ny udgivelse betyder, at denne test skal rettes.

### `tests/suites/test_build_label.gd`

**Formål:** Tjekker udviklingsversionens id.
- **Hvad det gør:** Tjekker mærkets form, og at dets iteration passer til den nyeste iterationsrapport i denne checkout (eller den næste), stadie-endelsen, at der er præcis ét mærke gennem menu, spil, dæk og kahyt, søkort og pause, dets plads i hjørnet ved flere grænsefladestørrelser og (renderet) efter at vinduet ændrer størrelse, at det ikke tager imod input, og at indstillingen for offentlige udgaver skjuler det.
- **Arbejder sammen med:** app-scenen, `GameVersion`, `BuildLabel`, `SettingsManager`.
- **Gemmer:** Intet (sætter grænsefladestørrelsen og indstillingen tilbage).
- **Hvornår det kører:** I testkøreren, før `test_gameplay_flow`.

### `tests/suites/test_cabin_objects.gd`

**Formål:** Tester de ting, en sejler bruger under dæk, og skødespillet på dækket (I026).
- **Hvad det gør:** På hver båd tester den, at kahytten har logbogen og VHF-radioen ved navigationspladsen, eltavlen, sømandskisten ved køjen og, når der er lavet et postkort, postkortet på salonbordet, hver med en fri plads ved siden af, hvor E vælger den. Hver åbner sit nærbillede indrammet som genstanden og lukker med Esc; vinduerne for proviantskabet, komfuret, trofætavlen og køjen har også ramme. VHF-lampen blinker, mens et opkald venter, og opkaldet besvares fra radioen; eltavlen viser kun, hvad spillet holder styr på. Skødespillet står på alle dæk og åbner sejltrimmet under sejlads. Den tester også, at hver indrammet visning passer på skærmen ved 1280×720 og 1024×768, ved 100 % og 130 %, på engelsk og dansk, og at advarselsboksen kalder en trafikalarm for en trafikadvarsel. I027: eltavlen viser nu brændstof (simuleret) og stadig intet batteri.
- **Arbejder sammen med:** `CabinObject`, `WinchProp`, `FocusFrame`, `VhfSetView`, `SystemsView`, `ScrapbookMenu`, `SailTrimPanel`, `BoatArea`, `GameSession`, hjælperen til gangbarhed, app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; flyttes møbler i kahytten eller genstandenes visninger, kan den fejle.

### `tests/suites/test_cabin_windows.gd`

**Formål:** Tjekker kahytsvinduerne og det blødere vand (I022; hver kahyt og det falmede hav udenfor siden I025).
- **Hvad det gør:** Tjekker, at hver vinduesåbning ligger inde i kahyttens vægtegning på alle fire både (hver med vinduer i begge sider; Clam 40's salon med sine fire store vinduer, der ser fremad), at vinduerne ligger over væggene og under møblerne, og at de siden Kaptajnens ændring af I025 er almindeligt glas: ingen udsigt til verden udenfor, ingen anden scene bag dem, lysere glas om dagen og mørkt glas om natten, aldrig tegnet om, mens skipperen går rundt, og billige at tegne. Den tjekker også, at den klassiske tegning skjuler vinduerne, at bagbords- og styrbordsvinduer vender hver sin vej i hver kahyt, det falmede hav omkring skroget (under al kahytstegning, svagt, mørkere om natten, ikke oplyst af lamperne, ikke under gulvet, pontonen kun ved fortøjning, aldrig på et dæk), og det blødere vand på dækket.
- **Arbejder sammen med:** `CabinWindows`, `CabinSeaBackdrop`, `WaterLook`, `BoatArea`, `App`.
- **Holder styr på:** Intet; den sætter vand- og tegningsindstillingerne tilbage.
- **Hvornår det kører:** I testkøreren; med skærmbilleder viser den hver kahyts glas om dagen og om natten og hver båds kahyt.
- **Hvis du ændrer det:** Flyttes et vindue, skal kahyttens fordybning males igen; hjørnetesten siger det.

### `tests/suites/test_captains_log.gd`

**Formål:** Tjekker Logbogens statistik og dens panel (Iteration 006).
- **Hvad det gør:** Den tjekker besøgte havne, sejlet distance og optegnelser over sejladser ved ankomst, kursskift og redning. Sømilene skal blive de samme, uanset om tiden går i ét stort spring eller i mange små, kun de nyeste sejladser bliver gemt, og gemme/indlæse og meget gamle gemte spil (version 7) skal virke. Bagefter åbner den Logbogen med L, prøver fanerne og havnefiltrene og åbner den fra pausemenuen. Golden Harbours: linjen om første besøg kan være en del af kortet med havneøjeblikket; den skal vises præcis én gang.
- **Arbejder sammen med:** `GameSession`, `CaptainsLog`, `Simulation`, `SaveManager`, `CaptainsLogMenu`, `WeatherFixtures`.
- **Holder styr på:** Intet af sit eget; den noterer de "sejlads logget"-beskeder, den hører.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på tallene i Logbogen eller på, hvordan de bliver gemt.

### `tests/suites/test_captains_other_life.gd`

**Formål:** Tjekker I022, Kaptajnens andet liv.
- **Hvad det gør:** Tjekker bådpriser, at et nyt spil kun ejer startbåden, køb af en båd (aldrig to gange, aldrig under nul kroner, kun på et værft), at gamle gemte spil beholder alle både, de tre sværhedsgrader (startpenge, mad, udgifter, danske navne), ændring af niveauet undervejs og menuerne Nyt spil og pause, der tilbyder det. I022 fritidssysler: postkort (rigtige motiver, to timer, bevares ved afbrydelse, ry én gang), det lille spil (økter på 2 til 4 timer, point for den del der er arbejdet, milepæle, udgivelse, ingen gentagne belønninger), gemte og gamle spil, det ene ur gennem App (to timer af verden går, en ankomst afbryder et kort, som gøres færdigt senere) og menuerne. I024: kahyttens hjul tilbyder laptoppen, hvor begge fritidssysler nu er.
- **Arbejder sammen med:** `GameSession`, `SessionState`, `VesselCatalog`, `Difficulty`, `NewGameMenu`, `DifficultyMenu`, `App`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Sammen med de andre testsæt (`test_runner.tscn`).
- **Hvis du ændrer det:** Kun testene ændres.

### `tests/suites/test_captains_watch.gd`

**Formål:** Tjekker Kaptajnens vagt: skibstrafik, radar, kollisionsadvarsler, ankeralarmer og opkald på VHF-radioen (I019).
- **Hvad det gør:** Den tjekker, at andre skibe altid er de samme steder på samme tidspunkt, holder sig på vandet og ikke er for mange. Den tjekker regnestykket for, hvor tæt skibene kommer på hinanden, og at kollisionsadvarsler kommer i god tid, én gang pr. skib, og vækker dig eller stopper Lang passage. Den tjekker også ankeralarmens niveauer og VHF-opkald: et svar belønnes kun én gang, også efter gemme/indlæse. Den tjekker også, at radaren, tændt på havet, forsvinder ved fortøjning og kommer igen på næste sejlads.
- **Arbejder sammen med:** `TrafficModel`, `Simulation`, `GameSession`, `RadarPanel`, `VhfRadio`, `AnchorState`, `SeaRouter`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test. Det er en af kun to testsamlinger, hvor møder på havet er slået til.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på trafikken, advarslerne eller radioopkaldene.

### `tests/suites/test_catamaran_cabin.gd`

**Formål:** Tjekker kahytten i katamaranen Halcyon 40 (Iteration 004b).
- **Hvad det gør:** Den tjekker salondøren ud til dækket og teksten, der dukker op ved den, og at tegningen af møblerne passer med, hvor man støder ind i dem. Den tjekker, at køjerne har en fornuftig størrelse, og at spilleren kan gå ind i begge skrog (ved rigtigt at trykke på bevægelsestasterne). Den tjekker også, at navigationsbordet åbner søkortet, at man vågner ved køjen efter at have sovet, og at man kan nå ledsagerens pladser.
- **Arbejder sammen med:** app-scenen, `BoatArea`, `BoatFixture`, testhjælperen til gang-områder, `SleepMenu`, `ShipCompanion`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Flytter du møbler eller døre i katamaranens kahyt, kan den fejle.

### `tests/suites/test_catch_and_cove_journey.gd`

**Formål:** Spiller en hel "Catch & Cove"-dag igennem, som en spiller ville gøre (Iteration 13).
- **Hvad det gør:** Den sejler mod Malmø, slæber et blink efter båden, lander en fisk med hjulet og gemmer/indlæser. Derefter ankrer den ved ankerspillet, steger fisken til aftensmad, sover for anker, letter anker og sejler videre, og den tjekker, at et sidste gemt spil indlæses helt nøjagtigt. En anden aften tjekker hårdt vejr: man kan ikke ankre i kuling, og ankeralarmen vækker dig i tide.
- **Arbejder sammen med:** app-scenen, `GameSession`, `Simulation`, `FishingMenu`, `AnchorMenu`, `CookingMenu`, testhjælperne til fiskehjulet og gang-områder, `WindField`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Fordi den bruger så mange dele af spillet, kan ændringer i fiskeri, ankring, madlavning eller søvn få den til at fejle.

### `tests/suites/test_chart_and_pause.gd`

**Formål:** Tjekker sidepanelet på søkortet og den fælles pauseknap.
- **Hvad det gør:** Den tjekker søkortets sidepanel (overskrift, fanerne Course / Weather / Details og bundlinje): det bliver på plads på alle faner, ved 20× fart, med forskellige størrelser på brugerfladen og i et mindre vindue. Den prøver også at ændre kurs, knapperne til zoom, centrering og vind, og at trække i kortet. Pause skal stoppe tiden, sejladsen, vinden og ledsageren i kahytten, på dækket og på søkortet. Søvn skal virke under pause, og et spil gemt på pause skal indlæses på pause.
- **Arbejder sammen med:** `WorldMap`, tidsbjælken i HUD'en (skærmens faste info-lag), `GameSession`, `Simulation`, `SleepMenu`, `SettingsManager`, `SaveManager`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Flytter du knapper på søkortet eller ændrer pausen, kan den fejle.

### `tests/suites/test_chartroom_ui.gd`

**Formål:** Tjekker "Kortrum"-udseendet: ét fælles tema (fælles farver og skrifttyper) med en dag-stemning og en nat-stemning.
- **Hvad det gør:** Den tjekker temaets farver, skrifttyper og kontrast. Den tjekker, at Altid dag / Altid nat / Automatisk gemmes i indstillinger (ikke i det gemte spil), og at Automatisk følger dagslyset i spillet og skifter langsomt. Et åbent vindue skal blive åbent, når stemningen skifter. Den tjekker også en roligere HUD, søkortets kurspanel, vedligehold af båden, fiskeriets tidsskive, og at farvetoner følger stemningen. I026: under sejlads står ruten, farten og vinden kun på instrumenterne, og rutepanelet beholder kun sin Menu-knap.
- **Arbejder sammen med:** `UiTheme`, `SettingsManager`, `Hud`, `WorldMap`, `BoatCareMenu`, `FishingMenu`, `ReelDial`. I026: `InstrumentCluster`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Ændrer du temaets farver eller HUD'ens opbygning, kan den fejle.

### `tests/suites/test_coastal_depth.gd`

**Formål:** Tjekker kystkortet for hele verden, havdybder og reglerne for at ankre, uden at starte spillet (revision 0.105b).
- **Hvad det gør:** Den tjekker, at det detaljerede kystkort indlæses, og at ruteplanlæggeren kan nå vand tæt på kysten via en kort, sikker vej. Den bruger opdigtede kyster og dybdefiler til at teste svære tilfælde. Dybder skal mærkes "GAME ESTIMATE" (spillets skøn), altid være de samme for samme sted og være jævne og varierede. Den tjekker, at læ afhænger af vinden, men dybden gør ikke, reglerne for at ankre, og at seks sejlområder rundt om i verden hver har en brugbar ankerplads.
- **Arbejder sammen med:** `CoastalGeography`, `DepthService`, `DepthData`, `SeaRouter`, `AnchorSite`, `GameSession`.
- **Holder styr på:** Intet af sit eget (den skriver to små midlertidige testfiler).
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på kystdataene, dybdeskønnene eller reglen for at ankre.

### `tests/suites/test_cockpit_ui.gd`

**Formål:** Tjekker cockpittet: instrumenterne, rorets kortplotter og handlingshjulet (Iteration 17; I026-instrumenterne).
- **Hvad det gør:** Under sejlads mod Las Palmas tjekker den, at instrumenterne i HUD'en (som afløste sejlpanelet i I026) viser fart, kurs, vind, næste strækning og næste sving, med skøn mærket som skøn; at de ikke vises i havn og ikke dækker andre paneler; at et klik åbner deres nærbillede, og Esc lukker det; at sidste strækning siger "No more turns"; og at et kursskift på mere end 5° kort fremhæver kursen. Kortplotteren er ikke længere i HUD'en: P åbner rorets plotter tæt på, fra dækket og fra kahytten, dens knapper skifter afstandsområde, den bygger aldrig det store verdenskort, og Esc lukker den. Handlingshjulet (Q) viser de rigtige handlinger på dækket og i kahytten, virker med både tastatur og mus, bruger plotteren med E, og intet bag det reagerer.
- **Arbejder sammen med:** `InstrumentCluster`, `InstrumentView`, `PlotterView`, `ChartPlotter`, `ActionWheel`, `Hud`, `WorldMap`, `GameSession`, `Simulation`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Ændrer du instrumenternes ordlyd, visningerne eller handlingerne i hjulet, kan den fejle.

### `tests/suites/test_companion_art.gd`

**Formål:** Tjekker billederne af katten og hunden, og hvordan de opfører sig (Iteration 004b, med nye tegninger siden Iteration 13).
- **Hvad det gør:** Den tjekker billederne af stillingerne (hviler, sover, vågen, strækker sig) for kat og hund, og at ejerens originale kattetegninger i `Visuals/Cat/` aldrig bliver ændret. Den tjekker, at hvid papirbaggrund bliver fjernet, og at stillingerne skifter en gang imellem uden at blinke. Den tjekker også at gå hen til og klappe dyret (lysende omrids, spinden), hvad der sker, når et billede mangler, at et nyt billede kan skiftes ind alene via data, alle både, og at stillinger ikke gemmes. Siden I024 er hver stilling et animeret klip med flere billeder, og billedets fodpunkt står på hvilestedet. I025: Nyt spil viser ikke længere en ledsager; testen tjekker det og starter så et spil med katten for at teste tegningerne. Kun synlige ledsagere tælles (en kahyt har også en tom plads til en anden).
- **Arbejder sammen med:** `CompanionVisualSet`, `ShipCompanion`, `NewGameMenu` (ingen forhåndsvisning siden I025), `CompanionState`, `AudioManager`, `SaveManager` og testhjælperen til gang-områder.
- **Holder styr på:** Intet af sit eget (den skriver et midlertidigt testbillede og sletter det igen).
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Den fejler, hvis nogen retter i ejerens originale kattetegninger, fordi deres fingeraftryk bliver tjekket.

### `tests/suites/test_companion_deck.gd`

**Formål:** Tjekker, at ledsageren kommer op på dækket, ankersignalerne og bådens lys om natten (Iteration 18).
- **Hvad det gør:** På alle fire både tjekker den tre sikre hvilepladser på dækket, og at ledsageren følger kaptajnen op og ned efter en lille pause og aldrig går ud over kanten. Den går under dæk, når båden sejler, eller når vinden tager til, og dens plads bliver gemt. For anker vises den sorte kugle, ankerlinen og bøjen. Om natten tjekker den lysene: hvidt ankerlys for anker, rødt/grønt/agterlys under sejlads (i de rigtige sider i alle otte visningsretninger) og ingen lys ved fortøjning.
- **Arbejder sammen med:** `DeckCompanionSpots`, `ShipCompanion`, `GameSession`, `BoatLighting`, `SailRig`, `SaveManager` og app-scenen.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Flytter du beslag på dækket eller ændrer dækkets omrids, kan den fejle.

### `tests/suites/test_companion_remarks.gd`

**Formål:** Tjekker de venlige ord, når der bliver kælet for ledsageren.
- **Hvad det gør:** Tjekker, at katte og hunde har deres egne linjer, at den samme linje aldrig kommer to gange i træk, linjerne "dygtig pige"/"dygtig dreng" for en hund med navn, at et navn med danske bogstaver bevares præcist, de danske linjer og sprogskift, at kæle for en kat og en hund i kahytten (reaktionen kommer stadig, en bemærkning kommer, ikke igen med det samme, en anden senere), reglen om fulde hænder, og at gemte spil er uændrede.
- **Arbejder sammen med:** `CompanionRemarks`, `ShipCompanion`, `BoatArea`, `GameSession`, `SettingsManager`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** I testkørslen (`--only=companion_remarks`).
- **Hvis du ændrer det:** Kun testen; bemærkningernes ordlyd tjekkes via deres engelske nøgler.

### `tests/suites/test_company_we_keep.gd`

**Formål:** Tjekker I024, The Company We Keep.
- **Hvad det gør:** Tjekker de tre ledsagere med valgfrit navn og køn (intet opfundet), og at ældre gemte spil beholder deres, også et rigtigt gemt spil fra versionen før I024 (`tests/fixtures/save_pre_i024.json`: ledsager, omdømme, optegnelser og postkort bevaret, datoer vist, "Stedet er ikke registreret"); linjerne på engelsk og dansk; de animerede klip (gå, vende, sove, vågne, kæl) og papegøjens letten, flugt og landing; at ledsageren følger Kaptajnen i land, at båden ikke kaster los, mens den er i land, at den kan kaldes om bord, og at en indlæsning aldrig efterlader den i land; opvågning ved køjen; snak på lange passager, der aldrig bliver en strøm, heller ikke efter en indlæsning; rekorder og milepæle for vedvarende fart for sejl; samlingen af bedrifter (rækkefølge, grå låste mærker, hvornår, hvor og hvilken båd, ærlige erstatninger for ældre gemte spil, intet betalt to gange); og laptoppen på hvert kahytsbord med sine apps, Esc, postkort og fjernarbejde. I025: tjekket af Nyt spil bekræfter nu, at der ingen ledsager er at vælge, og at spillet starter uden en (skærmbillede `i025_new_game`).
- **Arbejder sammen med:** app-scenen, `CompanionState`, `CompanionRemarks`, `CompanionVisualSet`, `ShipCompanion`, `NewGameMenu`, `GameSession`, `Simulation`, `SessionState`, `ObjectiveProgress`, `AchievementCatalog`, `LaptopView`, `SettingsManager`, `WeatherFixtures`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (den gemmer `i024_*`-skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun tjekkene ændres; fejler testen, kan ledsagerne, bedrifterne eller laptoppen opføre sig forkert.

### `tests/suites/test_cost_of_wind.gd`

**Formål:** Tester brændstof og driftsomkostningerne (I027).
- **Hvad det gør:** Tester balancefilen, brændstof brugt kun for motor, en tom tank der overlader det til sejlene (ingen gratis motor, aldrig strandet), køb af brændstof (fyld op, med få penge, Relaxed billigere, intet til søs), havnepenge (nætter, et kort ophold, eftergivet ud over pengene), regnskabet og en rejses oversigt, motor op mod vinden mod krydsning, det hele gennem et gemt spil og et ældre gemt spil, og tankanlægget på kajen med sin menu og havnekontorets driftsomkostninger; at ankomstestimatet regner med brændstoffet om bord, og beskeden når tanken løber tør. Den tester også, at handlingshjulet under sejlads aldrig lader sine punkter overlappe ved de lovede størrelser og skaleringer.
- **Arbejder sammen med:** `Economy`, `GameSession`, `Simulation`, `CareerLedger`, `SessionState`, `HarbourFront`, `FuelMenu`, `HarbourOfficeMenu`, `Hud`, kajhjælperen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i brændstof, havnepenge eller regnskabet kan få den til at fejle.

### `tests/suites/test_cozy_patch.gd`

**Formål:** Tjekker den lille rettelse efter 0.105b: at klappe katten mens hun går, fiskebilleder på trofætavlen og Drømmerens kort (Dreamer's Map) og dets farver.
- **Hvad det gør:** Den klapper Snøvs, mens hun går op på dækket, lige efter hun er nået frem, og mens hun går ned igen. Turen holder pause, hun reagerer én gang og ender stadig det rigtige sted. Den tjekker, at hvert trofæ viser sit eget fiskebillede, at tomme pladser forbliver tomme, og at en ny fangst vises med det samme. Drømmerens kort skal have sine malede farver, men søkortet til navigation skal ikke.
- **Arbejder sammen med:** `ShipCompanion`, `DeckCompanionSpots`, `TrophyBoard`, `FishArt`, `FishingState`, `WorldMap`, `GameSession`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Turene køres i spiltid uden at vente på rigtige billeder, og timeren, der får hende til at følge kaptajnen, står stille, mens hun går ned, så resultatet ikke længere afhænger af computerens fart.

### `tests/suites/test_cozy_polish.gd`

**Formål:** Tjekker "Cozy Polish"-runden med rettelser til navigation og komfort.
- **Hvad det gør:** Den tjekker ruter gennem Kielerkanalen, Suez (med Bab-el-Mandeb) og Panama og rundt om Stockholm, også når man gemmer midt i en kanal. Den tjekker, at søkortet holder sig på kortet, når man zoomer helt ud, og at et vildfarent klik ikke længere tilføjer et rutepunkt. Ting, der flyder i vandet, skal glide agterud forbi båden, og Q-menuen skal have sine nye navne og flueben. Kaffe og hue optager dine hænder, og alle både har en kopholder. Den tjekker også, at søvnlængden huskes, nåle for besøgte havne, mindre paneler, indlæsningsskærmen og kaffen i gemte spil. I026: ved roret tilbyder hjulet Chart plotter og Instruments, som åbner deres nærbilleder (uden flueben), mens radaren beholder sit flueben for til/fra.
- **Arbejder sammen med:** `SeaRouter`, `WorldMap`, `MapView`, `WaterLife`, `ActionWheel`, `CoffeeMug`, `GameSession`, `SleepMenu`, `SettingsManager`, `LoadingScreen`, `SessionState`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Den tjekker også, at gemmeformatet stadig er 12, så hæver du gemmeformatet, skal denne test også rettes.

### `tests/suites/test_data_model.gd`

**Formål:** Tjekker de grundlæggende byggesten: havne, afstande, kortprojektionen og det gemte spils tilstand.
- **Hvad det gør:** Den tjekker, at omkring 150 havne eller flere indlæses, at afstanden fra København til Kiel er omkring 116 sm, og at kortet omregner positioner korrekt frem og tilbage. Den gemmer en spiltilstand (med en planlagt rute) som tekst og indlæser den igen uændret. Ødelagte data bliver afvist i deres helhed, og planlægning af en rute virker.
- **Arbejder sammen med:** `PortCatalog`, `GeoMath`, `MapProjection`, `SessionState`, `GameSession`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test (det er den første testsamling på listen).
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl her betyder som regel, at gemme/indlæse er i stykker.

### `tests/suites/test_denmark_views.gd`

**Formål:** Tager billeder af de detaljerede danske farvande på søkortet og på havet (Iteration 14).
- **Hvad det gør:** Den viser søkortet i flere zoomniveauer over Danmark og tjekker, at det detaljerede danmarkskort bliver tegnet. Den lægger en kurs fra København rundt om Sjælland til Svendborg, sejler den og ankrer nær kysten. Derefter besøger den bådeværftet på kajen i Svendborg. Tjekkene er lette; skærmbillederne er hovedsagen. I026: bådeværftet findes nu ved at gå op på kajen i Svendborg, hvor dets facade lyser op.
- **Arbejder sammen med:** `WorldMap`, `MapView`, `SeaRouter`, `GameSession`, `Simulation`, `BoatyardMenu`, `HarbourFacilities`. I026: `HarbourFront`, `QuayLayout`, kaj-hjælperen.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test (billederne kun når kørslen gemmer skærmbilleder).
- **Hvis du ændrer det:** Kun tjekkene og skærmbillederne `14_*` ændrer sig.

### `tests/suites/test_dev_guides.gd`

**Formål:** Tjekker udviklervejledningerne i `DEV_GUIDES/` og læseren til dem inde i spillet (Iteration 004b).
- **Hvad det gør:** Den tjekker, at alle vejledningsfiler findes, og at alle links og filstier i vejledningerne og hoveddokumenterne virkelig findes. Den tjekker, at den simple omformer fra Markdown (et tekstformat) til visningstekst virker. Den åbner læseren fra hovedmenuen, vælger en vejledning, ruller og lukker den. Mangler vejledningerne, skjuler funktionen sig selv uden fejl.
- **Arbejder sammen med:** `DevGuides`, `DevGuidesMenu`, `MarkdownLite`, `MainMenu`.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Den fejler, når en vejledning eller et dokument får et dødt link eller nævner en fil, der ikke findes, så hold dokumenterne ryddelige.

### `tests/suites/test_diagnostics.gd`

**Formål:** Tjekker diagnoseloggen, en lille fil med optegnelser, som spillet skriver, mens du spiller.
- **Hvad det gør:** Den tjekker, at hver spillesession skriver én fil med én optegnelse pr. linje, som starter med spillets version. Filen skal optegne begivenheder som gemme, indlæse, kaptajnshuen, præstationer, penge og fejl. Den må ikke indeholde personlige data som dit brugernavn, og spillet skal opføre sig præcis ens med og uden loggen. Antallet og størrelsen af filerne er begrænset.
- **Arbejder sammen med:** `SessionLog`, `GameSession`, `SaveManager`, `GameVersion`, `Simulation`.
- **Holder styr på:** Intet af sit eget (den bruger sin egen midlertidige logmappe og rydder den op).
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Den tjekker det nøjagtige versionsnummer ("0.113a") og gemmeformat (12), så et nyt versionsnummer betyder, at denne test skal rettes.

### `tests/suites/test_eight_directions.gd`

**Formål:** Tjekker, at visningen af dækket drejer til den nærmeste af otte kompasretninger, mens båden sejler (Iteration 13).
- **Hvad det gør:** Den tjekker reglen for at vælge den nærmeste retning, også den "klæbrighed", der forhindrer visningen i at hoppe frem og tilbage. På dækket tjekker den, at stævnen peger rigtigt på skærmen i alle otte retninger, og at drejet er blødt. W-tasten skal stadig gå op ad skærmen, kameraet skal følge kaptajnen på en stor båd, alle fire både skal virke, og indstillingen med fast visning skal stadig virke.
- **Arbejder sammen med:** `BoatArea`, `SettingsManager`, `GameSession`, `Simulation` og app-scenen.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Den venter i rigtig tid på, at kameraet drejer, så ændret timing kan påvirke den. Skærmbillederne hedder `13_view_*`.

### `tests/suites/test_fishing.gd`

**Formål:** Tjekker det grundlæggende fiskeri: fiskestangen, blink, fisk fra data, bid, at beholde og sælge fangst og trofætavlen (Iteration 13).
- **Hvad det gør:** Den tjekker data for fisk og blink. Den tjekker, at bid kommer efter en fast tidsplan (den samme, uanset hvordan tiden deles op), at hver fisk kun gemmes én gang, og at belønninger kun udbetales én gang. Når køleboksen er fuld, ryger fisken ud igen. Den tjekker også salg og køb af blink, at fangsten gemmes, fiskestang og trofætavle på alle både, fiskepanelet med hjulet, et bid man ikke når, slæbefiskeri under sejlads og trofætavlen efter gemme/indlæse.
- **Arbejder sammen med:** `FishingCatalog`, `FishingState`, `GameSession`, `FishingMenu`, `TrophyMenu`, `SaveManager` og testhjælperne til fiskehjulet og gang-områder.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på fiskereglerne, fiskedataene eller pladserne til fiskestang og trofætavle.

### `tests/suites/test_fishing2.gd`

**Formål:** Tjekker "Fiskeri 2.0": hjulet til at hale fangsten ind, fiskenes størrelse og klasse, fiskebillederne, reglerne for at beholde fisk, hajer og skrald (Iteration 18).
- **Hvad det gør:** Den tjekker reglerne for hjulet: hvor mange gode tryk hver sjældenhed kræver, Perfect-tryk, tilgivende bom, og at det er fair for både omhyggelige og sjuskede spillere. Den tjekker vægt og klasserne Bronze/Silver/Gold, og at hver fisk og hvert stykke skrald har sit eget billede, som blinker og slår med halen (men står stille med Reduce motion), og at to fisk aldrig blinker i takt over tredive sekunder. Den tjekker også reglerne for at beholde fisk, at hajer altid sættes fri og skrald smides ud, at man kan nå fiskestangen med R overalt om bord, gemte spil og fiskeri for anker og i hurtig tid.
- **Arbejder sammen med:** `ReelTiming`, `FishingCatalog`, `FishArt`, `FishPortrait`, `FishingMenu`, `CatchBadge`, `GameSession`, `Simulation`, `SettingsManager` og testhjælperen til fiskehjulet.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. Ændrer du hjulets fart, buerne eller fiskedataene, kan den fejle.

### `tests/suites/test_galley_and_anchor.gd`

**Formål:** Tester kabyssens komfur og ankeret (Iteration 13, "The Cove").
- **Hvad det gør:** Tester ankerets regler for, hvor godt det holder. I det rigtige spil laver det mad af fangst og dagligvarer og tjekker reglen om, at komfuret er slukket, når det er for urolig sejlads. Derefter ankrer det ved Malmø, lader ankeret drive i tiltagende vind, sover for anker og gemmer/indlæser for anker.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `AnchorSite`, `AnchorState`, `CookingMenu`, `AnchorMenu`, `SaveManager` og app-scenen.
- **Holder styr på:** Intet selv; det bruger gemmeplads 3 kortvarigt og sletter den bagefter.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke. Ændringer i madlavning, ankring, drivende anker eller placeringen af ankerspil og komfur på en båd kan dog få testen til at fejle.

### `tests/suites/test_gameplay_flow.gd`

**Formål:** Spiller hele spillet fra start til slut, som en spiller med tastatur og mus.
- **Hvad det gør:** Tester hovedmenuen, et nyt spil, at gå rundt og støde ind i ting, og de små hjælpetekster ved tingene. Det tester også søkortet (zoom, panorering, kurs og rutepunkter), trappen mellem kahyt og dæk, pausemenuen, indstillinger, gemme/indlæse og Fortsæt. Så sejler det en første tur til Kiel med et kulingvarsel og en ny kurs og slutter med at trykke Afslut. Steady Hands: tjekket af ture gennem nedgangen fortæller, hvor spilleren stod, og hvad prompten sagde, for at finde en sjælden fejl. Rundturene ad nedgangen flytter skibets kammerat til side, når den sidder ved lugen (den blev før klappet i stedet, en fejl der kom og gik), og tjekket for "ingen teleportering" tillader den afstand, båden faktisk sejler, mens søkortet åbner. I025: Nyt spil åbner kun sin dialog (der vælges ingen ledsager), og diagnosen for rundturene regner ikke længere med, at der findes en ledsager. I026: mellem nedgangen og kortbordet kan navigationspladsens egne ting (logbogen, VHF-radioen, eltavlen) også være inden for rækkevidde.
- **Arbejder sammen med:** app-scenen, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, `SeaRouter`, `WeatherFixtures`, `MainMenu`, `WorldMap`, `PauseMenu` og `SaveLoadMenu`.
- **Holder styr på:** Intet selv (testgemmepladser og en testfil til indstillinger).
- **Hvornår det kører:** Kun i testene, og som den allersidste test, fordi den lukker programmet.
- **Hvis du ændrer det:** Spillet ændres ikke. Det er den bredeste test, så næsten enhver ændring i menuer, styring, søkort eller gemte spil kan få den til at fejle.

### `tests/suites/test_golden_harbours.gd`

**Formål:** Tester de gyldne havneøjeblikke.
- **Hvad det gør:** Sejler rigtige ture til havne, der aldrig er besøgt før, og tjekker, at den første ankomst viser ét illustreret kort (med navnet, "Første besøg" og logbogslinjen og ingen særskilt logbogsbesked), at et klik lægger det væk, at en kendt havn beholder det lille kort, og at et andet besøg ikke viser noget kort. At indlæse et spil i en ny havn og at gå under dæk og op igen viser intet. Den tjekker også lyset for tidspunktet (dag, skumring på dansk med stemplet på dansk, nat), at kortet bliver inden for skærmen, og at maleriets vinduer findes hurtigt og huskes. Den tager skærmbillederne for dag, skumring og nat.
- **Arbejder sammen med:** `App`, `HarbourMoment`, `Toasts`, `GameSession`, `Simulation`, `SaveManager`.
- **Holder styr på:** Intet (vinduesstørrelse, sprog og automatisk tid gendannes).
- **Hvornår det kører:** Sammen med de andre testsæt (`test_runner.tscn`).
- **Hvis du ændrer det:** Kun testene ændres.

### `tests/suites/test_harbour_chart.gd`

**Formål:** Tester, at søkortet forbliver overskueligt og hurtigt med mange havne.
- **Hvad det gør:** Tester, at kun vigtige havne vises langt ude, og at flere vises, når man zoomer ind. Det tester også, at navne aldrig overlapper, at havnesøgning finder og zoomer ind på en havn, og at tastning i søgefeltet ikke flytter kortet. Desuden måler det tiden for kortets layout med op til 1.000 opdigtede havne.
- **Arbejder sammen med:** `WorldMap`, `MapView`, `PortCatalog`, `PortData` og app-scenen.
- **Holder styr på:** En lille tabel med måletider, som det udskriver.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i havnemarkører, navne, søgning eller havnelisten kan få testen til at fejle.

### `tests/suites/test_harbour_life.gd`

**Formål:** Tester livet i havn: at gå i land, havnens tilbud, Gå i land-oplevelser og dæksvisningen, der følger kursen (Iteration 12).
- **Hvad det gør:** Tester, hvilke havne der har dagligvarebutik, bådeværft og optagning (Lohals har for eksempel intet bådeværft). På hver båd tester det, at man kan gå ned ad landgangen til pontonen og tilbage. Det tester også, at ting lyser op i stedet for cirkler, at Gå i land-oplevelser koster og betaler én gang, at landgangen tages ind, når man sejler, og at man kan gemme, mens man er i land. Til sidst tester det, at dækket under sejlads kan dreje, så stævnen peger langs kursen. Siden I021 står de små nye havne (Dingle, Ísafjörður, Symi, Essaouira, St. Helena) på listen over havne uden bådeværft. I026: på hver båd står gangbroen til kajen i land og kan nås til fods, dens skilt er pontonens eneste og lyser op med "To the quay"; på kajen lyser købmandens og bådeværftets facader op; Lohals har hverken bådeværft eller skibshandel på kajen, men sin købmand og stræden ind til byen, som nu er Gå i land ("Into town (Go ashore)"); under sejlads kan hverken tilbuddene eller gangbroen bruges.
- **Arbejder sammen med:** `HarbourFacilities`, `ShoreEvents`, `GoAshoreMenu`, `BoatArea`, `Interactable`, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, hjælperen til gangbarhed og app-scenen. I026: `HarbourFront`, `QuayLayout`, kaj-hjælperen.
- **Holder styr på:** Intet selv (bruger gemmeplads 3 og sletter den).
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i havnens tilbud, pontonernes layout, oplevelser i land eller kursvisningen kan få testen til at fejle.

### `tests/suites/test_harbours.gd`

**Formål:** Tester hver havn i havnekataloget (listen over alle havne).
- **Hvad det gør:** Tester, at hver havn har et unikt, korrekt id og fuldstændige oplysninger, at den ligger ved en kyst inden for søkortet, og at den kan nå åbent vand. Det tester også, at hver havn kan sejle til den nærmeste oprindelige havn. Desuden prøver det eksempler på sejladser (kystnært, ø-hop, til havs, smalle stræder) og havnesøgningen. Siden I021 kender den også de nye havområder (Nordamerika, Vestafrika, Sydatlanten, Det Indiske Ocean, Sydøstasien).
- **Arbejder sammen med:** `PortCatalog`, `PortData`, `SeaRouter`, `NavGrid` og `GeoMath`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene (uden spilvindue).
- **Hvis du ændrer det:** Spillet ændres ikke; nye eller flyttede havne eller ændringer i havkortet kan få testen til at fejle.

### `tests/suites/test_hat.gd`

**Formål:** Tester kaptajnshuen: at hænge den op, bære den, have den under armen, miste den og købe en ny.
- **Hvad det gør:** Tester huekrogen og H-tasten, og hvordan hård vind og vindstød belaster en hue, man har på på dækket. Det tester også advarslen, før den blæser væk, og at resultatet er det samme ved enhver tidshastighed og efter gemme/indlæse. Desuden tester det huen til €15 i dagligvarebutikken, gamle gemte spil, og huen på alle både og på spilleren i det rigtige spil.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `HatState`, `HatConfig`, `HatStory`, `HatBadge`, `SaveManager`, `WeatherFixtures` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i huens regler, pris, gemmeformatet eller krogens placering kan få testen til at fejle.

### `tests/suites/test_joy_journey.gd`

**Formål:** Spiller Kaptajnens eget eksempel på en tur med fiskeri, ankring og sejlads sammen, i 18 trin.
- **Hvad det gør:** Sætter et ankerplads-rutepunkt på vejen til Göteborg og trimmer sejlene i hånden. Derefter fisker det med slæbeline, fanger en fisk og slipper den igen og bruger Lang passage-tid frem til ankerpladsen. Så kaster det anker, laver kaffe og lader ledsageren komme op på dækket. Til sidst gemmer og indlæser det, letter anker og sejler videre til Göteborg. Efter indlæsning må intet ske to gange.
- **Arbejder sammen med:** `WorldMap`, `GameSession`, `Simulation`, `FishingMenu`, `AnchoragePrompt`, `SaveManager`, hjælperen til fiskehjulet (`tests/helpers/reel.gd`) og app-scenen.
- **Holder styr på:** Intet selv (bruger gemmeplads 3 og sletter den).
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i fiskeri, ankerpladser, Lang passage, ledsageren eller gemte spil kan få testen til at fejle.

### `tests/suites/test_life_aboard.gd`

**Formål:** Tester hverdagen om bord: katten eller hunden, søvn, søkortets panel og sejlene.
- **Hvad det gør:** Tester, at Nyt spil ikke tilbyder et valg af ledsager (I025), og, i spil startet med katten eller hunden, hvor ledsageren hviler, dens tidsplan og at klappe den (med lyd). Det tester også søvndialogen fra køjen og fra søkortet, at man vækkes tidligt af et vejrvarsel eller ved ankomst, og at søkortets panel står stille. Til sidst tester det rorets sejltjek, sejlenes rolige bevægelse, spilerens form og at ledsageren gemmes, også i gamle gemte spil. I024: når tiden kommer, går ledsageren hen til sit nye sted, og teksten siger "Pet the cat". I025: spillene med katten og med hunden startes direkte (`start_new_game` med den slags), fordi Nyt spil ikke længere vælger. I026: rorets sejltjek læser "Under sail" på instrumenterne.
- **Arbejder sammen med:** `NewGameMenu`, `SleepMenu`, `WorldMap`, `SailRig`, `ShipCompanion`, `CompanionState`, `AudioManager`, `GameSession`, `SaveManager`, `WeatherFixtures` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene (det går om bord i Wing 33, `starling_33`, fordi gåturene er skrevet til den kahyt).
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i ledsageren, søvn, søkortets sidepanel eller tegningen af sejl kan få testen til at fejle.

### `tests/suites/test_lighting.gd`

**Formål:** Tester lyset ved dag og nat (Iteration 17).
- **Hvad det gør:** Tester solens højde ud fra bådens position og årstid (også midnatssol) og rækkefølgen nat, daggry, dag, skumring. På hver båd tester det varme lamper og skygger i kahytten om natten og dagslys om dagen. Det tester også lys på dæk, i havnen og navigationslys, og at lyset skifter blødt ved Lang passage-tempo og med det samme efter indlæsning.
- **Arbejder sammen med:** `Daylight`, `BoatLighting`, `Interactable`, `GameSession`, `Simulation` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i lysets farver, lamper eller solberegningen kan få testen til at fejle.

### `tests/suites/test_living.gd`

**Formål:** Tester, hvordan man tjener og bruger penge: fjernarbejde og dagligvarebutikken.
- **Hvad det gør:** Tester fjernarbejde i havn (1–8 timer, €25 i timen, afvist til søs) og priser i dagligvarebutikken (€10 pr. manglende dag af mad og vand tilsammen, samme pris i alle havne). Det tester også, at reparationer koster det tilbudte beløb, at penge og proviant overlever gemme/indlæse, at hver båds kahyt har sin laptop ved arbejdspladsen (siden I024 åbnes fjernarbejde på laptoppen), og at butikken kan åbnes på alle både. I026: på hver båd har pontonen gangbroen til kajen med skilt, og købmanden nås ved sin dør deroppe.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `SaveManager`, `LaptopView`, `WorkMenu`, `GroceryMenu`, `WeatherFixtures` og app-scenen. I026: `BoatArea` (gangbroen), `QuayLayout`, kaj-hjælperen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i løn, priser, startpenge eller stationernes placering kan få testen til at fejle.

### `tests/suites/test_living_harbours.gd`

**Formål:** Tester de levende havne: kajen, dens butikker og åbningstider, byboerne og caféen (I026).
- **Hvad det gør:** Tester data for åbningstiderne og kajernes layout (en bygning for hver forretning, havnen har) og derefter i spillet: at gå op ad pontonens gangbro til kajen og ned igen, at hver dør lyser sin facade op og åbner sin menu i en butiksdisk-ramme, at en lukket butik tilbyder at vente, til den åbner (og at ventetiden virker), havnekontorets luge om natten, caféen (en kop kaffe, en plads på terrassen, ledsagerne ved bordet), byboerne (efter time og vejr, aldrig i en døråbning), handlingshjulet og tasterne på kajen, at man kan gemme på kajen uden et nyt felt i det gemte spil, og at man går om bord igen. Den tester også, at caféen, kontoret og dets luge, opslagstavlen og en butiksdisk passer til alle lovede skærmstørrelser og sprog, og at Kaptajnen fra hver caféstol rejser sig fri af bordene.
- **Arbejder sammen med:** `HarbourFront`, `QuayLayout`, `BusinessHours`, `ShopCounter`, `HarbourLife`, `HarbourNotes`, `CafeMenu`, `HarbourOfficeMenu`, `NoticeboardMenu`, `BoatArea`, `GameSession`, `SaveManager`, hjælperen til gangbarhed, app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i kajen, åbningstiderne eller butikkernes menuer kan få den til at fejle.

### `tests/suites/test_living_world.gd`

**Formål:** Tester udseendet i "en levende lille verden": sømanden, vandet og de tegnede både.
- **Hvad det gør:** Tester, at sømanden svinger armene, når han går, og at havnevandet bevæger sig roligt, med den rette slags vand for hver havn. Det tester også de illustrerede dæk og kahytter på hver båd, at bølgerne følger vinden under sejlads, og at kameraet glider ud, når båden forlader havnen, og ind igen ved ankomst. Tjekket af armsvinget går på det åbne fordæk og måles i afstand: fra startstedet gik sømanden ind i dækbeslag efter mindre end ét skridt, hvilket fik det til at fejle.
- **Arbejder sammen med:** `WaterLife`, `HarbourArt`, `SailorDrawing`, `VesselVisual`, `BoatArea`, `SettingsManager` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i grafikken, vandeffekterne eller kameraets udsnit kan få testen til at fejle.

### `tests/suites/test_localization.gd`

**Formål:** Tester sprogene engelsk og dansk.
- **Hvad det gør:** Tester, at hver engelsk tekst har en dansk oversættelse, der bevarer sine pladsholdere (steder, hvor tal eller navne sættes ind). Det tester også tal, penge, datoer og kompasretninger på hvert sprog, og at første opstart kun spørger om sproget én gang. Til sidst tester det, at skiftet i indstillinger virker med det samme, at dansk tekst kan være på skærmen, at bådens lys findes om bord på dansk, og at gemte spil er ens på begge sprog.
- **Arbejder sammen med:** `Loc`, `SettingsManager`, `LanguagePicker`, `GameSession`, `Simulation`, `SaveManager`, `locale/messages.pot`, `locale/da.po` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene (testkøreren slår møder til søs til for denne test).
- **Hvis du ændrer det:** Spillet ændres ikke; ny tekst uden dansk oversættelse får testen til at fejle.

### `tests/suites/test_long_passage.gd`

**Formål:** Tester Lang passage-tid (meget hurtig tid på lange sejladser) og sejlads over oceanerne.
- **Hvad det gør:** Tester, at en sejlads ender på samme måde i hurtig tid som i normal tid, og at hurtig tid stopper ved lav proviant, et bid eller ankomst. Det tester også passageproviant for hver båd, rådene om parathed før en lang passage og at gemme lige øst for datolinjen. Til sidst tester det "første gang"-oplevelser i Logbogen i Stillehavet og Lang passage-panelet på dækket.
- **Arbejder sammen med:** `Simulation`, `GameSession`, `PassageReadiness`, `VesselCatalog`, `Provisions`, `SaveManager`, `Hud` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i tidshastigheder, stop, proviant eller "første gang"-oplevelser kan få testen til at fejle.

### `tests/suites/test_magic_anchor.gd`

**Formål:** Tester det magiske anker og ankring med stoppet motor.
- **Hvad det gør:** Tester den fælles timing-skive (som fiskestangens hjul også bruger) og køb af det magiske anker i skibshandelen (kaptajnen beholder det på alle både). Det tester også at sætte ankeret til havs med én til tre gode omgange afhængigt af vinden, fejlforsøg, annullering og nyt forsøg, og at ankeret driver i kuling. Til sidst tester det, at ankring stopper motoren, og gemme/indlæse for anker.
- **Arbejder sammen med:** `TimingCheck`, `ReelTiming`, `MagicAnchorDeployment`, `AnchorMenu`, `TradePanel`, `HarbourTrades`, `BoatCareMenu`, `AnchorSite`, `GameSession`, `SaveManager` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i ankeret, skiven, priser eller motorreglerne kan få testen til at fejle.

### `tests/suites/test_marine_electronics.gd`

**Formål:** Tester den maritime elektronik: instrumentpakkerne, instrumenterne i HUD'en, enhederne i cockpittet og deres nærbilleder (I026).
- **Hvad det gør:** Tester, at hver instrumentværdi er lig spillets egne data (dybde kun til ankers, et skøn i spillet); at én samling instrumenter vises i HUD'en under sejlads, på dækket og i kahytten, aflæst nogle gange i sekundet og ikke hvert billede, og at de gamle svævende paneler er væk; at de tre pakker købes i skibshandelen, monteres i båden om bord, ejes for altid og kan vælges på enhver båd, at valget og siderne følger med, når der gemmes og indlæses, at ældre gemte spil får Classic, og at gemmeformatet stadig er 12; at hver båd har sin elektronik og plotterstation ved roret, og at E og klik åbner visningerne; at I og P åbner visningerne, Esc lukker dem, og sider og opstillinger skifter; og at alt passer ved 1280×720 og 1024×768, ved 100 % og 130 %, på engelsk og dansk.
- **Arbejder sammen med:** `InstrumentData`, `InstrumentPackage`, `InstrumentState`, `InstrumentCluster`, `InstrumentView`, `PlotterView`, `CockpitInstruments`, `ChandleryMenu`, `GameSession`, `SessionState`, `SaveManager`, `Hud`, app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i instrumenterne, deres ordlyd eller HUD'ens layout kan få den til at fejle.

### `tests/suites/test_more_room_aboard.gd`

**Formål:** Tjekker I025, A Little More Room Aboard.
- **Hvad det gør:** Tjekker, at et nyt spil starter uden ledsager, og at intet regner med en (kahyt, dæk, søvn, afgang, laptoppen, gemme og indlæse); at ældre gemte spil beholder deres ledsager præcis (det gemte spil fra før I024 og et spil gemt af I024) uden en opfundet adoptionsdato; at dyret på kajen er sjældent, men findes (chancen vokser for hver ankomst uden et), afgøres én gang pr. ankomst, aldrig slås om ved indlæsning, forsvinder, når båden kaster los, og ikke dukker op, mens to ledsagere bor om bord; kassen, de venlige gestus og at dyret følger efter, for hver slags; adoption ved nedgangen (navn, køn, velkommen om bord) og "Ikke nu" med den lille pige for hver slags (parakitten lander på hendes skulder); at velkomsten hjemme spilles én gang; to ledsagere (alle slags, samme slags to gange, samme navn to gange), der hver beholder deres egen identitet, pladser og gemte data, hviler side om side, vågner sammen med én linje, går i land sammen og begge kaldes tilbage; parøjeblikkene, parlinjerne på lange passager, laptoppens historik og optegnelsen "Velkommen om bord" (uden omdømme), på engelsk og dansk.
- **Arbejder sammen med:** app-scenen, `GameSession`, `SessionState`, `CompanionState`, `DockEncounters`, `DockEncounterScene`, `AdoptionDialog`, `CompanionRemarks`, `ShipCompanion`, `PairMoments`, `WelcomeHome`, `LaptopView`, `Simulation`, `WeatherFixtures`, `SettingsManager`, det gemte testspil `tests/fixtures/save_pre_i024.json`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (`test_runner.tscn`); i kørsler med skærm gemmer den `i025_*`-skærmbilleder og korte filmbilleder (`film_*`, sat sammen med `tools/qa/film_strip.py`).
- **Hvis du ændrer det:** Kun tjekkene ændres; fejler testen, kan fundne ledsagere, adoption, pigens farvel eller to ledsagere om bord opføre sig forkert.

### `tests/suites/test_navigation_views.gd`

**Formål:** Tester verdenskortet i ramme i kahytten ("Drømmerens kort") og arbejdskortet.
- **Hvad det gør:** Tester, at hver kahyt har et verdenskort, man kan gå hen til. På Drømmerens kort tester det, at der ikke er vind eller vejr, og at søgning og havnenes historier virker. "Forestil dig denne sejlads" skal nævne rigtige havne undervejs og må ikke ændre noget. Det tester også, at "Planlæg ved kortbordet" åbner det rigtige søkort, at kortet åbner omkring båden, og at det under sejlads viser næste kursændring.
- **Arbejder sammen med:** `WorldMap`, `MapView`, `VoyageDaydream`, `CabinWorldMap`, `HighlightResolver`, `SeaRouter`, `WeatherModel`, `GameSession` og app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i søkortets visninger, dagdrømmeteksten eller vindpilene kan få testen til at fejle.

### `tests/suites/test_objectives.gd`

**Formål:** Tester sejlermål og ry.
- **Hvad det gør:** Tester listen over mål (også de automatisk lavede) og at ry udbetales én gang, når en sejlads slutter. Gentagelige mål betaler kun igen ved en ny sejlads. En forlist båd får kun for sine sømil, og gemme, indlæse og gamle gemte spil betaler aldrig to gange. Det tester også fanen med mål i Logbogen. I024: et mål, der er taget ud af samlingen, tilbydes ikke længere der.
- **Arbejder sammen med:** `ObjectiveCatalog`, `ObjectiveProgress`, `CaptainsLog`, `CaptainsLogMenu`, `GameSession`, `Simulation`, `SaveManager`, `WeatherFixtures` og app-scenen.
- **Holder styr på:** En liste over de ry-belønninger, det har set under kørslen.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændrede belønninger, mål eller gemmeformat kan få testen til at fejle.

### `tests/suites/test_presentation.gd`

**Formål:** Tjekker små præsentationsdetaljer på dækket og ved ankomst i havn.
- **Hvad det gør:** Starter det rigtige spil og tjekker, at fendere hænger ude i havn og er stuvet væk under sejlads (på alle fire både), at sejl og bom tegnes oven over kaptajnen og bliver gennemsigtige, når kaptajnen står under dem, at havnens forhåndsvisning kun viser tjenester, der faktisk findes, og at den korte anløbsscene ved ankomst kan springes over og kun tæller ankomsten én gang.
- **Arbejder sammen med:** app-scenen, `GameSession`, `Simulation`, `SaveManager`, `FenderStowage`, `SailRig`, `HarbourFacilities`, `BoatArea`.
- **Holder styr på:** Intet selv; den bruger gemmeplads 3 kortvarigt og sletter den igen.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan fendere, tegningen af rigningen eller anløbet se forkerte ud i spillet.

### `tests/suites/test_publishing.gd`

**Formål:** Tjekker, at udgivelse af en rejseopdatering omsætter ry til penge korrekt.
- **Hvad det gør:** Tjekker, at ikke-udgivet ry udbetales til den fastsatte sats (som standard €2 pr. ry), kun i havn og aldrig to gange, at det samlede ry bevares, at det overlever gemme/indlæse, og at fjernarbejde og køb af proviant stadig virker. Derefter klikker den sig gennem udgiv-knapperne i Logbogen og i arbejdsdialogen (på laptoppen siden I024) i det rigtige spil.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `SaveManager`, `ObjectiveCatalog`, `CaptainsLogMenu`, `PublishMenu`, `WorkMenu`.
- **Holder styr på:** Intet selv; den bruger gemmeplads 2 kortvarigt og sletter den igen.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan spillere få forkert betaling for deres ry.

### `tests/suites/test_reassessment.gd`

**Formål:** Tjekker, hvornår båden beslutter at skifte mellem sejl og motor efter en ændring.
- **Hvad det gør:** Tjekker, at båden efter en kursændring, eller når du trykker "Check sail configuration" ved rattet, kan skifte mellem sejl og motor med det samme i tydeligt god eller dårlig vind, men stadig overholder minimumstiden for hver tilstand, så den aldrig skifter frem og tilbage. Den tjekker også rattets forklarende beskeder.
- **Arbejder sammen med:** `PropulsionController`, `PropulsionState`, `VesselProfile`, `WindField`, `GameSession`, `Simulation`, app-scriptets `describe_reassessment`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan båden skifte mellem motor og sejl på mærkelige tidspunkter.

### `tests/suites/test_regions.gd`

**Formål:** Tjekker det detaljerede danske søkort, og hvordan det passer ind i verdenskortet.
- **Hvad det gør:** Tjekker, at de detaljerede danske (og europæiske) søkort er indlæst, at byer inde i landet er land og stræder er åbent vand, at hver dansk havn har en vej ud til søs, at sejladser gennem danske farvande får fornuftige ruter, og at en gemt båd, der nu ligger på land, flyttes til nærmeste vand i stedet for at gå tabt. Den måler også indlæsnings- og rutehastighed og tjekker, at søkortet viser den detaljerede kyst, når man zoomer ind.
- **Arbejder sammen med:** `SeaRouter`, `NavGrid`, `PortCatalog`, `GameSession`, `AnchorSite`, `FishingCatalog`, `MapView`, `WorldMap`.
- **Holder styr på:** Intet selv; den udskriver tidsmålinger.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan danske ruter, havneindsejlinger eller gamle gemte spil blive påvirket.

### `tests/suites/test_route_wrap.gd`

**Formål:** Tjekker, at en planlagt rute bliver ved med at være synlig, mens du panorerer verdenskortet mod øst eller vest.
- **Hvad det gør:** Plotter lange ruter (Middelfart til Papeete, også med rutepunkter, og Papeete til Auckland hen over datolinjen), panorerer derefter søkortet jorden rundt trin for trin og tjekker, at ruten tegnes overalt, hvor den er i billedet, aldrig springer på tværs af kortet og ikke ændres af panoreringen. Den tjekker også kurslinjen under sejlads og dagdrømmeruten på Dreamer's Map.
- **Arbejder sammen med:** app-scenen, `WorldMap`, `MapView`, `GameSession`, `PortCatalog`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (pixeltjekkene kun, når spillet faktisk tegnes på skærmen).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan ruter forsvinde fra søkortet, mens man panorerer.

### `tests/suites/test_routing.gd`

**Formål:** Tjekker, at sejlruter aldrig krydser land og når frem til alle havne.
- **Hvad det gør:** Tjekker, at rutefinderen (den del, der planlægger en kurs uden om kysterne) finder gyldige ruter mellem alle europæiske havne og fra København til alle havne i udlandet, bruger de rigtige stræder (Gibraltar, Dover, Øresund, Storebælt, Bonifacio, Panama), krydser datolinjen den korte vej, afviser rutepunkter på land og fejler sikkert ved umulige ruter. Hver rute tjekkes også mod kystlinjen, sådan som søkortet tegner den.
- **Arbejder sammen med:** `SeaRouter`, `PortCatalog`, `GeoMath`, `PlannedRoute`, `MapProjection`, `NavGrid`, `WorldLand`, `GameSession`.
- **Holder styr på:** Intet selv; den indlæser de tegnede landformer én gang til sine egne tjek.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan kurser krydse land, eller nogle havne kan blive umulige at nå.

### `tests/suites/test_sail_trim.gd`

**Formål:** Tjekker funktionen sejltrim.
- **Hvad det gør:** Tjekker, at det bedste trim følger vindvinklen (hårdt trimmet bidevind, slækket på læns, lidt fladere i hård vind), at virkningen er beskeden (højst 6 % hurtigere eller 10 % langsommere), aldrig starter eller stopper motoren og ikke lægges oven i sig selv, at hurtig tid giver samme resultat, at indstillingen gemmes (gamle gemte spil lader besætningen trimme), og at T og handlingshjulet åbner trimpanelet med feedback som "Well trimmed", "Too tight" og "Too loose". I026: instrumenterne viser trimmet og dets tast.
- **Arbejder sammen med:** `SailTrim`, `GameSession`, `Simulation`, `SessionState`, `SailTrimPanel`, `InstrumentCluster`, app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan sejltrim gøre båden for hurtig eller langsom, eller panelet åbner måske ikke.

### `tests/suites/test_sailing.gd`

**Formål:** Tjekker det automatiske valg mellem sejl og motor, og at sejladser forløber ens, uanset hvor hurtigt tiden går.
- **Hvad det gør:** Tjekker, at båden sejler i god vind og bruger motor i let luft, venter på en varig ændring før den skifter, aldrig skifter frem og tilbage, sætter spileren på læns, giver samme sejlads ved normal hastighed, hurtig tid eller søvn, giver et godt bud på ankomsttiden, stadig giver vejrvarsler, og gemmer og indlæser sejl/motor-tilstanden (også gamle gemte spil fra Iteration 002).
- **Arbejder sammen med:** `PropulsionController`, `PropulsionState`, `VesselProfile`, `WindField`, `Simulation`, `GameSession`, `SessionState`, `SaveManager`, `WeatherFixtures`.
- **Holder styr på:** Intet selv; den skriver en midlertidig gemt fil i gammelt format på plads 3 og fjerner den igen.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan sejlhastigheder, ankomsttider eller gemte spil blive påvirket.

### `tests/suites/test_sailing_correctness.gd`

**Formål:** Tjekker, at dækket drejer med båden, og at gemme på havet sætter alt præcist tilbage.
- **Hvad det gør:** Tjekker, at dækket tegnes langs bådens kurs og drejer, når autopiloten drejer (uanset hvor kaptajnen står, og efter et besøg i kahytten). Den gemmer og indlæser på havet i mange situationer (ved rattet, i stævnen, agter, i kahytten, for anker, i kuling om natten) og tjekker, at kaptajnen, tid, position, vejr og penge kommer præcist tilbage, og at genindlæsning giver samme vejr. Den tjekker også hurtiggem (F5) og hurtigindlæs (F9).
- **Arbejder sammen med:** app-scenen, `BoatArea`, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, `WindField`, `WeatherFixtures`.
- **Holder styr på:** Intet selv; den rydder gemmeplads 1–3 og hurtiggemmet før og efter.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, bliver gemte spil på havet måske ikke genskabt korrekt, eller dækket vender forkert.

### `tests/suites/test_sailing_presentation.gd`

**Formål:** Tjekker, hvordan sejlads og motorsejlads ser ud og lyder i det rigtige spil.
- **Hvad det gør:** Sætter kendte sejltilstande og tjekker, at sejlene ligger i læ (væk fra vinden), at spileren sættes på læns og tages ned, når vinden går frem, at sejlene er rullet sammen under motor, at motorlyden er høj på dækket og dæmpet i kahytten og stopper ved sejlads, ved ankomst og i hovedmenuen, at HUD'en (skærmens infofelter) viser tilstand, vind og ankomsttid, og at søkortets vindlag og dets til/fra-knap virker. I026: tilstanden, vinden og ankomstskønnet læses på instrumenterne, ikke længere på rutepanelet.
- **Arbejder sammen med:** app-scenen, `SailRig`, `AudioManager`, `GameSession`, `PropulsionController`, `WorldMap`, `WindField`. I026: `InstrumentCluster`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan sejl, motorlyd, HUD eller vindlaget se forkerte ud eller lyde forkert.

### `tests/suites/test_save_manager.gd`

**Formål:** Tjekker, at gemmepladser skrives, læses og beskyttes korrekt.
- **Hvad det gør:** Tjekker tomme pladser og pladser uden for området, at gemning skriver en fil med de rigtige oplysninger (område, havn, destination, tidspunkt, formatversion), at indlæsning giver præcis det gemte tilbage, at "Continue" vælger det nyeste gode gemte spil, at der gemmes en sikkerhedskopi, når man overskriver, og at ødelagte, ulæselige eller filer fra en fremtidig version bliver meldt i stedet for at få spillet til at gå ned. Den tjekker også, at en mislykket gemning lader det gamle gemte spil være i fred.
- **Arbejder sammen med:** `SaveManager`, `SessionState`.
- **Holder styr på:** Intet selv; den arbejder i en separat testmappe til gemte spil og sletter plads 1–3 bagefter.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan spillernes gemte spil gå tabt eller blive læst forkert.

### `tests/suites/test_secret_achievements.gd`

**Formål:** Tjekker de syv hemmelige bedrifter med kaptajnshuen.
- **Hvad det gør:** Tjekker, at de hemmelige bedrifter findes i målsætningsdataene med små belønninger, at hver enkelt findes i den rigtige situation (første hue tabt, tredje hue tabt, €100 brugt på huer, en ny hue tabt inden for fem minutter, at beholde huen i farligt vejr, ti sejladser med den oprindelige hue, at miste den langt ude på havet), at hver kun giver ry én gang, også efter indlæsning, og at det aldrig kan betale sig at miste huer. Derefter tjekker den, at Logbogen skjuler hemmelige bedrifter, indtil de er fundet.
- **Arbejder sammen med:** `ObjectiveCatalog`, `GameSession`, `Simulation`, `HatState`, `HatConfig`, `HatStory`, `CaptainsLogMenu`, app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan hemmelige bedrifter blive afsløret for tidligt, udbetalt to gange eller slet ikke blive fundet.

### `tests/suites/test_settings_and_audio.gd`

**Formål:** Tjekker indstillingerne (lydstyrke, vindue, VSync, størrelse på brugerfladen) og lydsystemet.
- **Hvad det gør:** Tjekker standardindstillinger, at lydstyrken straks når lydkanalerne (0 % slår lyden fra, over 100 % begrænses), at indstillinger overlever en genstart, at forkerte værdier i indstillingsfilen falder sikkert tilbage, og, med et rigtigt vindue, at vinduestilstande og VSync bliver anvendt. Den tjekker også, at lydmanageren genbruger et fast sæt afspillere og kan starte, skifte og stoppe baggrundslyd og musik. Siden I022 tjekker den vindens lydstyrke: 100 % som standard, anvendt med det samme, bevaret efter genstart.
- **Arbejder sammen med:** `SettingsManager`, `AudioManager`, Godots `AudioServer` og `DisplayServer`.
- **Holder styr på:** Intet selv; den bruger en separat testfil til indstillinger og sletter den.
- **Hvornår det kører:** Kun i test (vinduestjek springes over uden et rigtigt vindue).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, virker indstillinger eller lyd måske ikke som forventet.

### `tests/suites/test_simulation.gd`

**Formål:** Tjekker spillets ur, sejladser, søvn, vejrvarsler og kursændringer.
- **Hvad det gør:** Tjekker, at spillet starter 1. maj 2026 kl. 08:00, at tiden kan sættes korrekt op og står stille under pause, at sejladser bevæger sig med den rigtige fart uanset tidsskridt, at ankomst meldes én gang og præcist til tiden, og at søvn afbrydes af ankomst eller et vejrvarsel. Den bruger et fast område med hård vind til at tjekke, at varsler kommer cirka 6 timer i forvejen og kun én gang, og at man kan ændre kurs eller destination på havet, uden at båden hopper.
- **Arbejder sammen med:** `Simulation`, `GameSession`, `WeatherFixtures`, `WeatherModel`, `SeaRouter`, `PortCatalog`, `GeoMath`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan tid, sejladser eller vejrvarsler opføre sig forkert.

### `tests/suites/test_solar_panels.gd`

**Formål:** Tjekker de dekorative solpaneler på alle fire både.
- **Hvad det gør:** Tjekker, at hver båd har solpaneler i passende størrelse (ét på den mindste, tre på den største), at de sidder agter, hvor de ikke er i vejen for kaptajnen eller Snøvs, ikke har kollision, drejer med båden, ses i havn, under sejlads, for anker og i bådeværftets forhåndsvisning, og kun er pynt (intet i det gemte spil, intet at købe, intet arbejde hvert billede).
- **Arbejder sammen med:** app-scenen, `BoatArea`, `VesselVisual`, `SolarPanels`, `TestWalkability`, `DeckCompanionSpots`, `BoatCare`, `BoatyardMenu`, `GameSession`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan panelerne være i vejen, mangle eller påvirke det gemte spil.

### `tests/suites/test_soundtrack.gd`

**Formål:** Tjekker spillets originale musik, og hvordan den skifter med situationen.
- **Hvad det gør:** Tjekker, at de tre musikstykker indlæses, kører i ring og er lange, og at de faktisk kan høres. Den tjekker, at musikken vælger det rigtige stykke (natmusik om natten; om dagen sejlmusik på dækket til søs og hjemmemelodien i havn, i kahytten og i menuer), at skift tones blødt over og venter et øjeblik, at et stykke fortsætter fra starten af en frase, at søkortet, pausemenuen eller indstillingerne ikke starter musikken forfra, at hurtig tid ikke får den til at skifte frem og tilbage, og at slukket musik ikke påvirker lydeffekterne.
- **Arbejder sammen med:** `MusicDirector`, `AudioManager`, `SettingsManager`, `GameSession`, `Simulation`, app-scenen.
- **Holder styr på:** Intet selv; den forkorter musikkens tider under testen og sætter dem tilbage.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan musikken blive klippet, starte forfra eller spille det forkerte sted.

### `tests/suites/test_sprite_workshop.gd`

**Formål:** Tjekker Sprite Workshop, systemet der lader ny grafik erstatte spillets indbyggede billeder.
- **Hvad det gør:** Tjekker, at grafiklisterne (manifests) er ryddelige og ærlige, og at der ikke ligger erstatningsbilleder tilbage i projektet, at manglende billeder falder tilbage til originalen, kun indlæses én gang, og at filer i forkert størrelse eller ulæselige filer afvises med en tydelig advarsel. Den installerer midlertidigt testbilleder for hver færdig post og for tre eksempler i det kørende spil (ankerbøjen, Snøvs der hviler, og ruffet på Arctic Wanderer 26) og tjekker, at de vises i rigtig størrelse og på rigtig plads, og fjerner dem igen.
- **Arbejder sammen med:** `ArtworkResolver`, `TestArtFixtures`, `TestWalkability`, `CompanionVisualSet`, `AnchorSignals`, `VesselVisual`, `SolarPanels`, `FishArt`, `HatArt`, `ShipCompanion`, app-scenen.
- **Holder styr på:** Intet selv; alle testbilleder, den installerer, fjernes igen.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, vises erstatningsgrafik måske ikke, eller dårlige grafikfiler kan ødelægge udseendet.

### `tests/suites/test_steady_hands.gd`

**Formål:** Tester, at brugerfladen bliver på plads, på skærmen, kan lukkes og er oversat (Steady Hands).
- **Hvad det gør:** Viser, opdaterer og skjuler vejradvarsler mange gange (engelsk og dansk, dag og nat, med hver af de tre instrumentpakker monteret) og tjekker, at instrumenterne (I026: de afløste Turdetaljer) aldrig flytter sig, og at advarslen aldrig dækker dem. Derefter åbner den alle vinduer, spillet tilbyder, fra spillets egne indgange, ved flere skærmformater og brugerfladestørrelser på begge sprog. Hvert vindue skal blive inden for skærmen, lukke med Esc og ikke vise rå pladsholdere eller engelsk tekst på dansk. Testen tjekker også HUD'ens paneler mod hinanden, hovedskærmene, det længste havnenavn med lange beskeder, hvad der sker, når situationen ændres under et åbent vindue, og at intet usynligt fanger musen. Den tjekker også skumring og daggry: over et helt døgn er brugerfladen enten dag eller nat (aldrig parkeret halvvejs) og skifter to gange, og teksten kan læses på sine paneler hele vejen gennem skiftet.
- **Arbejder sammen med:** `App`, `Hud`, alle vinduesklasser, `SettingsManager`.
- **Holder styr på:** Intet (vinduesstørrelse og indstillinger gendannes).
- **Hvornår det kører:** Sammen med de andre testsæt (`test_runner.tscn`).
- **Hvis du ændrer det:** Kun testene ændres; et nyt vindue hører til i dens liste over åbnere.

### `tests/suites/test_turbocharge.gd`

**Formål:** Tjekker, at de hurtigere genveje i vejrberegningen giver præcis samme resultat som den fulde beregning.
- **Hvad det gør:** Sammenligner det hurtige vejropslag med det fulde mange steder, datoer og seeds (startværdier for tilfældigheden) rundt om i verden, sammenligner vejrfarer på ruter og vejrskader med den tidligere beregningsmåde (som er gemt inde i testen), tjekker at den nye måde er billigere, og tjekker at tre nætters søvn til søs ender ens to gange i træk.
- **Arbejder sammen med:** `WeatherModel`, `Simulation`, `WeatherDamage`, `SeaRouter`, `GameSession`, `WindField`, `GeoMath`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan vejrvarsler eller stormskader være ændret, uden at det var meningen.

### `tests/suites/test_upkeep.gd`

**Formål:** Tjekker prisen for at sejle: bådens tilstand, stormskader, reparation, redning, penge og proviant.
- **Hvad det gør:** Tjekker starttilstanden (€10.000, 14 dages mad og vand, både på 100 %), at proviant bruges med den rigtige hastighed og advarer, når den er ved at slippe op, at storme (ikke almindelig vind) skader båden alt efter hvor robust den er, at resultatet er det samme ved enhver tidshastighed, at reparation koster penge i havn, at en båd med nul i tilstand bliver reddet til København for et gebyr på €1.000 (aldrig under €0), og at alt dette gemmes, og gamle gemte spil kan indlæses.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `WeatherDamage`, `WeatherFixtures`, `Provisions`, `VesselCondition`, `BoatCare`, `SaveManager`, `VesselCatalog`.
- **Holder styr på:** Intet selv; den bruger gemmeplads 2 og 3 kortvarigt og sletter dem.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan skader, redningsgebyrer, proviant eller gemte spil være forkerte.

### `tests/suites/test_upkeep_ui.gd`

**Formål:** Tjekker skærmene for bådens tilstand, proviant, bådeværftet og redning i det rigtige spil.
- **Hvad det gør:** Tjekker, at HUD'en (infolinjen på skærmen) viser skrogets tilstand, penge, mad og vand; at proviantstationen i hver kahyt åbner proviantpanelet og fører videre til købmanden; at kasserne med mad og vand tømmes, efterhånden som tiden går; at skadesmærker bliver flere, når båden slides, og forsvinder efter reparation; at bådeværftets panel bevarer sin størrelse og tilbyder Boat care til en slidt båd (I026: købmanden er sin egen butik på kajen og åbnes her direkte); og at redningsrapporten vises og sætter spillet på pause. Den tjekker også udviklerens testpanel (F10), og at spillere aldrig ser det, og at skibskatten aldrig spærrer for en station (dens tekst siger "Pet the cat").
- **Arbejder sammen med:** app-scenen, `ProvisionsMenu`, `GroceryMenu`, `ProvisionDisplay`, `BoatyardMenu`, `BoatCareMenu`, `RescueDialog`, `DevTools`, `DevTestPanel`, `ShipCompanion`, `InteractionSensor`, `TestWalkability`, `GameSession`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan skærmene for vedligehold, udviklerværktøjerne eller kattens placering opføre sig forkert.

### `tests/suites/test_vessels.gd`

**Formål:** Tjekker de fire både, bådeværftet og livet om bord på hver båd.
- **Hvad det gør:** Tjekker bådlisten (Arctic Wanderer 26 som startbåd, Wing 33, Clam 40, Frogleap 36), at hver båds dæk og kahyt har alle billedpladser, stationer og startpunkter, at man kan gå hen til hver station, og at hver båd sejler med sine egne hastigheder. Den bruger bådeværftet til at skifte båd (kun i havn), gennemgår livet om bord på hver båd (kahyt, ledsager, søkort, søvn, sejl, spiler, motor), tjekker at udskiftning med sprite-billeder (færdigtegnet grafik) aldrig ændrer kollisioner, og tjekker gemme/indlæse og gamle gemte spil. I025: når den tæller ledsagere, ser den bort fra skjulte (den tomme plads til en anden ledsager). I026: for at skifte båd går den op ad pontonens gangbro til kajen og bruger bådeværftets dør dér.
- **Arbejder sammen med:** `VesselCatalog`, `VesselVisual`, `VesselVisualProfile`, `BoatArea`, `BoatyardMenu`, `SailRig`, `ShipCompanion`, `TestWalkability`, `GameSession`, `Simulation`, `SaveManager`, app-scenen. I026: `HarbourFront`, `QuayLayout`, kaj-hjælperen.
- **Holder styr på:** Intet selv; den bruger gemmeplads 2 og 3 kortvarigt og sletter dem.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan en båd mangle dele, have stationer man ikke kan nå, sejle med forkerte hastigheder eller blive indlæst forkert.

### `tests/suites/test_visual_prototype.gd`

**Formål:** Tjekker det malede ("Illustrated") udseende af bådene og havnen.
- **Hvad det gør:** Tjekker, at ejerens kattetegninger er urørte, at Wing 33, Clam 40 og Frogleap 36 har malede billedsæt, der kan udskiftes, og at et skift mellem Illustrated og Classic kun ændrer udseendet, aldrig hvor man kan gå, eller hvad man kan bruge. Den tjekker den malede havn (København med Nyhavn som vartegn, en almindelig havn andre steder, skilte kun for tjenester der findes, ingen havn til søs), at købmanden og bådeværftet stadig åbner, og valget af Artwork i indstillingerne. Siden I021 viser Kiel udseendet som havneby med gavlhuse i stedet for en bar kaj. I026: pontonens eneste skilt er gangbroens ("To the quay"); kajen har havnens tilbud og intet andet, og købmanden og bådeværftet åbner fra deres butikker deroppe.
- **Arbejder sammen med:** `VesselCatalog`, `VesselVisual`, `SettingsManager`, `HatArt`, `HarbourArt`, `HarbourLandmark`, `HarbourFacilities`, `BoatArea`, `SettingsMenu`, `TestWalkability`, app-scenen. I026: `HarbourFront`, `QuayLayout`, kaj-hjælperen.
- **Holder styr på:** Intet selv; den efterlader grafikstilen sat til Illustrated.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan den malede grafik skjule ændringer i spillet, havnen kan vise forkerte skilte, eller grafikindstillingen bliver ikke husket.

### `tests/suites/test_voyage_persistence.gd`

**Formål:** Tjekker gemme/indlæse midt i en sejlads og meget gamle gemte spil.
- **Hvad det gør:** Gemmer under sejlads mod Kiel og tjekker, at indlæsning bringer uret, tidshastigheden, positionen, ruten, kaptajnens plads og allerede givne vejrvarsler tilbage (som ikke gentages), og at sejladsen derefter når Kiel. Den indlæser et gemt spil fra Iteration 001 og tjekker, at det opdateres fornuftigt, og tjekker at ødelagte sejladsfiler afvises uden at røre spillet, der er i gang.
- **Arbejder sammen med:** `SaveManager`, `GameSession`, `Simulation`, `WeatherFixtures`, `SettingsManager`, `SeaRouter`, `PortCatalog`.
- **Holder styr på:** Intet selv; den sletter gemmeplads 1–3, når den er færdig.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan spil gemt til søs eller gamle gemte spil måske ikke indlæses korrekt.

### `tests/suites/test_waterfront_walkthrough.gd`

**Formål:** Spiller vejen til den nye havnefront som en spiller, for at vise, at det hele kan nås i almindeligt spil (I026).
- **Hvad det gør:** Starter fra hovedmenuen (Nyt spil, Start) og går med Kaptajnen med bevægelsestasterne (styret ad en vej gennem de steder, den rigtige kollision lader fri) og E: op ad nedgangen, ad pontonen hen til gangbroen, op på kajen; tester facaderne, og at byboerne går; bestiller en kop kaffe på caféen og rejser sig med en tast; går hen til skibshandelen, ruller ned til Elektronik og køber Modern Cruiser med et klik; går ned til båden igen; trykker I for instrumenterne og finder under sejlads de tre displays i HUD'en. Kun kursen lægges i koden.
- **Arbejder sammen med:** app-scenen, `MainMenu`, `NewGameMenu`, `BoatArea`, `HarbourFront`, `HarbourLife`, `CafeMenu`, `ChandleryMenu`, `InstrumentView`, `InstrumentCluster`, `CockpitInstruments`, `GameSession`, hjælperen til gangbarhed.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; alt, der spærrer vejen til kajen, dørene eller instrumenterne, får den til at fejle.

### `tests/suites/test_windward.gd`

**Formål:** Tester sejlads op mod vinden (I027).
- **Hvad det gør:** Tester kursvalget (krydsning lige mod vinden, en halv vind sejlet lige, bomning med vinden, intet i stille vejr, bæltet der bliver smallere), hver båds egne vinkler, en rigtig krydsning i spillet (vendinger, for sejl, ærlig fremdrift, aldrig på land, ingen frem og tilbage, instrumenterne), en vending i hånden, et vindskift, det samme resultat i korte og lange skridt, en rejse midt i en halse gennem et gemt spil og et ældre gemt spil uden, et ankomstestimat der ved, at et ben mod vinden er langsomt, og de tre både side om side.
- **Arbejder sammen med:** `CourseMaker`, `Simulation`, `GameSession`, `Voyage`, `SessionState`, `InstrumentData`, `SeaRouter`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i testene.
- **Hvis du ændrer det:** Spillet ændres ikke; ændringer i sejlmodellen eller reglerne for krydsning kan få den til at fejle.

### `tests/suites/test_weather.gd`

**Formål:** Tjekker vejrsystemet: vind, kulingområder, tordenbyger og tropiske cykloner.
- **Hvad det gør:** Tjekker, at vejret er det samme for samme sted, tid og seed (startværdi for tilfældigheden), at kulingområder opstår, bevæger sig, vokser og forsvinder med uregelmæssige omrids, at tordenbyger mest hører sommeren til og kommer med vindstød i bølger, og at cykloner holder sig til deres egne have og årstider (aldrig i europæiske farvande). Med testvejr tjekker den vindretninger, hvordan vinden aftager fra kernen, alle fire både der sejler gennem en kuling, varsler der ikke gentages, ens resultat ved enhver tidshastighed, pause, samt gemme og gamle gemte spil.
- **Arbejder sammen med:** `WeatherModel`, `WeatherEvent`, `WeatherFixtures`, `WindField`, `Simulation`, `GameSession`, `SaveManager`, `VesselCatalog`, `GeoMath`.
- **Holder styr på:** Intet selv; den bruger gemmeplads 2 og 3 kortvarigt og sletter dem.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan vejret blive uforudsigeligt, dukke op forkerte steder, eller varsler kan blive gentaget.

### `tests/suites/test_weather_ui.gd`

**Formål:** Tjekker, hvordan spilleren ser og hører vejret i det rigtige spil.
- **Hvad det gør:** Med testvejr ved København tjekker den, at søkortet tegner præcis de aktive vejrområder med deres rigtige uregelmæssige omrids og etiketter, at de bliver på plads under panorering, står stille under pause og flytter sig med tiden, at fanen Weather viser farerne på kursen, og at dens forklaring dækker alle fire slags vejr, at HUD'en viser en kuling med vindstød, og at stormlyden starter og stopper, og at en storm, der opstår på kursen, vækker en sovende kaptajn én gang med årsagen vist.
- **Arbejder sammen med:** app-scenen, `WorldMap`, `MapView`, `WeatherLegend`, `WeatherStyle`, `WeatherFixtures`, `WeatherModel`, `GameSession`, `Simulation`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan vejret på søkortet, HUD'en, stormlyde eller varsler under søvn være forkerte.

### `tests/suites/test_well_run_ship.gd`

**Formål:** Tjekker sikring af ydeevnen og skærmene der viser, at tiden går (søvn, kort ved daggry og skumring, Lang passage).
- **Hvad det gør:** Tjekker, at brugerfladens dag/nat-farveskift er én billig ændring, og at gentagne ture mellem dæk, kahyt, søkort og søvn ikke får spillet til at vokse. Den tjekker datoer og ugedage, at søvn viser et tikkende ur forbi midnat og giver kontrollen tilbage (en tast springer over), at et kort ved daggry eller skumring vises én gang pr. tusmørke (ikke efter indlæsning eller over en menu), og at søkortet for Lang passage følger den rigtige rute, gennem Kielerkanalen og over datolinjen, stopper ved hændelser med "Sail on" og stopper ved en planlagt ankerplads.
- **Arbejder sammen med:** app-scenen, `TimePassage`, `DayNightWatch`, `Daylight`, `UiTheme`, `VoyageMap`, `Simulation`, `GameSession`, `SeaRouter`, `WorldMap`.
- **Holder styr på:** Intet selv; den slår tidsskærmene til under testen og fra igen.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan spillet blive langsommere over tid, eller søvn, tusmørkekort eller Lang passage kan opføre sig forkert.

### `tests/suites/test_wind.gd`

**Formål:** Tjekker baggrundsvinden, og hvor hurtigt en båd sejler i den.
- **Hvad det gør:** Tjekker reglerne for vindretning (en vestenvind kommer fra 270° og blæser mod øst; bagbord og styrbord), at vinden er den samme for samme sted, tid og seed (startværdi for tilfældigheden), holder sig mellem 0 og 45 kn, ændrer sig jævnt i rum og tid og passer med det virkelige klima (vestenvind i Atlanten, passat ud for Portugal, Meltemi, Mistral, en skiftende Østersø). Den tjekker også, at vindopslag er hurtige, og reglerne for sejlhastighed: ingen fart lige op i vinden, en topfart på omkring 10 kn, mere vind gør aldrig båden langsommere, og en lille spiler-bonus kun med vinden agterind.
- **Arbejder sammen med:** `WindField`, `PropulsionState`, `VesselProfile`, `SessionState`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan vinden føles urealistisk, eller bådene sejler med mærkelige hastigheder.

### `tests/suites/test_wind_overlay.gd`

**Formål:** Tjekker vindpilene på søkortet og knapperne til at bladre i vindens tid.
- **Hvad det gør:** Tjekker, at søkortets hurtige vindopslag giver præcis samme vind som det fulde vejr, at pile kun tegnes på havet, at et søkort der står stille ikke laver ekstra arbejde, og at små panoreringer genbruger det, der allerede er regnet ud, og at de gamle pile bliver stående, til de nye er klar. Den tjekker, at søkortet helt zoomet ud skriver "Zoom in to see wind details.", at tidsknapperne går en time ad gangen op til ±6 timer med etiketterne NOW, FORECAST og PAST uden at ændre spillet, at et hurtigt ur ikke tegner forfra hele tiden, og at lukning af søkortet stopper vindarbejdet.
- **Arbejder sammen med:** `WeatherModel`, `WindLayer`, `MapView`, `WorldMap`, `SeaRouter`, `NavGrid`, `GameSession`, `Simulation`, app-scenen.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (den gemmer skærmbilleder, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan søkortets vindpile være forkerte, langsomme eller dukke op på land.

### `tests/suites/test_wider_world.gd`

**Formål:** Tjekker I021, En større og varmere verden: de nye havne, havnenes udseende, de særlige havne, ankomstkortet, de nye fisk og tingene til kahytten.
- **Hvad det gør:** Tjekker, at de 16 nye havne findes med en sætning, en kilde og en købmand, på engelsk og dansk. Hver havn har et udseende med et færdigt billede, valgt efter hvordan stedet ser ud (New Zealand som Norge, Willemstad som Danmark). De særlige havne er netop dem med deres eget billede, og mangler et billede, vises den almindelige kaj. De nye fisk lever, hvor de virkelig lever, har billeder, rimelige priser og danske navne, og en rekord overlever et gemt spil. De tre nye ting til kahytten kan købes. Gamle gemte spil kan indlæses, at fortøje igen og igen tilføjer intet, begge sider af datolinjen virker, og ankomstkortet viser billede og ord uden at stå i vejen.
- **Arbejder sammen med:** `PortCatalog`, `HarbourLooks`, `HarbourArt`, `HarbourDressing`, `WorldMap`, `FishingCatalog`, `FishArt`, `HarbourTrades`, `SessionState`, `SeaRouter`, `SettingsManager` og app-scenen.
- **Holder styr på:** Intet af sit eget.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Kun tjekkene ændrer sig. En fejl peger på havnedata, billeder, tabellen over udseender, fiskedata eller ankomstkortet.

### `tests/suites/test_world_chart_render.gd`

**Formål:** Tjekker, at verdenskortet aldrig viser tomme huller, hvor der skulle være land.
- **Hvad det gør:** Panorerer søkortet hele vejen rundt om jorden flere gange, begge veje, zoomet ud og zoomet ind, og tjekker at kendt land (Australien, New Zealand, Japan, Alaska, Argentina, Ny Guinea, Kina, Brasilien) er tegnet overalt, hvor det er på skærmen. Den tjekker også, at skærm- og kortpositioner passer sammen hen over datolinjen, og at havne stadig kan vælges efter megen panorering.
- **Arbejder sammen med:** app-scenen, `WorldMap`, `MapView`, `GeoMath`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun i test (den gemmer et skærmbillede, når man beder om det).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, kan land forsvinde fra dele af verdenskortet, eller havne kan være svære at klikke på.

### `tests/suites/test_world_voyage.gd`

**Formål:** Den store rejsetest "Copenhagen to Paradise": sejler den mindste båd hele vejen til Tahiti.
- **Hvad det gør:** Sejler Arctic Wanderer 26 fra København via Las Palmas, Caribien og Panamakanalen over Stillehavet til Papeete, i Lang passage-tid i det rigtige vejr med fast seed. Undervejs fylder den proviant op, tjekker om båden er klar til passagen, fisker og laver mad én gang om dagen, gemmer og indlæser midt i Atlanten, går i land i havne og tjekker, at hver etape når frem, at provianten slår til, at der ikke skal redning til, og at båden aldrig hopper på tværs af kortet.
- **Arbejder sammen med:** app-scenen, `GameSession`, `Simulation`, `PassageReadiness`, `Provisions`, `SeaRouter`, `SaveManager`, `WeatherModel`, `WindField`, `PortCatalog`.
- **Holder styr på:** Intet selv; den bruger gemmeplads 3 kortvarigt og sletter den.
- **Hvornår det kører:** Kun i test (det er en af de længste kørsler).
- **Hvis du ændrer det:** Kun sikkerhedsnettet ændres; fejler testen, er en lang havsejlads måske ikke længere mulig, eller proviant, fiskeri eller gemme til søs kan være i stykker. I027: før hver passage fylder den også tanken, som en skipper ville.

## Testkørsel, målinger og værktøjer

### `tests/benchmark.gd`

**Formål:** Et stopur for hele spillet: det tager tid på indlæsning, ruteplanlægning, søkortet, en sejlads på ti dage og gemning.
- **Hvad det gør:** Planlægger en række europæiske og verdensomspændende ruter, starter spillet, åbner og lukker søkortet, sejler ti simulerede dage mod Piræus og gemmer og indlæser én gang. Det skriver én linje `BENCH {...}` og kan gemme tallene i en fil.
- **Arbejder sammen med:** `SeaRouter`, `PortCatalog`, `GameSession`, `Simulation`, `SaveManager`, søkortets `MapView`.
- **Holder styr på:** Intet selv; kun de målte tal, mens det kører.
- **Hvornår det kører:** Kun når du starter det: `godot --headless --path . res://tests/benchmark.tscn -- --out=/tmp/bench.json` (udelad `--headless` for at måle billedtider).
- **Hvis du ændrer det:** Intet i spillet ændres; kun sammenligninger med ældre måleresultater passer ikke længere.

### `tests/benchmark_105b.gd`

**Formål:** Måler hvor glat nattescenerne, fiskestangens hjul og søkortets lag kører (Revision 0.105b).
- **Hvad det gør:** Viser kahyt og dæk ved midnat (fortøjet i havn, under sejlads, for anker), en fisk på krogen, går vindens tidsnavigator igennem og fylder ankerplads-laget, mens hvert billede tidtages. Det skriver `BENCH105B {...}` og noterer version, commit (kodeversion) og en før/efter-mærkat.
- **Arbejder sammen med:** Spillets scene (`app.tscn`), `GameSession`, `Simulation`, `WindField`, søkortets vind- og ankerplads-lag.
- **Holder styr på:** Intet selv; kun resultaterne, mens det kører.
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_105b.tscn -- --out=/tmp/b.json --label=after`.
- **Hvis du ændrer det:** Intet i spillet ændres; gamle og nye resultater kan måske ikke længere sammenlignes.

### `tests/benchmark_17.gd`

**Formål:** Måler hvad søkortets vindlag og vejret bag det koster (Iteration 17).
- **Hvad det gør:** Åbner søkortet igen og igen, tidtager billeder i fire zoomniveauer med vind til og fra (stille, panorering, zoom), tidtager gentegning af vinden, en dags sejlads og en dags Lang passage samt gemning. Det skriver `BENCH17 {...}`.
- **Arbejder sammen med:** `MapView`, `WorldMap`, `WeatherModel`, `Simulation`, `GameSession`, `SaveManager`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun når du starter det: `godot --headless --path . res://tests/benchmark_17.tscn -- --out=/tmp/b.json` (uden `--headless` for rigtige billedtider).
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/benchmark_18.gd`

**Formål:** Måler billedtider i de scener, Iteration 18 ændrede (natlys, fiskestangens hjul, vindens tidsnavigator).
- **Hvad det gør:** Samme scener som 0.105b-målingen, men uden ankerplads-laget og uden at notere commit og mærkat. Skriver `BENCH18 {...}`.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `Simulation`, `WindField`, søkortets vindlag.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_18.tscn -- --out=/tmp/b18.json`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/benchmark_wrs.gd`

**Formål:** En lang "kører skibet godt?"-måling: hak og langsom vækst under søvn, solopgang/solnedgang, søkortet, Lang passage og lange spilsessioner.
- **Hvad det gør:** Lader kaptajnen gå rundt, kører dag/nat-skift ved 20x fart, sover hen over midnat, sejler, kører Lang passage og gentager 20 runder af almindelige handlinger, mens billeder tidtages og "hak" (billeder over 50 ms) tælles. Efter hvert trin tælles også noder, signal-forbindelser, lydafspillere og mellemlagre, så lækager viser sig som en tendens. Ekstra tilstande: `--presented` og `--turbo`.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `Simulation`, `Daylight`, `UiTheme`, `WeatherModel`, `SeaRouter`, `SessionLog`, `SaveManager`.
- **Holder styr på:** Intet selv.
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_wrs.tscn -- --out=/tmp/w.json --label=before`.
- **Hvis du ændrer det:** Intet i spillet ændres; før/efter-sammenligninger forudsætter, at den forbliver den samme.

### `tests/cabin_light_18.gd`

**Formål:** Måler hvor lys kahytten er om natten på alle fire både, så lyset kan sammenlignes før og efter en ændring.
- **Hvad det gør:** For hver båd, i København ved lokal midnat, fotograferer den kahytten uden skærmpanelerne og skriver lysstyrken ved lamperne, i gulvets hjørner, hen over gulvet og på kaptajnen.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `BoatLighting`, `BoatArea`.
- **Holder styr på:** Intet selv; gemmer PNG-billeder i den valgte mappe.
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/cabin_light_18.tscn -- --out=DIR --label=before`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/companion_animation_preview.gd`

**Formål:** Viser alle ledsagernes klip spille side om side, som dokumentation for animationerne fra I024.
- **Hvad det gør:** Én række pr. slags (kat, hund, papegøje) og én celle pr. klip, hver en lille forhåndsvist ledsager i spillets størrelse, forstørret; et klip, der spilles én gang, starter forfra hvert andet sekund. Med `--out` gemmer den nogle øjebliksbilleder af gitteret og lukker.
- **Arbejder sammen med:** `CompanionState`, `CompanionVisualSet`, `ShipCompanion` (som forhåndsvisning).
- **Holder styr på:** Intet; den skriver PNG-filer, når man beder om det.
- **Hvornår det kører:** Kun når du starter det: i editoren (F6) eller tegnet med `res://tests/companion_animation_preview.tscn -- --out=DIR`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/helpers/art_fixtures.gd`

**Formål:** Laver iøjnefaldende pink-og-gule testbilleder, der står i stedet for rigtig grafik i Sprite Workshop-testene.
- **Hvad det gør:** Tegner et ternet erstatningsbillede i den størrelse, grafiklisten forventer, kan skrive en bevidst ødelagt fil, kan se om en tekstur er testbilledet, fjerner det igen og finder erstatnings-PNG'er, der er blevet efterladt.
- **Arbejder sammen med:** `ArtworkResolver` (grafiklisten og mappen); bruges af `test_sprite_workshop`, `restart_105b` og `screenshots_105b`.
- **Holder styr på:** Intet selv; filerne, den skriver, skal testen fjerne igen.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Sprite Workshop-testene kan fejle, eller testbilleder kan blive liggende i grafikmappen.

### `tests/helpers/quay.gd`

**Formål:** Lader en test nå havnens butikker, som en spiller gør, op ad gangbroen til kajen (I026).
- **Hvad det gør:** Siden forretningerne flyttede op på kajen, går en test, der skal bruge købmanden, bådeværftet eller en håndværker, op ad pontonens gangbro (og viser først dækket, hvis Kaptajnen er under dæk), stiller sig ved døren på kajen og trykker E der. Som standard bruges døren uanset hvad uret siger, til test, der ikke handler om åbningstiderne. Den venter også, til skærmskiftet er faldet til ro.
- **Arbejder sammen med:** `HarbourFront`, `BoatArea`, `BusinessHours`, `App`; bruges af `test_boat_care`, `test_denmark_views`, `test_harbour_life`, `test_living`, `test_vessels` og `test_visual_prototype`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Alle test, der besøger en butik, kan fejle.

### `tests/helpers/reel.gd`

**Formål:** Lader en test hale en fisk ind gennem det rigtige hjul på fiskestangen, som en spiller med perfekt timing.
- **Hvad det gør:** Drejer nålen rundt, sætter den midt i (eller i kanten af) målbuen og trykker, indtil indhalingen er slut. Fortæller om fangsten kom om bord.
- **Arbejder sammen med:** `FishingMenu`, `ReelTiming`; bruges af fisketestene, `restart_18` og `screenshots_18`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Fisketestene kan begynde at miste fiskene.

### `tests/helpers/view_fit.gd`

**Formål:** Tjekker, at nærbillederne passer på skærmen i alle de størrelser, spillet lover (I026).
- **Hvad det gør:** Åbner hver visning, en test giver den, ved 1280×720 og 1024×768, ved 100 % og 130 % brugerflade, på engelsk og dansk, måler dens panel (med rammens margen, når den er indrammet som en genstand, og som den ser ud, når åbningsanimationen er faldet til ro) og lister alle visninger, der går uden for skærmen. Bagefter sætter den vinduet, sproget og brugerfladens størrelse tilbage.
- **Arbejder sammen med:** `FocusFrame` (dens margen), `SettingsManager` (sprog og brugerfladens størrelse), appens stak af vinduer.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Testene af nærbillederne kan bestå eller fejle anderledes.

### `tests/helpers/walkability.gd`

**Formål:** Finder ud af, hvor kaptajnen faktisk kan gå på dækket eller i kahytten, og hvorfra hver station kan bruges.
- **Hvad det gør:** Breder sig ud fra et startpunkt i et gitter og prøver kaptajnens rigtige kropsstørrelse mod de rigtige vægge; måler så, hvor tæt hvert sted er på stationer og inventar.
- **Arbejder sammen med:** `BoatArea`, `Interactable`, `BoatFixture`; bruges af `test_vessels`, `test_visual_prototype`, `test_solar_panels`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Kun i test.
- **Hvis du ændrer det:** Test af bådenes indretning kan bestå eller fejle forkert (fx påstå at en station ikke kan nås).

### `tests/pacing_18.gd`

**Formål:** Tæller hvor tit Lang passage stopper på en havkrydsning, med og uden fiskeri.
- **Hvad det gør:** Sejler København til Las Palmas i op til 12 spildage tre gange (uden fiskeri; med slæbefiskeri og stop ved hvert bid; stop kun for fisk, der er værd at beholde) og skriver en `PACE`-linje med årsagerne til stop.
- **Arbejder sammen med:** `GameSession`, `Simulation`, `FishingState`, `WindField`.
- **Holder styr på:** Intet.
- **Hvornår det kører:** Kun når du starter det: `godot --headless --path . res://tests/pacing_18.tscn`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/restart_105b.gd`

**Formål:** Tjekker at ankring og udskiftet grafik overlever, at spillet lukkes og åbnes igen (Revision 0.105b).
- **Hvad det gør:** I separate kørsler gemmer den en båd for anker ud for Antigua og en på Magic Anchor ude på åbent hav, indlæser dem igen og tjekker, at alt forløber præcis ens; den installerer også et testbillede af katten, tjekker at en ny kørsel bruger det, fjerner det og tjekker at originalen er tilbage.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `SaveManager`, `MagicAnchorDeployment`, `ArtworkResolver`, `TestArtFixtures`.
- **Holder styr på:** Sin egen testmappe til gemte spil og en fil med forventninger, som fjernes til sidst.
- **Hvornår det kører:** Kun når du starter det, som separate kørsler: `godot --headless --path . res://tests/restart_105b.tscn -- --phase=write`, derefter `--phase=read`; for grafikken: `--phase=art_install`, `godot --headless --path . --import`, `--phase=art_read`, `--phase=art_after`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/restart_17.gd`

**Formål:** Tjekker at et spil gemt under sejlads og indlæst i et nyt spil sætter alt præcis tilbage (Iteration 17).
- **Hvad det gør:** Gemmer tre gange under sejlads (på dækket ved stævnen, i kahytten, i dårligt vejr) og sejler hver gang seks timer videre; i en anden kørsel indlæses hvert gemt spil, og kaptajnens plads, båden, tiden, ruten og vejret tjekkes, og at de næste seks timer går på samme måde.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `Simulation`, `SaveManager`.
- **Holder styr på:** Sin egen testmappe til gemte spil og en fil med forventninger.
- **Hvornår det kører:** Kun når du starter det, to gange: `godot --headless --path . res://tests/restart_17.tscn -- --phase=write`, derefter `-- --phase=read`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/restart_18.gd`

**Formål:** Tjekker at fiskeri, ankerpladser og sejltrim overlever at blive gemt og indlæst i en ny start (Iteration 18).
- **Hvad det gør:** Gemmer tre situationer: en køleboks med beholdte og genudsatte fisk, en båd for anker på en ankerplads fra søkortet med ledsageren på dækket, og en båd under sejlads med håndtrimmede sejl. En anden kørsel indlæser dem og tjekker hver detalje, og at sejladserne fortsætter præcis som før.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `Simulation`, `SaveManager`, `FishingCatalog`, `WorldMap`, hjælperen `reel.gd`.
- **Holder styr på:** Sin egen testmappe til gemte spil og en fil med forventninger.
- **Hvornår det kører:** Kun når du starter det, to gange: `godot --headless --path . res://tests/restart_18.tscn -- --phase=write`, derefter `-- --phase=read`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/restart_check.gd`

**Formål:** Det oprindelige "luk og åbn igen"-tjek: indstillinger og et rigt gemt spil skal komme tilbage efter en genstart.
- **Hvad det gør:** Første kørsel: ændrer indstillinger, sejler til Göteborg, mister og erstatter kaptajnshuen, udgiver en rejseopdatering, skifter til trimaranen, sætter kurs mod Kiel og gemmer. Anden kørsel: tjekker indstillinger, position, sejlads, Logbogen, ry, kaptajnshuen, vejret, penge, proviant, bådenes stand og diagnoseloggen.
- **Arbejder sammen med:** `SettingsManager`, `SaveManager`, `GameSession`, `Simulation`, `WeatherModel`, `SessionLog`.
- **Holder styr på:** Sin egen indstillingsfil, testmappe til gemte spil, logmappe og forventningsfil, som alle ryddes op efter læsningen.
- **Hvornår det kører:** Kun når du starter det, to gange: `godot --headless --path . res://tests/restart_check.tscn -- --phase=write`, derefter `-- --phase=read`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/screenshots_105b.gd`

**Formål:** Tager billedbeviserne for Revision 0.105b: ankerpladser i udlandet, nat for anker og hvad der sker, når udskiftet grafik fjernes.
- **Hvad det gør:** Ankrer ud for Antigua og (med Magic Anchor) ud for Madeira, viser natten for anker og installerer, fjerner og fejldimensionerer et erstatningsbillede af ankerbøjen; hvert tilfælde tjekkes og fotograferes.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `AnchorSite`, `ArtworkResolver`, `TestArtFixtures`.
- **Holder styr på:** Intet; skriver PNG'er til den angivne mappe.
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_105b.tscn -- --out=DIR`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/screenshots_16.gd`

**Formål:** Tager de tyve gennemgangsbilleder af "The World Awaits" (Iteration 16): verdenssøkortet, lange ruter og havsejladser.
- **Hvad det gør:** Fotograferer søkortet mange steder og i mange zoomniveauer, flere lange ruter, panelet til Lang passage, en ankomst til Papeete og landgang, og sætter tre zoombilleder sammen til ét.
- **Arbejder sammen med:** Spillets scene, `WorldMap`, `MapView`, `GameSession`, `Simulation`.
- **Holder styr på:** Intet; skriver i `docs/screenshots/iteration16/` i projektet.
- **Hvornår det kører:** Kun når du starter det, med skærm: `godot --path . --resolution 1600x900 res://tests/screenshots_16.tscn`.
- **Hvis du ændrer det:** Intet i spillet; kun dokumentationsbillederne.

### `tests/screenshots_17.gd`

**Formål:** Tager de tredive gennemgangsbilleder af "Let There Be Light" (Iteration 17): lyset døgnet rundt, vejret og drømmekortet (Dreamer's Map).
- **Hvad det gør:** Fotograferer kahytter og dæk ved middag, skumring og nat, drømmekortet, søkortet, sejladsvisninger, regn og lyn samt ankomst til kaj. `--only=` vælger et udsnit. I026: billedet af kortplotteren viser rorets plotter tæt på (`PlotterView`), da plotteren ikke længere er et HUD-panel.
- **Arbejder sammen med:** Spillets scene, `GameSession`, `Simulation`, `Daylight`, `WeatherFixtures`, `PlotterView`, `CaptainsLogMenu`.
- **Holder styr på:** Intet; skriver i `docs/screenshots/iteration17/`.
- **Hvornår det kører:** Kun når du starter det, med skærm: `godot --path . --resolution 1600x900 res://tests/screenshots_17.tscn [-- --only=cabin]`.
- **Hvis du ændrer det:** Intet i spillet; kun dokumentationsbillederne.

### `tests/screenshots_18.gd`

**Formål:** Tager fiskebillederne til Iteration 18: hjulet på fiskestangen, fangster, fiskegrafik, trofætavlen og at trække en ankerplads på søkortet.
- **Hvad det gør:** Viser bid og indhaling (perfekt og forbier), beholdte og genudsatte fangster, køleboksen og indstillingerne for hvad der beholdes, hver fisks grafik, en animationsstribe og et ark med alle arter, og til sidst et rutepunkt for ankerplads, der trækkes.
- **Arbejder sammen med:** Spillets scene, `FishingMenu`, `FishingCatalog`, `FishPortrait`, `WorldMap`, hjælperen `reel.gd`.
- **Holder styr på:** Intet; skriver PNG'er til den angivne mappe.
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_18.tscn -- --out=DIR`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/screenshots_chartroom.gd`

**Formål:** Fotograferer alle spillets hovedskærme om dagen og om natten, så Chartroom-udseendet kan tjekkes.
- **Hvad det gør:** Ved lokal middag og midnat viser den hovedmenuen, dæk, kahyt, trofætavlen, bådpleje, butikkerne, Logbogen, søvn, kabys, søkort, sejlads, fiskeri, drømmekortet, pause og indstillinger og gemmer et billede af hver.
- **Arbejder sammen med:** Spillets scene, `SettingsManager`, `UiTheme`, `GameSession`, `FishingCatalog`.
- **Holder styr på:** Intet; bruger en test-indstillingsfil og skriver PNG'er (som standard i `docs/screenshots/chartroom_ui`).
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_chartroom.tscn -- --out=DIR [--only=day|night]`.
- **Hvis du ændrer det:** Intet i spillet ændres.

### `tests/screenshots_harbours_i025.gd`

**Formål:** Tager I025-billederne af havnen omkring den fortøjede båd for at vise byen og nabobådene i deres rigtige størrelse.
- **Hvad det gør:** Starter et nyt spil, skifter eventuelt til en anden båd og fortøjer i hver valgt havn (som standard København, Kiel, Napoli, Dingle, Dakar og Bergen) kl. 11.30 lokal tid med en jævn vind, og fotograferer så dækket: byens størrelse, arkitektur og farver efter egn og nabobådenes størrelse.
- **Arbejder sammen med:** app-scenen, `GameSession`, `PortCatalog`, `SessionState`, `UiTheme`, `WindField`, `WeatherModel`, `SeaSurface`, `Simulation`.
- **Holder styr på:** Intet; den skriver PNG-filer (kun testgemmer og testindstillinger, aldrig spillerens egne).
- **Hvornår det kører:** Kun i hånden, med en rigtig skærm eller Xvfb: `res://tests/screenshots_harbours_i025.tscn -- --out=DIR [--ports=kiel,naples] [--vessel=ID] [--suffix=after]`.
- **Hvis du ændrer det:** Kun skærmbillederne ændres.

### `tests/screenshots_i021.gd`

**Formål:** Tager billederne til I021-rapporten: hvert udseende af havnene, de særlige havne, ankomstkortet og stjernen på søkortet.
- **Hvad det gør:** Fortøjer båden i en havn med hvert af de ni udseender og i hver særlig havn og fotograferer dækket. Den viser ankomstkortet (på engelsk og på dansk) og åbner så søkortet om dagen og om natten med Valletta og Symi valgt, og Drømmerens kort.
- **Arbejder sammen med:** App-scenen, `HarbourLooks`, `PortCatalog`, `GameSession`, `UiTheme`, `SettingsManager`, `WindField`.
- **Holder styr på:** Intet; den skriver PNG-filer.
- **Hvornår det kører:** Kun når du starter det, med en rigtig skærm eller Xvfb: `res://tests/screenshots_i021.tscn -- --out=DIR`.
- **Hvis du ændrer det:** Kun skærmbillederne ændrer sig.

### `tests/screenshots_i024.gd`

**Formål:** Tager billederne til I024-rapporten fra det kørende spil.
- **Hvad det gør:** Fotograferer de tre ledsagere om bord, papegøjen på sin pind og i flugt, en ledsager i land og afgangen, der venter på den, opvågningen med ledsageren ved køjen, Kaptajnen der taler på en lang passage, og laptoppen i kahytten: på bordet, åben på Hjem, bedrifterne med låste mærker, en detalje med hvornår og hvor, postkortværkstedet, en kategori, rejsehistorikken og bedrifterne på dansk. De fleste billeder får også et nærbillede.
- **Arbejder sammen med:** App-scenen, `GameSession`, `CompanionState`, `ShipCompanion`, `LaptopView`, `UiTheme`, `SettingsManager`, `WindField`.
- **Holder styr på:** Intet; den skriver PNG-filer (kun testens gemte spil og indstillinger, aldrig spillerens egne).
- **Hvornår det kører:** Kun når du starter det, med en rigtig skærm eller Xvfb: `res://tests/screenshots_i024.tscn -- --out=DIR [--only=PREFIX]`.
- **Hvis du ændrer det:** Kun skærmbillederne ændrer sig.

### `tests/screenshots_i026_harbour.gd`

**Formål:** Tager I026-billederne af kajen: butiksfacaderne, deres diske, åbningstiderne på dørene, folkene på forskellige tider, caféen og egnsvarianter.
- **Hvad det gør:** Fortøjer i København og andre havne på valgte tidspunkter og fotograferer pontonens gangbro, kajen ved ankomsten, hver butiks indgang og disk, opslagstavlen, folk der går rundt midt på dagen, en lukket skibshandel om morgenen med tilbuddet om at vente, liv om morgenen, caféen med gæster, Kaptajnen med en kop kaffe (og en ledsager, der hviler ved bordet), en handlende der låser af om aftenen, kajen om natten og kajer i andre egne. `--shots=` vælger et udsnit.
- **Arbejder sammen med:** app-scenen, `HarbourFront`, `QuayLayout`, `GameSession`, `SessionState`, `Simulation`, `UiTheme`.
- **Holder styr på:** Intet; den skriver PNG-filer (kun testgemmer og testindstillinger, aldrig spillerens egne).
- **Hvornår det kører:** Kun i hånden, med en rigtig skærm eller Xvfb: `res://tests/screenshots_i026_harbour.tscn -- [--out=DIR] [--shots=a,b]`.
- **Hvis du ændrer det:** Kun skærmbillederne ændres.

### `tests/screenshots_i026_instruments.gd`

**Formål:** Tager I026-billederne af den maritime elektronik fra det kørende spil.
- **Hvad det gør:** Fotograferer HUD'en under sejlads før og efter ændringen, de tre instrumentpakker under sejlads om dagen og om natten og i kahytten, hvert nærbillede af instrumenterne, kortplotteren tæt på, elektronikken ved roret på alle både og skibshandelens afdeling for elektronik. `--only=` vælger billeder efter begyndelsen af navnet.
- **Arbejder sammen med:** app-scenen, `GameSession`, `InstrumentPackage`, `InstrumentView`, `PlotterView`, `ChandleryMenu`, `WindField`, `UiTheme`.
- **Holder styr på:** Intet; den skriver PNG-filer (kun testgemmer og testindstillinger).
- **Hvornår det kører:** Kun i hånden, med en rigtig skærm eller Xvfb: `res://tests/screenshots_i026_instruments.tscn -- [--out=DIR] [--only=PREFIX]`.
- **Hvis du ændrer det:** Kun skærmbillederne ændres.

### `tests/screenshots_i026_motion.gd`

**Formål:** Tager nummererede billeder af I026 i bevægelse, som et lille værktøj sætter sammen til filmstrimler.
- **Hvad det gør:** Gemmer billeder (`film_NAME_NN.png`) til `tools/qa/film_strip.py`: det samme stykke af Københavns kaj gennem en dag (morgen, middag, aften, nat), folk der går og standser midt på dagen med et halvt sekunds mellemrum, en bestilling på caféen, at sætte sig og drikke, at gå hen til skibshandelens dør og ind, at bladre i Modern Cruisers displays og logbogen, der bringes tæt på. `--films=` vælger et udsnit. Med `--probe=PATH` måler den i stedet billedtider på dækket og på kajen (middag og kajen ved 20×) og skriver dem som JSON.
- **Arbejder sammen med:** app-scenen, `HarbourFront`, `HarbourLife`, `CafeMenu`, `InstrumentView`, `FocusFrame`, `GameSession`, `Simulation`.
- **Holder styr på:** Intet; den skriver PNG-filer (kun testgemmer og testindstillinger, aldrig spillerens egne).
- **Hvornår det kører:** Kun i hånden, med en rigtig skærm eller Xvfb: `res://tests/screenshots_i026_motion.tscn -- [--out=DIR] [--films=a,b]`.
- **Hvis du ændrer det:** Kun filmbillederne ændres.

### `tests/screenshots_i027.gd`

**Formål:** Tager de billeder, der viser I027 virke i det kørende spil.
- **Hvad det gør:** Starter et nyt spil, sætter sejl mod Göteborg med vinden lige imod og fotograferer båden, der krydser på dækket, instrumenterne med halsen og fremdriften, kortplotteren, dækket efter en vending i hånden og handlingshjulet med "Vend nu". `--shots=` vælger nogle. Billeder fra trin 2 (10-13, docs/screenshots/i027/tier2): tankanlæggets pumpe på kajen, dens menu, havnekontorets driftsomkostninger og hjulets Motor op mod vinden.
- **Arbejder sammen med:** app-scenen, `Simulation`, `GameSession`, `InstrumentView`, `PlotterView`, handlingshjulet.
- **Holder styr på:** Intet; den skriver PNG-filer (kun testgemmer og testindstillinger).
- **Hvornår det kører:** Kun i hånden, med en rigtig skærm eller Xvfb: `res://tests/screenshots_i027.tscn -- [--out=DIR] [--shots=a,b]`.
- **Hvis du ændrer det:** Kun billederne ændres.

### `tests/one_clock_sea_trial.gd`

**Formål:** En prøvetur på fem minutter, der måler, hvor tiden går, når uret kører hurtigere end 1x, især ved daggry, skumring, om natten og i havn (Operation One Clock).
- **Hvad det gør:** Starter et spil med kladdegemninger, sejler og fortøjer på faste steder og kører hvert scenarie (dag og nat ved 1x og 20x, skumring med og uden datokortet, søkortet i skumringen, havnen om natten med og uden lys og et minut ved 20x). For hvert billede tager den tid på simuleringen, omfarvningen af brugerfladen, bådens lys og daggry/skumrings-vagten hver for sig og på tegningen. Til sidst viser den en tabel, kopierer den til udklipsholderen og gemmer den som `one_clock_sea_trial.txt`.
- **Arbejder sammen med:** Spilscenen, `GameSession`, `Simulation`, `UiTheme`, `DayNightWatch`, `BoatLighting`, `TimePassage`, `Daylight`.
- **Holder styr på:** Intet selv; spillerens gemninger og indstillinger bruges aldrig.
- **Hvornår det kører:** Kun når man starter det med vilje: åbn `tests/one_clock_sea_trial.tscn` i Godot og tryk F6, eller (udviklere) `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/one_clock_sea_trial.tscn -- --all --out=/tmp/one_clock.json`.
- **Hvis du ændrer det:** Intet i spillet ændres; sammenligninger med tidligere prøveture kræver, at scenarierne er de samme.

### `tests/test_runner.gd`

**Formål:** Spillets automatiske testkører: den kører alle 85 testsamlinger og fortæller, hvor mange tjek der bestod.
- **Hvad det gør:** Flytter gemte spil, indstillinger og logs over i midlertidige testfiler, slår søvn- og daggry-animationerne fra, vælger engelsk og vindstille, og kører hver testsamling efter tur. Den giver også testsamlingerne fælles værktøjer: tjek, ventetid, tastetryk, museklik, at gå om bord på en båd, at sætte vinden, at planlægge ruter og skærmbilleder. Siden I021 kører den også suiten om den større verden. Siden I022 kører den I022-testsættet og lader testsættene sejle alle både uden at købe dem. I022: den slår Skipperskolens tilbud og tips fra for de andre testsæt. Den kører også testsættet for kahytsvinduerne. Den kører også Steady Hands-testsættet for brugerfladen. Den kører også testsættet for de gyldne havne. I024: den kører også testsættet for The Company We Keep. I025: den kører også testsættet for A Little More Room Aboard, lige før testsættet for hele spillets forløb, som stadig er det sidste. I026: den kører også testsættene for de levende havne, tingene i kahytten og den maritime elektronik, lige før A Little More Room Aboard. I026 tilføjede også gennemgangen af havnefronten til listen. I027 tilføjede testsamlingen om at sejle op mod vinden. I027 trin 2 tilføjede testsamlingen om brændstof og driftsomkostninger; de ældre testsamlinger, der sejler langt for motor i vindstille, kører med en motor, der ikke bruger brændstof, og alle andre har den rigtige tank.
- **Arbejder sammen med:** Alle testsamlinger i `tests/suites/`, plus `SaveManager`, `SettingsManager`, `SessionLog`, `TimePassage`, `WindField`, `Simulation`, `GameSession`.
- **Holder styr på:** Antal beståede/fejlede tjek og listen over fejl.
- **Hvornår det kører:** Når du starter det, eller i automatik: `godot --headless --path . res://tests/test_runner.tscn` (valgmuligheder efter `--`: `--only=navn`, `--skip=navn`, `--screenshots=MAPPE`).
- **Hvis du ændrer det:** Alle test kan blive påvirket; en ny testsamling kører først, når den er tilføjet til listen her.

### `tools/art/capture_previews.gd`

**Formål:** Fotograferer den grafik, spillet tegner i kode (kahytsting, sejl, søkortets mærker), så det illustrerede katalogs kontaktark viser præcis det, spilleren ser.
- **Hvad det gør:** Viser hver kahytsting på en kahytsgulvfarve; starter så et spil med kladdegemninger og fotograferer for hver af de fire både båden fortøjet i København, kahytten med alle kahytsting og båden for sejl; til sidst klipper den søkortets mærker ud (havn, valgt havn, destination med messingstjernen, båden, et waypoint, drømmekortets nåle) om dagen og om natten. Værktøjet tegner intet selv.
- **Arbejder sammen med:** `App`, `GameSession`, `CabinDecor`, `HarbourTrades`, `WindField`, `Simulation`, `MapView`; `tools/art/build_contact_sheets.py` sætter billederne på arkene.
- **Holder styr på:** Intet; skriver PNG'er i `docs/art/previews/` (kladdegemninger og -indstillinger, aldrig spillerens).
- **Hvornår det kører:** Kun når du starter det, med skærm: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tools/art/capture_previews.tscn -- --out=docs/art/previews`.
- **Hvis du ændrer det:** Kun katalogets forhåndsbilleder ændres, ikke spillet.

### `tools/build_theme.gd`

**Formål:** Bygger spillets fælles udseende (farver, skrifttyper, knapper, paneler) som en temafil.
- **Hvad det gør:** Laver temaet i marineblå, blågrøn, creme og messing i kode, med Barlow-skrifterne og den håndskrevne overskriftsskrift, og gemmer det som `assets/ui/next_harbor_theme.tres`.
- **Arbejder sammen med:** Skrifterne i `assets/fonts/`; resultatet er projektets tema, som alle skærme bruger.
- **Holder styr på:** Intet; skriver temafilen.
- **Hvornår det kører:** Kun når du starter det: `godot --headless --path . -s res://tools/build_theme.gd` (kør `godot --headless --path . --import` først på en frisk kopi af projektet).
- **Hvis du ændrer det:** Når det er kørt igen, ser alle menuer, knapper og paneler i spillet anderledes ud.

### `tools/export_branding.gd`

**Formål:** Laver spillets logo- og ikontegninger (SVG) om til PNG-billeder i flere størrelser.
- **Hvad det gør:** Tegner hver branding-SVG i de angivne højder og gemmer dem i `assets/branding/png/`. Siden I022 eksporteres logoet også i 240 pixels højde til Godots opstartsbillede.
- **Arbejder sammen med:** SVG'erne i `assets/branding/`; indlæsningsskærmen bruger to af PNG'erne.
- **Holder styr på:** Intet; skriver PNG-filer.
- **Hvornår det kører:** Kun når du starter det: `godot --headless --path . -s res://tools/export_branding.gd`.
- **Hvis du ændrer det:** De eksporterede logoer ændres, også logoet på indlæsningsskærmen.

### `tools/navigation/world_land_to_res.gd`

**Formål:** Laver verdens landformer om til en fil, der indlæses hurtigt, så søkortet åbner hurtigt.
- **Hvad det gør:** Læser `data/navigation/world/land.json`, omregner kystlinjer og småøer til søkortets koordinater og gemmer dem som `data/navigation/world/land.res`.
- **Arbejder sammen med:** `MapProjection`, `WorldLand`; `MapView` indlæser resultatet.
- **Holder styr på:** Intet; skriver ressourcefilen.
- **Hvornår det kører:** Kun når du starter det, efter `build_world.py`: `godot --headless --path . --script tools/navigation/world_land_to_res.gd`.
- **Hvis du ændrer det:** Landet, der tegnes på søkortet, kan ændre sig eller mangle.

### `tools/vessels/render_art_templates.gd`

**Formål:** Laver tegneskabeloner til hver båd, så kunstnere kan se, hvor vægge, stationer og startpunkter er.
- **Hvad det gør:** For hver båds dæk og kahyt gemmer den et referencebillede (den nuværende grafik med kendemærker tegnet ovenpå) og et guidebillede (kun kendemærkerne, gennemsigtigt) i bådens `templates`-mappe.
- **Arbejder sammen med:** `VesselCatalog`, `VesselVisual`, `BoatFixture`, `Interactable`.
- **Holder styr på:** Intet; skriver PNG'er.
- **Hvornår det kører:** Kun når du starter det, med skærm: `godot --path . --rendering-driver opengl3 res://tools/vessels/render_art_templates.tscn`.
- **Hvis du ændrer det:** Kun kunstnerskabelonerne ændres, ikke spillet.

### `tools/weather/measure_wind_variation.gd`

**Formål:** Måler hvor meget vinden ændrer sig fra et trin i søkortets tidsnavigator for vind til det næste.
- **Hvad det gør:** Tager prøver af vejret i gitre over fem sejlområder på mange tidspunkter og skriver, hvor meget fart og retning ændrer sig efter 30 minutter til 6 timer, både for den faktiske vind og for prognosen.
- **Arbejder sammen med:** `WeatherModel`.
- **Holder styr på:** Intet; skriver kun tal ud.
- **Hvornår det kører:** Kun når du starter det: `godot --headless --path . -s res://tools/weather/measure_wind_variation.gd`.
- **Hvis du ændrer det:** Intet i spillet ændres.
