class_name WorldApp
extends RefCounted
## The laptop's World app (I028 Tier 6): the sailing world as the Captain
## reads it. Invitations from well-known travellers at the top when there are
## any; then Sails & Sights (the latest issue and the archive, each issue as
## it was published), the renown rankings (the Captain's place, the top ten,
## the memorable travellers) and the yacht directory (searchable, last
## public reports, unknown and stale ones marked: not a live tracker - live
## positions are only on the radar's AIS). Everything through GameSession.

const SECTIONS := ["Sails & Sights", "Rankings", "Yacht directory"]

static var section := 0
static var issue_index := 0
static var query := ""


static func build(laptop: LaptopView) -> Control:
	var page := laptop._page("World")
	_build_invitations(laptop, page)
	var bar := HBoxContainer.new()
	bar.name = "Sections"
	bar.add_theme_constant_override("separation", 8)
	page.add_child(bar)
	for i in SECTIONS.size():
		var button := Button.new()
		button.name = "Section_%d" % i
		button.text = Loc.t(String(SECTIONS[i]))
		button.toggle_mode = true
		button.set_pressed_no_signal(section == i)
		var index := i
		button.pressed.connect(func() -> void:
			section = index
			laptop.show_app(LaptopView.APP_WORLD))
		bar.add_child(button)
	match section:
		1:
			_build_rankings(laptop, page)
		2:
			_build_directory(laptop, page)
		_:
			_build_magazine(laptop, page)
	return page


static func _place(id: Variant) -> String:
	return TravellerNetwork._place(String(id))


