class_name Settlement
extends RefCounted
## Agreements and their settlement (I028 Tier 3): the contract terms written
## into a booking when it is accepted, the promise of an arrival, refunds,
## tips, reviews, an alternative harbour agreed under way, and the record the
## voyage ledger keeps. Pure; GameSession moves the money and keeps the
## records.
##
## The rules, in short:
##   - a deposit (Marketplace.DEPOSIT_SHARE) is paid on booking; the rest on
##     arrival, for the legs actually sailed with the passenger aboard;
##   - late beyond the grace: a refund of 5 % a day (at most 30 %), unless the
##     delay came from the Captain's caution in bad weather (excused);
##   - an agreed alternative harbour: the fare for the legs as sailed, less a
##     small goodwill discount by how far onward travel is;
##   - the Captain cancels: the deposit back in full;
##   - a tip and a review follow satisfaction and the traveller's habits.

const GRACE_MIN_H := 6.0
const GRACE_SHARE := 0.15
const LATE_REFUND_PER_DAY := 0.05
const LATE_REFUND_MAX := 0.3
## Goodwill on an agreed alternative harbour, by its transfer band rank.
const ALTERNATE_DISCOUNT := [0.0, 0.05, 0.1, 0.15]

const REVIEW_TEXTS := {
	5: ["An unforgettable passage. Warm, safe and beautifully sailed.", "Everything we hoped for and more. Book this Captain."],
	4: ["A lovely voyage with a kind Captain. Recommended.", "Comfortable, friendly and well planned."],
	3: ["A decent passage, with a few rough edges.", "We arrived, and it was mostly pleasant."],
	2: ["Not quite what we were promised.", "Too late and too uncomfortable for us."],
	1: ["Disappointing. We would not sail again.", "A difficult journey, from start to finish."],
}


## The contract terms written into a new booking.
static func terms(offer: Dictionary, request: Dictionary, fare_eur: int, traveller: Dictionary) -> Dictionary:
	var from := int(request.from)
	var to := int(request.to)
	var booked_s := float(offer.arrive[to]) - float(offer.depart[from])
	var grace_h := maxf(GRACE_MIN_H, booked_s / 3600.0 * GRACE_SHARE)
	# How far onward travel may be from an alternative harbour, by temperament.
	var accept_rank: int = {"strict": 0, "normal": 1, "relaxed": 2}.get(traveller.get("timing", "normal"), 1)
	if traveller.get("detour", "") == "enjoys":
		accept_rank += 1
	return {"fare": fare_eur, "deposit": Marketplace.deposit_for(fare_eur), "paid": 0, "refunded": 0,
		"depart_after": float(offer.depart[from]), "depart_before": float(offer.depart[from]) + Marketplace.WINDOW_H * 3600.0,
		"promised": float(offer.arrive[to]) + grace_h * 3600.0, "grace_h": snappedf(grace_h, 0.1),
		"embark": String(offer.stops[from]), "disembark": String(offer.stops[to]), "original_disembark": String(offer.stops[to]),
		"booked_nm": Marketplace.distance(offer, from, to), "nights": Marketplace.nights(offer, from, to),
		"alternate_rank": accept_rank}


## Would the passenger accept `port_id` instead of their harbour? {"ok", "reason", "band"}.
static func alternate_acceptance(booking: Dictionary, traveller: Dictionary, port_id: StringName) -> Dictionary:
	var b := TransferAccess.band(port_id)
	var limit := int(booking.get("alternate_rank", 1))
	if traveller.get("timing", "") == "strict" and float(booking.get("satisfaction", 70.0)) < 50.0:
		limit -= 1
	var ok: bool = int(b.rank) <= limit
	var reason := Loc.t("%s is fine: %s.") % [traveller.given, b.label.to_lower()] if ok \
		else Loc.t("%s would rather not: %s is too far from onward travel.") % [traveller.given, b.label.to_lower()]
	return {"ok": ok, "reason": reason, "band": b}


