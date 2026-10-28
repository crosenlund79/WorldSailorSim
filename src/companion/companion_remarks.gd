class_name CompanionRemarks
extends RefCounted
## A kind word when the Captain pets the ship's companion: a short remark
## that fits the animal (cat or dog), in the game's current language.
##
## The companion's identity is read from the authoritative CompanionState
## (identity()), never kept here. Since I024 a companion has the name and
## gender ("female", "male" or "other") the player chose, both optional:
## lines with the name are chosen when it has one, and the dog's lines say
## "girl" or "boy" where natural. A name is inserted exactly as chosen
## (Danish letters, punctuation and all). No name is ever made up.
##
## I024 (The Company We Keep): this is the one place for everything the
## companion "says" or what is said about it - the petting remarks, the
## shore and recall lines, the wake-up observations after a night's sleep,
## and the Captain's talk on long passages with the animal's response (a
## line and the animation clip that goes with it). Nothing here keeps state
## or awards anything; callers decide when.
##
## Lines rotate (remark(identity, turn)): consecutive turns never give the
## same line. Translated when they are shown (Loc), so a language switch
## applies to the next remark. The cooldown that keeps the remarks rare lives
## with the companion node (ShipCompanion.take_remark()).

const GENDER_FEMALE := CompanionState.GENDER_FEMALE
const GENDER_MALE := CompanionState.GENDER_MALE
const GENDER_OTHER := CompanionState.GENDER_OTHER

## Without a name. By kind.
const UNNAMED := {
	CompanionState.KIND_CAT: [
		"You're looking especially cozy today.",
		"What a lovely little purr.",
		"There's my favourite little sailor.",
		"The ship's cat, on watch as ever.",
	],
	CompanionState.KIND_DOG: [
		"Who's a good dog?",
		"There's my faithful first mate!",
		"Best crew on the seven seas, that's you.",
		"That tail could power the boat.",
	],
	CompanionState.KIND_PARROT: [
		"Hello, little lookout.",
		"Those are very fine feathers.",
		"Easy there, bright eyes.",
	],
}
## With a name (%s), for every gender.
const NAMED := {
	CompanionState.KIND_CAT: [
		"You're looking especially cozy today, %s.",
		"What a lovely little purr, %s.",
		"The ship's cat, on watch as ever. Good %s.",
	],
	CompanionState.KIND_DOG: [
		"Who's the best companion, %s?",
		"That tail could power the boat, %s.",
	],
	CompanionState.KIND_PARROT: [
		"Hello, %s. Keeping watch?",
		"Very fine feathers today, %s.",
		"There's my little lookout, %s.",
	],
}
## With a name (%s), added for a gender where it reads naturally.
const NAMED_BY_GENDER := {
	CompanionState.KIND_CAT: {
		GENDER_FEMALE: ["There's my lovely little sailor, %s."],
		GENDER_MALE: ["There's my handsome little sailor, %s."],
	},
	CompanionState.KIND_DOG: {
		GENDER_FEMALE: ["Who's a good girl, %s?"],
		GENDER_MALE: ["There's my good boy, %s!"],
	},
	CompanionState.KIND_PARROT: {
		GENDER_FEMALE: ["Who's a clever girl, %s?"],
		GENDER_MALE: ["Who's a clever boy, %s?"],
	},
}
## Without a name, added for a gender.
const UNNAMED_BY_GENDER := {
	CompanionState.KIND_DOG: {
		GENDER_FEMALE: ["Who's a good girl?"],
		GENDER_MALE: ["Who's a good boy?"],
	},
}


## {"kind", "name", "gender"} of a companion, from its state. A field the
## state does not (yet) have is empty.
static func identity(companion: CompanionState) -> Dictionary:
	if companion == null:
		return {"kind": CompanionState.DEFAULT_KIND, "name": "", "gender": &""}
	var name: Variant = companion.get("name") if "name" in companion else ""
	var gender: Variant = companion.get("gender") if "gender" in companion else &""
	return {"kind": companion.kind, "name": String(name).strip_edges() if name is String else "",
		"gender": StringName(gender) if gender is String or gender is StringName else &""}