static func _card(page: Control, node_name: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.theme_type_variation = &"SectionPanel"
	page.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	return box


static func _build_invitations(laptop: LaptopView, page: VBoxContainer) -> void:
	for invitation: Dictionary in GameSession.get_invitations():
		var box := _card(page, "Invitation_%s" % invitation.id)
		laptop._heading(box, String(invitation.title))
		laptop._text(box, &"Text", String(invitation.text))
		laptop._text(box, &"Expires", Loc.t("From %s. The invitation stands until %s.") % [_place(invitation.port),
			Simulation.format_game_time(float(invitation.expires), false)], &"MutedLabel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var id := String(invitation.id)
		laptop._action(row, "Accept", "Accept and publish the passage", func() -> void:
			var result := GameSession.accept_invitation(id)
			laptop.notify(Loc.t("Booked: they will be aboard when you sail.") if result.ok else String(result.error))
			laptop.show_app(LaptopView.APP_WORLD))
		laptop._action(row, "Decline", "Decline politely", func() -> void:
			GameSession.decline_invitation(id)
			laptop.show_app(LaptopView.APP_WORLD))


static func _build_magazine(laptop: LaptopView, page: VBoxContainer) -> void:
	var issues := GameSession.get_magazine_issues()
	if issues.is_empty():
		laptop._text(page, &"NoIssue", "The first issue of Sails & Sights comes out at the end of the month.", &"MutedLabel")
		return
	issue_index = clampi(issue_index, 0, issues.size() - 1)
	var issue: Dictionary = issues[issue_index]
	var box := _card(page, "Issue")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var cover := TravellerNetwork.image_path(String(issue.get("cover", "")))
	if cover != "" and ResourceLoader.exists(cover):
		var picture := TextureRect.new()
		picture.name = "Cover"
		picture.texture = load(cover) as Texture2D
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.custom_minimum_size = Vector2(220, 134)
		head.add_child(picture)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	laptop._text(title, &"Masthead", "Sails & Sights", &"HeaderLabel")
	laptop._text(title, &"Number", Loc.t("No. %d · %s %d") % [int(issue.number), Loc.month(int(issue.month)), int(issue.year)], &"MutedLabel")
	if int(issue.get("captain_rank", 0)) > 0:
		laptop._text(title, &"CaptainRank", Loc.t("You are no. %d of %d in this month's renown list.") % [int(issue.captain_rank), int(issue.of)])
	var stories: Array = issue.get("stories", [])
	if stories.is_empty():
		laptop._text(box, &"Quiet", "A quiet month at sea.", &"MutedLabel")
	for story: Dictionary in stories:
		laptop._heading(box, String(story.headline))
		laptop._text(box, &"Story", String(story.text))
	laptop._heading(box, "The month's best-known sailors")
	var top := PackedStringArray()
	for row: Dictionary in issue.get("top", []):
		top.append("%d. %s" % [int(row.rank), Loc.t("You") if row.id == WorldChronicle.CAPTAIN else String(row.name)])
	laptop._text(box, &"Top", " · ".join(top), &"MutedLabel")
	if issues.size() > 1:
		var nav := HBoxContainer.new()
		nav.add_theme_constant_override("separation", 8)
		page.add_child(nav)
		if issue_index < issues.size() - 1:
			laptop._action(nav, "Older", "Older issue", func() -> void:
				issue_index += 1
				laptop.show_app(LaptopView.APP_WORLD))
		if issue_index > 0:
			laptop._action(nav, "Newer", "Newer issue", func() -> void:
				issue_index -= 1
				laptop.show_app(LaptopView.APP_WORLD))


static func _build_rankings(laptop: LaptopView, page: VBoxContainer) -> void:
	var rows := GameSession.get_rankings()
	var standing := GameSession.get_captain_standing()
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 16)
	page.add_child(tiles)
	laptop._tile(tiles, "Your place", "%d" % int(standing.get("rank", 0)), Loc.t("of %d sailors") % int(standing.get("of", 0)))
	laptop._tile(tiles, "Renown", str(int(standing.get("renown", 0))), Loc.t("lasting, and the attention of recent news"))
	var box := _card(page, "Top")
	laptop._heading(box, "The ten best-known")
	for row: Dictionary in rows.slice(0, 10):
		_rank_row(laptop, box, row)
	var mine := int(standing.get("rank", 0))
	if mine > 10:
		var near := _card(page, "Near")
		laptop._heading(near, "Around you")
		for row: Dictionary in rows.slice(maxi(mine - 3, 10), mine + 2):
			_rank_row(laptop, near, row)
	var known := _card(page, "Memorable")
	laptop._heading(known, "Memorable travellers")
	var followed := GameSession.get_followed_travellers()
	for t: Dictionary in WorldChronicle.data().get("travellers", []).slice(0, 30):
		var rank := 0
		for row: Dictionary in rows:
			if row.id == t.id:
				rank = int(row.rank)
		laptop._text(known, &"Traveller", "%s · %s · %s%s" % [String(t.name), Loc.t(String(t.get("speciality", ""))), Loc.t("no. %d") % rank,
			Loc.t(" · following") if String(t.id) in followed else ""], &"MutedLabel")


static func _rank_row(laptop: LaptopView, box: Control, row: Dictionary) -> void:
	var me: bool = row.id == WorldChronicle.CAPTAIN
	var label := laptop._text(box, &"Rank_%d" % int(row.rank), "%d. %s · %s" % [int(row.rank), Loc.t("You") if me else String(row.name), str(int(row.renown))])
	if me:
		label.add_theme_color_override(&"font_color", UiTheme.color(&"heading"))


static func _build_directory(laptop: LaptopView, page: VBoxContainer) -> void:
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = Loc.t("Search by yacht, skipper, model or harbour")
	search.text = query
	search.text_submitted.connect(func(text: String) -> void:
		query = text
		laptop.show_app(LaptopView.APP_WORLD))
	page.add_child(search)
	laptop._text(page, &"Note", "Last public reports from the yachts' own posts. Where a yacht is now, only AIS can tell, within range.", &"MutedLabel")
	var entries := GameSession.get_yacht_directory(query)
	if entries.is_empty():
		laptop._text(page, &"None", "No yacht matches.", &"MutedLabel")
	for entry: Dictionary in entries:
		var box := _card(page, "Yacht_%s" % entry.id)
		laptop._text(box, &"Name", "%s · %s %s · %s" % [entry.name, entry.model, entry.type, entry.skipper], &"HeaderLabel")
		var report: Dictionary = entry.report
		var text := ""
		if entry.unknown:
			text = Loc.t("No public report yet.")
		else:
			match String(report.status):
				"departed":
					text = Loc.t("Left %s for %s") % [_place(report.port), _place(report.to)]
				"announced":
					text = Loc.t("Expedition announced from %s") % _place(report.port)
				_:
					text = Loc.t("In %s") % _place(report.port)
			text += " · " + Simulation.format_game_time(float(report.t), false)
			if entry.stale:
				text += " · " + Loc.t("stale: %d days old") % int(entry.age_days)
		var label := laptop._text(box, &"Report", text, &"MutedLabel")
		if entry.stale or entry.unknown:
			label.add_theme_color_override(&"font_color", UiTheme.color(&"caution"))
		if String(entry.expedition) != "":
			laptop._text(box, &"Expedition", Loc.t("On expedition: %s") % TravellerNetwork._expedition_title(String(entry.expedition)))
