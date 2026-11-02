class_name PassagesApp
extends RefCounted
## The laptop's Passages app (I028 Tiers 1-3): the passage trade on one page.
## Publish the course planned on the chart (or chartplotter) as a passage,
## with stops along it, a departure window and a price; read and answer the
## travellers' requests (accept, decline or name a price); follow the
## bookings leg by leg; agree another harbour with a passenger; see the
## other skippers and the latest reviews. Everything goes through
## GameSession; this only shows and asks.

const DEPART_CHOICES := [12, 24, 48]
const PRICE_CHOICES := [0.85, 1.0, 1.15, 1.3]


static func build(laptop: LaptopView) -> Control:
	var page := laptop._page("Passages")
	var book := GameSession.get_passage_book()
	var rating := book.rating()
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 16)
	page.add_child(tiles)
	laptop._tile(tiles, "Reviews", "%.1f ★" % rating.x if rating.y > 0 else "–", Loc.n("%d review", "%d reviews", int(rating.y)) % int(rating.y))
	laptop._tile(tiles, "Passengers", str(int(book.totals.passengers)), Loc.t("carried so far"))
	laptop._tile(tiles, "Fares", GameSession.format_money(int(book.totals.fares) + int(book.totals.tips)), Loc.t("fares and tips"))
	_build_offer(laptop, page, book)
	_build_requests(laptop, page, book)
	_build_records(laptop, page, book)
	_build_rivals(laptop, page, book)
	return page


static func _refresh(laptop: LaptopView, message := "") -> void:
	if message != "":
		laptop.notify(message)
	laptop.show_app(LaptopView.APP_PASSAGES)


static func _port(id: Variant) -> String:
	return PortCatalog.get_default().get_display_name(StringName(id))


# --- The passage ------------------------------------------------------------------