## The English lines (message keys) for an identity, in a fixed order.
static func lines(who: Dictionary) -> Array[String]:
	var kind: StringName = who.get("kind", CompanionState.DEFAULT_KIND)
	if not kind in CompanionState.KINDS:
		kind = CompanionState.DEFAULT_KIND
	var gender: StringName = who.get("gender", &"")
	var named := String(who.get("name", "")) != ""
	var out: Array[String] = []
	out.assign((NAMED if named else UNNAMED)[kind])
	var extra: Dictionary = (NAMED_BY_GENDER if named else UNNAMED_BY_GENDER).get(kind, {})
	out.append_array(extra.get(gender, []))
	return out


## The remark for turn `turn` (0, 1, 2, …), translated, with the name in.
## Consecutive turns never repeat a line.
static func remark(who: Dictionary, turn: int) -> String:
	var choices := lines(who)
	var line := Loc.t(choices[posmod(turn, choices.size())])
	return line % String(who.name) if line.contains("%s") else line


## When the Captain's hands are full (hat and coffee): the companion gets a
## friendly look instead.
static func hands_full(who: Dictionary) -> String:
	if String(who.get("name", "")) != "":
		return Loc.t("%s gets a friendly look: your hands are full (hat and coffee).") % String(who.name)
	if who.get("kind", &"") == CompanionState.KIND_DOG:
		return Loc.t("The dog gets a friendly look: your hands are full (hat and coffee).")
	if who.get("kind", &"") == CompanionState.KIND_PARROT:
		return Loc.t("The parrot gets a friendly look: your hands are full (hat and coffee).")
	return Loc.t("The cat gets a friendly look: your hands are full (hat and coffee).")


# --- Who: the name, or the animal (I024) -----------------------------------------

static func _named(who: Dictionary) -> bool:
	return String(who.get("name", "")) != ""


static func _kind(who: Dictionary) -> StringName:
	var kind: StringName = who.get("kind", CompanionState.DEFAULT_KIND)
	return kind if kind in CompanionState.KINDS else CompanionState.DEFAULT_KIND


## The companion as the subject at the start of a sentence: its name, or
## "The cat" / "The dog" / "The parrot" (translated).
static func subject(who: Dictionary) -> String:
	if _named(who):
		return String(who.name)
	match _kind(who):
		CompanionState.KIND_DOG:
			return Loc.t("The dog")
		CompanionState.KIND_PARROT:
			return Loc.t("The parrot")
	return Loc.t("The cat")


## "Pet Fido" / "Pet the cat": the prompt over the animal.
static func pet_prompt(who: Dictionary) -> String:
	if _named(who):
		return Loc.t("Pet %s") % String(who.name)
	match _kind(who):
		CompanionState.KIND_DOG:
			return Loc.t("Pet the dog")
		CompanionState.KIND_PARROT:
			return Loc.t("Say hello to the parrot")
	return Loc.t("Pet the cat")


# --- Ashore and back aboard (I024) -----------------------------------------------

## Why the boat cannot cast off: the companion is still ashore.
static func still_ashore(who: Dictionary) -> String:
	if _named(who):
		return Loc.t("Wait! %s is still ashore.") % String(who.name)
	match _kind(who):
		CompanionState.KIND_DOG:
			return Loc.t("Wait! The dog is still ashore.")
		CompanionState.KIND_PARROT:
			return Loc.t("Wait! The parrot is still ashore.")
	return Loc.t("Wait! The cat is still ashore.")


## The refusal for everyone still ashore (I025): one companion as before;
## two named together. "" when nobody is ashore.
static func still_ashore_all(ashore: Array[Dictionary]) -> String:
	if ashore.is_empty():
		return ""
	if ashore.size() == 1:
		return still_ashore(ashore[0])
	return Loc.t("Wait! %s and %s are still ashore.") % [subject(ashore[0]), _lower_subject(ashore[1])]


## The subject inside a sentence: a name as written, "the cat" otherwise.
static func _lower_subject(who: Dictionary) -> String:
	if _named(who):
		return String(who.name)
	match _kind(who):
		CompanionState.KIND_DOG:
			return Loc.t("the dog")
		CompanionState.KIND_PARROT:
			return Loc.t("the parrot")
	return Loc.t("the cat")


## "Call Fido and Snowy aboard" / "Call the companions aboard".
static func call_all_aboard_label(ashore: Array[Dictionary]) -> String:
	if ashore.size() == 1:
		return call_aboard_label(ashore[0])
	if ashore.size() == 2 and _named(ashore[0]) and _named(ashore[1]):
		return Loc.t("Call %s and %s aboard") % [String(ashore[0].name), String(ashore[1].name)]
	return Loc.t("Call the companions aboard")