## The fare for an agreed alternative harbour: the original fare scaled by the
## share of the booked distance the new harbour covers (at most all of it),
## less goodwill by how far onward travel is.
static func alternate_fare(booking: Dictionary, covered_nm: float, band_rank: int) -> int:
	var share := clampf(covered_nm / maxf(float(booking.booked_nm), 0.1), 0.3, 1.0)
	var discount: float = ALTERNATE_DISCOUNT[clampi(band_rank, 0, ALTERNATE_DISCOUNT.size() - 1)]
	return int(snappedf(float(booking.fare) * share * (1.0 - discount), 5.0))


## Settles a booking on arrival at its harbour. Returns {"balance" (owed now:
## negative is a refund), "refund", "tip", "stars", "review", "late_h", "excused"}.
static func settle(booking: Dictionary, traveller: Dictionary, now: float) -> Dictionary:
	var fare_eur := int(booking.fare)
	var sailed: float = booking.get("sailed_nm", 0.0)
	var share := clampf(sailed / maxf(float(booking.booked_nm), 0.1), 0.0, 1.0) if not booking.get("alternate_agreed", false) else 1.0
	var owed := int(snappedf(fare_eur * share, 5.0)) if share < 0.98 else fare_eur
	var late_h := maxf((now - float(booking.promised)) / 3600.0, 0.0)
	var refund := 0
	if late_h > 0.0 and not booking.get("excused", false):
		refund = int(snappedf(owed * minf(LATE_REFUND_PER_DAY * ceilf(late_h / 24.0), LATE_REFUND_MAX), 5.0))
	var balance := owed - refund - int(booking.get("paid", 0))
	var satisfaction := float(booking.get("satisfaction", GuestReactions.START))
	var tendency: float = {"generous": 0.5, "fair": 0.0, "critical": -0.6}.get(traveller.get("reviews", "fair"), 0.0)
	var stars := clampi(roundi(1.0 + satisfaction / 22.0 + tendency), 1, 5)
	var tip := 0
	if satisfaction >= 75.0:
		tip = int(snappedf(owed * (0.04 + (satisfaction - 75.0) / 25.0 * 0.08) * (1.4 if traveller.get("reviews", "") == "generous" else 1.0), 5.0))
	var texts: Array = REVIEW_TEXTS[stars]
	var review := String(texts[absi(hash(String(booking.id))) % texts.size()])
	return {"balance": balance, "refund": refund, "tip": tip, "stars": stars, "review": review, "late_h": snappedf(late_h, 0.1),
		"excused": booking.get("excused", false), "owed": owed}


## The voyage ledger's record of a finished booking: the facts, never derived again.
static func make_record(booking: Dictionary, traveller: Dictionary, offer: Dictionary, result: Dictionary, vessel_id: StringName, now: float,
		disembark: String) -> Dictionary:
	return {
		"id": String(booking.id), "booking": String(booking.id), "offer": String(offer.get("id", "")), "traveller": String(traveller.id),
		"name": Travellers.display_name(traveller), "size": int(booking.size), "vessel": String(vessel_id),
		"accommodation": "private cabin" if booking.get("private", false) else "shared",
		"embark": String(booking.embark), "disembark": disembark, "booked_disembark": String(booking.original_disembark),
		"legs": booking.get("legs_sailed", []).duplicate(true), "boarded": float(booking.get("boarded_at", 0.0)), "left": now,
		"nm": snappedf(float(booking.get("sailed_nm", 0.0)), 0.1), "nights": int(booking.get("nights_aboard", 0)),
		"max_hazard": int(booking.get("max_hazard", 0)), "late_h": result.late_h, "excused": result.excused,
		"diversions": booking.get("diversions", []).duplicate(true),
		"fare": int(booking.fare), "deposit": int(booking.deposit), "paid": int(booking.get("paid", 0)) + int(result.balance),
		"refund": int(result.refund) + int(booking.get("refunded", 0)), "tip": int(result.tip),
		"satisfaction": roundi(float(booking.get("satisfaction", GuestReactions.START))), "stars": int(result.stars), "review": result.review,
		"events": booking.get("events", []).duplicate(true), "dream": booking.get("dream", {}).duplicate(true),
	}