static func _build_offer(laptop: LaptopView, page: VBoxContainer, book: PassageBook) -> void:
	laptop._heading(page, "Your passage")
	var current := {}
	for offer: Dictionary in book.offers:
		if offer.status in [PassageBook.STATUS_PUBLISHED, PassageBook.STATUS_SAILING]:
			current = offer
	if not current.is_empty():
		_show_offer(laptop, page, book, current)
		return
	var route := GameSession.get_planned_route()
	if GameSession.is_underway() or route == null or GameSession.get_location() == null:
		laptop._text(page, &"NoCourse", "Plan a course at the chart table or the chartplotter while in harbour, then publish it here as a passage.", &"MutedLabel")
		return
	var vessel := GameSession.get_vessel_id()
	laptop._text(page, &"Course", Loc.t("Planned: %s to %s, %.0f nm.") % [_port(route.origin_port_id), _port(route.destination_port_id),
		route.get_distance_nm()])
	laptop._text(page, &"Boat", Loc.t("%s: %d places by day, %d overnight, %d private cabins; %s, fitted for %s passages.") % [
		GameSession.get_vessel_definition().display_name, Accommodation.safe_guest_count(vessel), Accommodation.overnight_guest_count(vessel),
		Accommodation.private_guest_cabins(vessel), Accommodation.comfort_name(Accommodation.comfort_tier(vessel)),
		Accommodation.passage_short(Accommodation.passage_suitability(vessel))], &"MutedLabel")
	var candidates := GameSession.passage_candidate_stops()
	var picks: Array[CheckBox] = []
	if not candidates.is_empty():
		laptop._text(page, &"StopsNote", "Stops along the way (passengers may join or leave there):", &"MutedLabel")
		var flow := HFlowContainer.new()
		flow.name = "Stops"
		page.add_child(flow)
		for id in candidates.slice(0, 8):
			var box := CheckBox.new()
			box.name = "Stop_%s" % id
			box.text = _port(id)
			box.set_meta(&"port", id)
			flow.add_child(box)
			picks.append(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var when := OptionButton.new()
	when.name = "Departure"
	for hours: int in DEPART_CHOICES:
		when.add_item(Loc.t("Leave in %d hours") % hours)
	row.add_child(when)
	var price := OptionButton.new()
	price.name = "Price"
	var rate := Marketplace.going_rate(vessel)
	for factor: float in PRICE_CHOICES:
		price.add_item(Loc.t("€%.2f per nm and person") % (rate * factor))
	price.select(1)
	row.add_child(price)
	laptop._action(row, "PublishButton", "Publish passage", func() -> void:
		if not GameSession.can_work_remotely():
			_refresh(laptop, Loc.t("You need the harbour Wi-Fi to publish."))
			return
		var stops: Array = []
		for box in picks:
			if box.button_pressed and stops.size() < Marketplace.MAX_STOPS - 1:
				stops.append(String(box.get_meta(&"port")))
		stops.append(String(route.destination_port_id))
		var result := GameSession.publish_passage(stops, GameSession.get_game_time() + DEPART_CHOICES[when.selected] * 3600.0,
			rate * PRICE_CHOICES[price.selected])
		_refresh(laptop, Loc.t("Passage published. Requests will come in over the next hours.") if result.ok else String(result.error)))


static func _show_offer(laptop: LaptopView, page: VBoxContainer, book: PassageBook, offer: Dictionary) -> void:
	var stops: Array = offer.stops
	var names: Array[String] = []
	for id: Variant in stops:
		names.append(_port(id))
	laptop._text(page, &"Route", " → ".join(names), &"HeaderLabel")
	laptop._text(page, &"Window", Loc.t("Leaves %s between %s and %s; %s per nm and person.") % [_port(stops[0]),
		Simulation.format_game_time(float(offer.depart_after), false), Simulation.format_game_time(float(offer.depart_before), false),
		"€%.2f" % float(offer.rate)], &"MutedLabel")
	var legs := VBoxContainer.new()
	legs.name = "Legs"
	page.add_child(legs)
	for i in (offer.leg_nm as Array).size():
		var used := Marketplace.occupancy(book, String(offer.id), i)
		var overnight := Marketplace.leg_nights(float(offer.leg_s[i])) > 0
		var room := Accommodation.overnight_guest_count(StringName(offer.vessel)) if overnight else Accommodation.safe_guest_count(StringName(offer.vessel))
		var done := i < int(offer.stop_index)
		laptop._text(legs, StringName("Leg%d" % i), Loc.t("%s → %s: %.0f nm, about %s%s · %d/%d aboard%s") % [names[i], names[i + 1], float(offer.leg_nm[i]),
			Simulation.format_duration(float(offer.leg_s[i])), Loc.t(", overnight") if overnight else "", used.x, room,
			Loc.t(" · sailed") if done else ""], &"MutedLabel" if done else &"")
	for booking: Dictionary in book.bookings_for_offer(String(offer.id), true):
		if booking.status == PassageBook.BOOKING_CANCELLED:
			continue
		_booking_card(laptop, page, book, offer, booking)
	if offer.status == PassageBook.STATUS_PUBLISHED:
		laptop._action(page, "WithdrawButton", "Withdraw this passage", func() -> void:
			var error := GameSession.cancel_passage_offer(String(offer.id))
			_refresh(laptop, error if error != "" else Loc.t("Passage withdrawn; deposits returned.")))


static func _booking_card(laptop: LaptopView, page: VBoxContainer, book: PassageBook, offer: Dictionary, booking: Dictionary) -> void:
	var traveller := book.get_traveller(String(booking.traveller))
	var card := PanelContainer.new()
	card.name = "Booking_%s" % booking.id
	card.theme_type_variation = &"SectionPanel"
	page.add_child(card)
	var box := VBoxContainer.new()
	card.add_child(box)
	var status: String = {PassageBook.BOOKING_CONFIRMED: Loc.t("booked"), PassageBook.BOOKING_ABOARD: Loc.t("aboard"),
		PassageBook.BOOKING_COMPLETED: Loc.t("ashore, settled")}.get(String(booking.status), String(booking.status))
	laptop._text(box, &"Who", "%s · %s" % [Travellers.display_name(traveller), status], &"HeaderLabel")
	laptop._text(box, &"Terms", Loc.t("%s to %s · fare %s, deposit %s paid · arrival promised by %s") % [_port(booking.embark), _port(booking.disembark),
		GameSession.format_money(int(booking.fare)), GameSession.format_money(int(booking.deposit)),
		Simulation.format_game_time(float(booking.promised), false)], &"MutedLabel")
	if String(booking.disembark) != String(booking.original_disembark):
		laptop._text(box, &"Alternate", Loc.t("Agreed instead of %s.") % _port(booking.original_disembark), &"MutedLabel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	if booking.status == PassageBook.BOOKING_CONFIRMED:
		laptop._action(row, "CancelButton", "Cancel booking", func() -> void:
			var error := GameSession.cancel_passage_booking(String(booking.id))
			_refresh(laptop, error if error != "" else Loc.t("Booking cancelled; the deposit was returned.")))
	if booking.status in [PassageBook.BOOKING_CONFIRMED, PassageBook.BOOKING_ABOARD]:
		var choices := _alternate_choices(offer, booking)
		if not choices.is_empty():
			var pick := OptionButton.new()
			pick.name = "AlternatePick"
			for id: StringName in choices:
				pick.add_item("%s (%s)" % [_port(id), TransferAccess.describe(id)])
			row.add_child(pick)
			laptop._action(row, "AlternateButton", "Propose this harbour", func() -> void:
				var answer := GameSession.propose_alternate_harbour(String(booking.id), choices[pick.selected])
				_refresh(laptop, String(answer.text)))


## Harbours a passenger might accept instead: the passage's other stops after
## where the boat is, and harbours along the course to their own harbour.
static func _alternate_choices(offer: Dictionary, booking: Dictionary) -> Array[StringName]:
	var found: Array[StringName] = []
	var stops: Array = offer.stops
	for i in range(int(offer.stop_index) + 1, stops.size()):
		if String(stops[i]) != String(booking.disembark):
			found.append(StringName(stops[i]))
	var route := GameSession.get_planned_route() if not GameSession.is_underway() else (GameSession.get_voyage().route if GameSession.get_voyage() else null)
	for id in Marketplace.candidate_stops(route):
		if not id in found and String(id) != String(booking.disembark):
			found.append(id)
	return found.slice(0, 6)


# --- Requests ---------------------------------------------------------------------

static func _build_requests(laptop: LaptopView, page: VBoxContainer, book: PassageBook) -> void:
	var open := GameSession.get_passage_requests()
	var lost := GameSession.get_passage_requests(true).filter(func(r: Dictionary) -> bool: return r.status == PassageBook.REQUEST_LOST)
	if open.is_empty() and lost.is_empty():
		return
	laptop._heading(page, "Requests")
	for request: Dictionary in open:
		var traveller := book.get_traveller(String(request.traveller))
		var offer := book.get_offer(String(request.offer))
		var card := PanelContainer.new()
		card.name = "Request_%s" % request.id
		card.theme_type_variation = &"SectionPanel"
		page.add_child(card)
		var box := VBoxContainer.new()
		card.add_child(box)
		laptop._text(box, &"Who", Travellers.display_name(traveller), &"HeaderLabel")
		laptop._text(box, &"About", "%s, %s." % [Travellers.background_text(traveller), Travellers.motivation_text(traveller)])
		laptop._text(box, &"Traits", Travellers.describe_traits(traveller), &"MutedLabel")
		var legs_text := Loc.t("%s to %s") % [_port(offer.stops[int(request.from)]), _port(offer.stops[int(request.to)])]
		laptop._text(box, &"Trip", Loc.t("%s · %s · offers %s (your price %s)%s") % [legs_text, Loc.n("%d person", "%d people", int(request.size)) % int(request.size),
			GameSession.format_money(int(request.offered)), GameSession.format_money(int(request.asked)),
			Loc.t(" · their final offer") if request.status == PassageBook.REQUEST_COUNTERED else ""], &"MutedLabel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		laptop._action(row, "AcceptButton", "Accept", func() -> void:
			_refresh(laptop, String(GameSession.answer_passage_request(String(request.id), true).text)))
		laptop._action(row, "DeclineButton", "Decline", func() -> void:
			_refresh(laptop, String(GameSession.answer_passage_request(String(request.id), false).text)))
		if request.status == PassageBook.REQUEST_PENDING:
			var ask := SpinBox.new()
			ask.name = "Ask"
			ask.min_value = 5
			ask.max_value = 100000
			ask.step = 5
			ask.value = int(request.asked)
			ask.prefix = "€"
			row.add_child(ask)
			laptop._action(row, "AskButton", "Ask this price", func() -> void:
				_refresh(laptop, String(GameSession.answer_passage_request(String(request.id), true, int(ask.value)).text)))
	for request: Dictionary in lost.slice(0, 4):
		var traveller := book.get_traveller(String(request.traveller))
		laptop._text(page, StringName("Lost_%s" % request.id), "%s %s." % [Travellers.display_name(traveller), String(request.note)], &"MutedLabel")


# --- The ledger and the other skippers --------------------------------------------

static func _build_records(laptop: LaptopView, page: VBoxContainer, book: PassageBook) -> void:
	if book.records.is_empty():
		return
	laptop._heading(page, "Recent passengers")
	var recent := book.records.slice(maxi(book.records.size() - 6, 0))
	recent.reverse()
	for record: Dictionary in recent:
		laptop._text(page, StringName("Record_%s" % record.id), Loc.t("%s · %s to %s · %s · paid %s%s") % [record.name, _port(record.embark),
			_port(record.disembark), "★".repeat(int(record.stars)), GameSession.format_money(int(record.paid)),
			(Loc.t(", tip %s") % GameSession.format_money(int(record.tip))) if int(record.tip) > 0 else ""])
		laptop._text(page, StringName("Review_%s" % record.id), "“%s”" % Loc.t(String(record.review)), &"MutedLabel")


static func _build_rivals(laptop: LaptopView, page: VBoxContainer, book: PassageBook) -> void:
	laptop._heading(page, "Other skippers")
	for skipper: Dictionary in Marketplace.skippers():
		var won := int((book.rivals.get(String(skipper.id), {}) as Dictionary).get("won", 0))
		laptop._text(page, StringName("Skipper_%s" % skipper.id), Loc.t("%s · %s (%s) · %.1f ★ · %s%s") % [skipper.name, skipper.yacht, skipper.model,
			float(skipper.rating), Loc.t({"budget": "good value", "comfort": "comfort", "pets": "animals welcome", "family": "families",
				"expedition": "expeditions"}.get(String(skipper.speciality), "")),
			(Loc.t(" · won %d of your travellers") % won) if won > 0 else ""], &"MutedLabel")