## A second line for the refusal: where it is and how to fetch it.
static func ashore_hint(who: Dictionary) -> String:
	if _kind(who) == CompanionState.KIND_PARROT:
		return Loc.t("%s is still exploring the harbour.") % subject(who)
	return Loc.t("%s is still exploring the pontoon.") % subject(who)


## The action that fetches it ("Call Fido aboard").
static func call_aboard_label(who: Dictionary) -> String:
	if _named(who):
		return Loc.t("Call %s aboard") % String(who.name)
	match _kind(who):
		CompanionState.KIND_DOG:
			return Loc.t("Call the dog aboard")
		CompanionState.KIND_PARROT:
			return Loc.t("Call the parrot aboard")
	return Loc.t("Call the cat aboard")


## Called back aboard.
static func recalled(who: Dictionary) -> String:
	match _kind(who):
		CompanionState.KIND_DOG:
			return Loc.t("%s trots back up the gangplank.") % subject(who)
		CompanionState.KIND_PARROT:
			return Loc.t("%s flutters back aboard.") % subject(who)
	return Loc.t("%s strolls back up the gangplank.") % subject(who)


## The recall notes of every companion called back, as one note (I025): two
## identical notes (two parrots both called Kiwi, two unnamed Pugs) become
## "Both are back aboard." rather than the same sentence twice.
static func recalled_all(lines: Array[String]) -> String:
	if lines.size() == 2 and lines[0] == lines[1]:
		return Loc.t("Both are back aboard.")
	return " ".join(lines)


# --- Waking up (I024) ------------------------------------------------------------

## A small observation when the Captain wakes: lines with the subject (%s:
## the name or "The cat") and a few without.
const WAKE := {
	CompanionState.KIND_CAT: [
		"%s snuggled up against you.",
		"%s was curled up at the end of the berth.",
		"%s kneaded the blanket until you opened your eyes.",
		"A quiet purr came from the end of the berth.",
	],
	CompanionState.KIND_DOG: [
		"%s licked your nose.",
		"%s was curled up beside your feet.",
		"%s's tail thumped the blanket as you stirred.",
		"A small snore came from the foot of the berth.",
	],
	CompanionState.KIND_PARROT: [
		"%s greeted the morning with a little chirp.",
		"%s was perched nearby when you opened your eyes.",
		"%s whistled softly, just like the kettle.",
		"A cheerful chirp came from the perch by the berth.",
	],
}


## The wake-up line for `day` (a stable number, e.g. the local day), or "".
static func wake_line(who: Dictionary, day: int) -> String:
	var choices: Array = WAKE[_kind(who)]
	var line := Loc.t(choices[posmod(day, choices.size())])
	return line % subject(who) if line.contains("%s") else line


## The wake-up line for one or two companions (I025): with two, one line
## about both, never two competing messages.
static func wake_line_all(who: Array[Dictionary], day: int) -> String:
	if who.is_empty():
		return ""
	if who.size() == 1:
		return wake_line(who[0], day)
	var a: Dictionary = who[posmod(day, 2)]
	var b: Dictionary = who[1 - posmod(day, 2)]
	var pair := "%s+%s" % [_kind(a), _kind(b)]
	var choices: Array = WAKE_PAIR.get(pair, WAKE_PAIR_ANY)
	return Loc.t(choices[posmod(day, choices.size())]) % [subject(a), _lower_subject(b)]


## Two companions waking with the Captain: %s is the first, %s the second.
const WAKE_PAIR := {
	"cat+dog": ["%s had claimed your pillow, and %s was asleep at your feet.", "%s was curled up on the blanket; %s snored softly beside it."],
	"dog+cat": ["%s was asleep at your feet; %s had claimed your pillow.", "%s licked your nose while %s watched from the end of the berth."],
	"parrot+dog": ["%s chirped softly while %s stretched.", "%s whistled good morning; %s answered with a yawn."],
	"dog+parrot": ["%s stretched while %s chirped softly from its perch.", "%s thumped the blanket with its tail; %s whistled back."],
	"parrot+cat": ["%s chirped from its perch; %s pretended not to hear.", "%s greeted the morning; %s opened one eye."],
	"cat+parrot": ["%s was curled up beside you, and %s chirped from its perch.", "%s purred at the end of the berth while %s preened nearby."],
	"cat+cat": ["%s and %s were curled up together at the end of the berth.", "%s had your pillow and %s your feet."],
	"dog+dog": ["%s and %s were piled up together at your feet.", "%s licked your nose; %s was still snoring."],
	"parrot+parrot": ["%s and %s chirped back and forth by the berth.", "%s and %s sat side by side on the perch, fluffed up."],
}
const WAKE_PAIR_ANY := ["%s and %s were waiting by the berth when you woke."]


