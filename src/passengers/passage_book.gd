class_name PassageBook
extends RefCounted
## The passage trade's state (I028, Passages, People & Reputation): the
## travellers the Captain has met, the passages published from the chart
## (offers), travellers' requests, the agreements made (bookings, with their
## contract terms), the authoritative voyage ledger of what really happened
## (records), the letters and keepsakes passengers left behind, and the
## competing skippers' standing. Kept in SessionState.passages and saved under
## "passages" (optional: an older save starts with an empty book).
##
## Plain dictionaries of JSON types throughout (ids are strings: "t12", "o3",
## "r7", "b5"), so the save is the state and nothing is derived twice. Only
## GameSession changes it, through the rules in Marketplace, GuestReactions and
## Settlement.

const STATUS_PUBLISHED := "published"
const STATUS_SAILING := "sailing"
const STATUS_DONE := "done"
const STATUS_CANCELLED := "cancelled"
const REQUEST_PENDING := "pending"
const REQUEST_COUNTERED := "countered"
const REQUEST_ACCEPTED := "accepted"
const REQUEST_DECLINED := "declined"
const REQUEST_LOST := "lost"
const REQUEST_EXPIRED := "expired"
const BOOKING_CONFIRMED := "confirmed"
const BOOKING_ABOARD := "aboard"
const BOOKING_COMPLETED := "completed"
const BOOKING_CANCELLED := "cancelled"
## The ledger keeps the most recent records (older ones are summarised in totals).
const MAX_RECORDS := 300
const MAX_LETTERS := 60

## id -> traveller (Travellers.make)
var travellers := {}
var offers: Array = []
var requests: Array = []
var bookings: Array = []
## The voyage ledger: one record per finished booking (Settlement.settle).
var records: Array = []
## Sailed legs with people aboard: {"offer", "from", "to", "departed", "arrived", "nm", "aboard": [booking ids], "max_hazard"}.
var legs: Array = []
## Totals kept forever (records roll over): passengers carried, nights, fares, tips, refunds.
var totals := {"passengers": 0, "bookings": 0, "nights": 0, "fares": 0, "tips": 0, "refunds": 0, "dreams": 0, "stars": 0, "reviews": 0}
## skipper id -> {"won": n} (their standing moves only with bookings they win).
var rivals := {}
## Letters, photographs and gifts from passengers: {"id", "time", "from", "kind", "text", "booking"}.
var letters: Array = []
## Delighted passengers who recommend the Captain: the next published passage
## brings that many referred travellers (I028 Tier 4).
var referrals := 0
var next_id := 1


func new_id(prefix: String) -> String:
	next_id += 1
	return "%s%d" % [prefix, next_id - 1]


func get_offer(id: String) -> Dictionary:
	for offer: Dictionary in offers:
		if offer.id == id:
			return offer
	return {}


func get_request(id: String) -> Dictionary:
	for request: Dictionary in requests:
		if request.id == id:
			return request
	return {}


func get_booking(id: String) -> Dictionary:
	for booking: Dictionary in bookings:
		if booking.id == id:
			return booking
	return {}


func get_traveller(id: String) -> Dictionary:
	return travellers.get(id, {})


func bookings_for_offer(offer_id: String, include_closed := false) -> Array:
	return bookings.filter(func(b: Dictionary) -> bool:
		return b.offer == offer_id and (include_closed or b.status in [BOOKING_CONFIRMED, BOOKING_ABOARD]))


## The offer being sailed (or about to be: published, with bookings), or {}.
func active_offer() -> Dictionary:
	for offer: Dictionary in offers:
		if offer.status == STATUS_SAILING:
			return offer
	return {}


func aboard() -> Array:
	return bookings.filter(func(b: Dictionary) -> bool: return b.status == BOOKING_ABOARD)


## The Captain's average review (stars) and how many reviews it rests on.
func rating() -> Vector2:
	var count := int(totals.reviews)
	return Vector2(float(totals.stars) / count if count > 0 else 0.0, count)


func duplicate_book() -> PassageBook:
	return PassageBook.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {"travellers": travellers.duplicate(true), "offers": offers.duplicate(true), "requests": requests.duplicate(true),
		"bookings": bookings.duplicate(true), "records": records.duplicate(true), "legs": legs.duplicate(true), "totals": totals.duplicate(),
		"rivals": rivals.duplicate(true), "letters": letters.duplicate(true), "referrals": referrals, "next_id": next_id}


## Lenient: anything malformed is left out, never fatal.
static func from_dict(data: Variant) -> PassageBook:
	var book := PassageBook.new()
	if not data is Dictionary:
		return book
	var d: Dictionary = data
	if d.get("travellers") is Dictionary:
		for id: Variant in d.travellers:
			if d.travellers[id] is Dictionary:
				book.travellers[String(id)] = (d.travellers[id] as Dictionary).duplicate(true)
	for key in ["offers", "requests", "bookings", "records", "legs", "letters"]:
		var list: Variant = d.get(key, [])
		if list is Array:
			var kept: Array = []
			for item: Variant in list:
				if item is Dictionary and (key in ["legs"] or (item as Dictionary).has("id")):
					kept.append((item as Dictionary).duplicate(true))
			book.set(key, kept)
	if d.get("totals") is Dictionary:
		for key: String in book.totals:
			var value: Variant = d.totals.get(key, 0)
			book.totals[key] = int(value) if value is int or value is float else 0
	if d.get("rivals") is Dictionary:
		book.rivals = (d.rivals as Dictionary).duplicate(true)
	var referred: Variant = d.get("referrals", 0)
	book.referrals = clampi(int(referred) if referred is int or referred is float else 0, 0, 20)
	var next: Variant = d.get("next_id", 1)
	book.next_id = maxi(int(next) if next is int or next is float else 1, 1)
	return book
