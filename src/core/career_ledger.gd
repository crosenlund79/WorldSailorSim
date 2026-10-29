class_name CareerLedger
extends RefCounted
## The career's books (I027, The Cost of the Wind): every euro in and out by
## its source, fuel bought and burned, and each voyage's own figures - the
## real game's numbers, recorded as they happen, for the Captain's running
## costs in the harbour office and for career testing (telemetry). Owned by
## SessionState (saved, optional); written only by GameSession.
##
## Nothing here is invented: an entry exists because the game moved money,
## fuel or the boat. Old saves start an empty ledger.

## Recent money movements kept in full (older ones live on in the totals).
const MAX_ENTRIES := 400
## Recent voyages kept in full.
const MAX_VOYAGES := 200

## Totals by source tag ("provisions", "fuel", "harbour_dues", "remote_work",
## "fishing", ...): income positive, expenses negative.
var totals := {}
## [{t, source, amount, balance}] newest last.
var entries: Array = []
## Litres of fuel bought and burned, and euros spent on fuel, all career.
var fuel_bought_l := 0.0
var fuel_burned_l := 0.0
## Distance sailed through the water under sail and under engine (nm).
var nm_sail := 0.0
var nm_engine := 0.0
## [{from, to, departed, arrived, nm, nm_engine, fuel_l, tacks, costs}] newest last.
var voyages: Array = []
## The voyage under way: the counters at its departure ({} in harbour).
var open_voyage := {}


func record_money(time: float, source: String, amount: int, balance: int) -> void:
	if amount == 0:
		return
	totals[source] = int(totals.get(source, 0)) + amount
	entries.append({"t": time, "source": source, "amount": amount, "balance": balance})
	if entries.size() > MAX_ENTRIES:
		var removed := entries.size() - MAX_ENTRIES
		entries = entries.slice(removed)
		if open_voyage.has("entries_from"):
			open_voyage.entries_from = maxi(int(open_voyage.entries_from) - removed, 0)


func record_distance(nm: float, under_engine: bool) -> void:
	if under_engine:
		nm_engine += nm
	else:
		nm_sail += nm


func record_voyage(summary: Dictionary) -> void:
	voyages.append(summary)
	if voyages.size() > MAX_VOYAGES:
		voyages = voyages.slice(voyages.size() - MAX_VOYAGES)


## A voyage begins: the counters now, to tell its own share at the end.
func open(time: float, from: String) -> void:
	open_voyage = {"departed": time, "from": from, "fuel_burned_l": fuel_burned_l, "nm_sail": nm_sail, "nm_engine": nm_engine,
		"entries_from": entries.size()}


## The voyage ends: its figures from the counters, recorded.
func close(time: float, to: String, tacks: int, outcome: String) -> Dictionary:
	if open_voyage.is_empty():
		return {}
	var costs := 0
	for i in range(mini(int(open_voyage.entries_from), entries.size()), entries.size()):
		costs += mini(int(entries[i].amount), 0)
	var summary := {"from": open_voyage.from, "to": to, "departed": open_voyage.departed, "arrived": time, "outcome": outcome,
		"nm_sail": snappedf(nm_sail - float(open_voyage.nm_sail), 0.01), "nm_engine": snappedf(nm_engine - float(open_voyage.nm_engine), 0.01),
		"fuel_l": snappedf(fuel_burned_l - float(open_voyage.fuel_burned_l), 0.01), "tacks": tacks, "costs_underway": -costs}
	record_voyage(summary)
	open_voyage = {}
	return summary


## Income (positive) or expenses (negative) for `source` over the career.
func total(source: String) -> int:
	return int(totals.get(source, 0))


## Sum of all expenses since `since` (game time), by source: {source: euros}
## (positive numbers), from the recent entries.
func expenses_since(since: float) -> Dictionary:
	var out := {}
	for e: Dictionary in entries:
		if float(e.t) >= since and int(e.amount) < 0:
			out[e.source] = int(out.get(e.source, 0)) - int(e.amount)
	return out


func duplicate_ledger() -> CareerLedger:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	return {"totals": totals.duplicate(), "entries": entries.duplicate(true), "fuel_bought_l": fuel_bought_l,
		"fuel_burned_l": fuel_burned_l, "nm_sail": nm_sail, "nm_engine": nm_engine, "voyages": voyages.duplicate(true),
		"open_voyage": open_voyage.duplicate(true)}


## Lenient: anything unreadable starts empty (the ledger is a record, never
## a reason for a save not to load).
static func from_dict(data: Variant) -> CareerLedger:
	var ledger := CareerLedger.new()
	if not data is Dictionary:
		return ledger
	var t: Variant = data.get("totals", {})
	if t is Dictionary:
		for key: Variant in t:
			if (t[key] is int or t[key] is float) and is_finite(float(t[key])):
				ledger.totals[String(key)] = int(t[key])
	for key: String in ["fuel_bought_l", "fuel_burned_l", "nm_sail", "nm_engine"]:
		var v: Variant = data.get(key, 0.0)
		if (v is int or v is float) and is_finite(float(v)):
			ledger.set(key, maxf(float(v), 0.0))
	var e: Variant = data.get("entries", [])
	if e is Array:
		for entry: Variant in e:
			if entry is Dictionary and entry.has("t") and entry.has("source") and entry.has("amount"):
				ledger.entries.append({"t": float(entry.t), "source": String(entry.source), "amount": int(entry.amount),
					"balance": int(entry.get("balance", 0))})
	var open_data: Variant = data.get("open_voyage", {})
	if open_data is Dictionary and open_data.has("departed"):
		ledger.open_voyage = open_data.duplicate(true)
	var v2: Variant = data.get("voyages", [])
	if v2 is Array:
		for voyage: Variant in v2:
			if voyage is Dictionary:
				ledger.voyages.append(voyage.duplicate(true))
	return ledger