# --- Talk on long passages (I024) ------------------------------------------------

## The longer the passage, the more the Captain talks to the companion -
## not a need or a meter, just days shared on a small boat. Three stages by
## the voyage's own clock (hours since leaving): a remark is possible at
## most every PASSAGE_GAP_HOURS game hours (shorter as days go by) and never
## sooner than PASSAGE_MIN_REAL_SECONDS of real time, so time acceleration
## cannot bring a flood. Callers keep the timing (App._update_passage_talk).
const STAGE_EARLY := 0
const STAGE_DAYS := 1
const STAGE_EXTENDED := 2
## Hours at sea at which each stage begins.
const STAGE_HOURS: Array[float] = [0.0, 48.0, 120.0]
## No remark in the first hours of a passage; then at most one per gap.
const PASSAGE_FIRST_HOURS := 6.0
const PASSAGE_GAP_HOURS: Array[float] = [14.0, 9.0, 6.0]
const PASSAGE_MIN_REAL_SECONDS := 240.0

## The Captain's lines per stage. %s is the name: a line with %s is only
## used for a named companion.
const PASSAGE := {
	STAGE_EARLY: [
		"Good sailing weather, isn't it, %s?",
		"Comfortable there?",
		"Let's see what the wind does.",
		"Settled in already, %s?",
		"Nice and steady, this.",
		"Another tack or two and we're well on our way.",
		"Keep an eye on things for me, %s.",
		"Not a bad start, is it?",
	],
	STAGE_DAYS: [
		"Think we'll find a good breakfast in the next harbour?",
		"You've got the best seat on this boat.",
		"I wonder what everyone back home is doing.",
		"Another day of blue, %s.",
		"You've found your sea legs, haven't you?",
		"I could get used to this, couldn't you?",
		"Fresh bread. That's what I'd like. Fresh bread.",
		"We've come a fair way together, %s.",
		"Same old sea, different every hour.",
		"Don't tell anyone I talk to you this much.",
	],
	STAGE_EXTENDED: [
		"Funny how familiar the sound of the sea becomes.",
		"I suppose it's just you and me out here.",
		"You're not much help with the navigation, are you?",
		"I think we've discussed the weather quite enough.",
		"Do you dream about land, %s?",
		"I've stopped counting the waves. You?",
		"Whatever happens, %s, we're in this together.",
		"You're better company than most people I know.",
		"I'll miss these quiet watches when we're ashore.",
		"Remember the last harbour? Feels like a month ago.",
		"Tell me honestly, %s: am I talking to myself?",
		"One day we'll tell stories about this passage.",
	],
}
## Lines only for one kind, added to every stage from `min stage` on.
const PASSAGE_BY_KIND := {
	CompanionState.KIND_CAT: [[STAGE_EARLY, "Don't shed on the charts, please."], [STAGE_DAYS, "You've claimed that cushion for good, haven't you?"],
		[STAGE_EXTENDED, "Nine lives, and you chose to spend this one at sea."]],
	CompanionState.KIND_DOG: [[STAGE_EARLY, "No, there are no squirrels out here."], [STAGE_DAYS, "Snoring again? You and the bilge pump both."],
		[STAGE_EXTENDED, "Best first mate a captain could ask for."]],
	CompanionState.KIND_PARROT: [[STAGE_EARLY, "Watch the halyards, little one."], [STAGE_DAYS, "Was that you, or the winch?"],
		[STAGE_EXTENDED, "You've learnt every sound on this boat, haven't you?"]],
}
## By gender, with the name.
const PASSAGE_BY_GENDER := {
	GENDER_FEMALE: [[STAGE_DAYS, "Good girl, %s."]],
	GENDER_MALE: [[STAGE_DAYS, "Good lad, %s."]],
}

## Responses: [line, clip]. The line has the subject (%s); "" = it does
## nothing (that is fine). The clip is a pose of the companion's art
## (ShipCompanion.respond()); a missing clip is simply not played.
const RESPONSES := {
	CompanionState.KIND_CAT: [
		["%s gives you a slow blink.", &"alert"],
		["%s answers with a small meow.", &"alert"],
		["%s purrs.", &"pet"],
		["The tip of %s's tail twitches.", &"resting"],
		["%s ignores you completely.", &"groom"],
		["", &""],
		["", &""],
	],
	CompanionState.KIND_DOG: [
		["%s tilts a curious head.", &"alert"],
		["%s's tail thumps the cabin sole.", &"tail_wag"],
		["%s gives a small, approving woof.", &"alert"],
		["%s sighs and settles down again.", &"resting"],
		["", &""],
		["", &""],
	],
	CompanionState.KIND_PARROT: [
		["%s chirps back.", &"alert"],
		["%s whistles a little tune.", &"alert"],
		["%s fluffs up and settles.", &"ruffle"],
		["%s turns to look at you.", &"head_turn"],
		["%s clicks, exactly like the winch.", &"alert"],
		["", &""],
		["", &""],
	],
}


## Lines for two companions (I025): %s is the first one's name, %s the
## second's; only with both named. Mixed in now and then, never on top of the
## usual lines (one remark at a time, the same gaps).
const PASSAGE_PAIR := [
	[STAGE_EARLY, "Well, you two seem to have this voyage figured out."],
	[STAGE_EARLY, "%s, I think %s has stolen your favourite spot."],
	[STAGE_DAYS, "%s, are you encouraging %s?"],
	[STAGE_DAYS, "You two get along better than most crews I know."],
	[STAGE_DAYS, "%s and %s, the finest crew afloat."],
	[STAGE_EXTENDED, "Days at sea, and you two still find something to look at."],
	[STAGE_EXTENDED, "%s, %s - I'm glad you're both aboard."],
]
## The second companion's reaction to a pair remark: [line (%s = its
## subject), clip] or nothing.
const PAIR_RESPONSES := [["%s glances at the other, then at you.", &"alert"], ["", &""], ["%s settles down a little closer.", &"resting"]]


## The other companion's answer to a remark about both: {"text", "clip"}
## (the text may be empty: it only looks).
static func pair_response(who: Dictionary, n: int) -> Dictionary:
	var entry: Array = PAIR_RESPONSES[posmod(n, PAIR_RESPONSES.size())]
	var line := String(entry[0])
	return {"text": Loc.t(line) % subject(who) if line != "" else "", "clip": entry[1]}


## Pair lines available at `stage` for two companions.
static func passage_pair_lines(a: Dictionary, b: Dictionary, stage: int) -> Array[String]:
	var named := _named(a) and _named(b)
	var out: Array[String] = []
	for entry: Array in PASSAGE_PAIR:
		var line := String(entry[1])
		if int(entry[0]) <= stage and (named or not line.contains("%s")):
			out.append(line)
	return out


## A pair remark (translated, in quotes, both names in).
static func say_pair(a: Dictionary, b: Dictionary, key: String) -> String:
	var line := Loc.t(key)
	if line.contains("%s"):
		line = line % [String(a.get("name", "")), String(b.get("name", ""))]
	return Loc.t("“%s”") % line


## The stage of a passage `hours` long.
static func passage_stage(hours: float) -> int:
	var stage := STAGE_EARLY
	for i in STAGE_HOURS.size():
		if hours >= STAGE_HOURS[i]:
			stage = i
	return stage


## The Captain's lines (message keys) available at `stage` for `who`, in a
## fixed order: the stage's own lines first, then kind and gender extras.
static func passage_lines(who: Dictionary, stage: int) -> Array[String]:
	var named := _named(who)
	var out: Array[String] = []
	for line: String in PASSAGE[clampi(stage, STAGE_EARLY, STAGE_EXTENDED)]:
		if named or not line.contains("%s"):
			out.append(line)
	for extra: Array in PASSAGE_BY_KIND.get(_kind(who), []):
		if int(extra[0]) <= stage:
			out.append(String(extra[1]))
	if named:
		for extra: Array in PASSAGE_BY_GENDER.get(StringName(who.get("gender", &"")), []):
			if int(extra[0]) <= stage:
				out.append(String(extra[1]))
	return out


## The Captain's remark (translated, in quotes, name inserted) for line key `key`.
static func say(who: Dictionary, key: String) -> String:
	var line := Loc.t(key)
	if line.contains("%s"):
		line = line % String(who.get("name", ""))
	return Loc.t("“%s”") % line


## Response number `n` for `who`: {"text": translated line or "", "clip": pose}.
static func response(who: Dictionary, n: int) -> Dictionary:
	var choices: Array = RESPONSES[_kind(who)]
	var pick: Array = choices[posmod(n, choices.size())]
	var text := String(pick[0])
	return {"text": Loc.t(text) % subject(who) if text != "" else "", "clip": StringName(pick[1])}


# --- An animal on the dock (I025) ------------------------------------------------

## The kind gestures, in order (DockEncounters.TRUST_NEEDED of them): a
## hello, a free treat from the Captain's pocket, a little play. What each
## says and which clip the animal answers with, by kind.
const BEFRIEND := {
	CompanionState.KIND_CAT: [
		["A Ragdoll peeks over the edge of the box. You hold out a hand and let it sniff.", &"alert"],
		["You find a few treats in your pocket. The Ragdoll eats them, very politely.", &"pet"],
		["You trail a bit of rope along the planks. The Ragdoll pounces, then purrs.", &"stretching"],
	],
	CompanionState.KIND_DOG: [
		["The little Pug wriggles all over as you crouch down to say hello.", &"tail_wag"],
		["A biscuit from your pocket disappears in one happy crunch.", &"pet"],
		["You toss a knot of rope a little way. The Pug brings it back, very proud.", &"tail_wag"],
	],
	CompanionState.KIND_PARROT: [
		["The conure tilts its head and gives a soft chirp as you say hello.", &"head_turn"],
		["You offer a few seeds on your palm. The conure takes them, one by one.", &"pet"],
		["You whistle a little tune. The conure whistles it back, nearly right.", &"ruffle"],
	],
}


static func _dock_kind(kind: StringName) -> StringName:
	return kind if kind in CompanionState.KINDS else CompanionState.DEFAULT_KIND


## What the Captain does next (the prompt over the waiting animal).
static func befriend_prompt(kind: StringName, trust: int) -> String:
	if trust >= DockEncounters.TRUST_NEEDED:
		return ""
	match trust:
		0:
			match _dock_kind(kind):
				CompanionState.KIND_DOG:
					return Loc.t("Say hello to the Pug")
				CompanionState.KIND_PARROT:
					return Loc.t("Say hello to the conure")
			return Loc.t("Say hello to the Ragdoll")
		1:
			return Loc.t("Offer a treat")
	return Loc.t("Play a little")


## The line for kind gesture `step` (1..TRUST_NEEDED); after the last one,
## a second sentence says it would like to come along.
static func befriend_line(kind: StringName, step: int) -> String:
	var entries: Array = BEFRIEND[_dock_kind(kind)]
	var line := Loc.t(String(entries[clampi(step - 1, 0, entries.size() - 1)][0]))
	if step >= DockEncounters.TRUST_NEEDED:
		line += " " + Loc.t("It looks as if it would like to come with you.")
	return line


## The clip the animal answers gesture `step` with.
static func befriend_clip(kind: StringName, step: int) -> StringName:
	var entries: Array = BEFRIEND[_dock_kind(kind)]
	return entries[clampi(step - 1, 0, entries.size() - 1)][1]


## Simply waiting nearby, quietly, also counts as a kind gesture.
static func waited_line(kind: StringName) -> String:
	match _dock_kind(kind):
		CompanionState.KIND_DOG:
			return Loc.t("You sit on the pontoon for a while. The Pug comes and leans against your leg.")
		CompanionState.KIND_PARROT:
			return Loc.t("You sit on the pontoon for a while. The conure hops a little closer.")
	return Loc.t("You sit on the pontoon for a while. The Ragdoll comes a little closer.")


## The question at the companionway.
static func followed_home(kind: StringName) -> String:
	match _dock_kind(kind):
		CompanionState.KIND_DOG:
			return Loc.t("The little Pug has followed you all the way home. Would you like to welcome it aboard?")
		CompanionState.KIND_PARROT:
			return Loc.t("The little conure has followed you all the way home. Would you like to welcome it aboard?")
	return Loc.t("The Ragdoll has followed you all the way home. Would you like to welcome it aboard?")


## The laptop's history line for a companion (I025): where and when it came
## aboard, from its own record only - never invented. "" for a companion
## without an adoption record (one who sailed from the start).
static func welcomed_line(companion: CompanionState, port_name: String) -> String:
	if companion == null or not companion.has_adoption_record():
		return ""
	var who := _lower_subject(identity(companion))
	if port_name != "":
		return Loc.t("Welcomed %s aboard in %s.") % [who, port_name]
	return Loc.t("Welcomed %s aboard.") % who
