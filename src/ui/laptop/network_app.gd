class_name NetworkApp
extends RefCounted
## The laptop's Traveller Network (I028 Tier 5): the sailing world's quiet
## feed - departures, arrivals, expeditions and books of the travellers out
## there, and the Captain's own notable passages and published works. Every
## post comes from the world's one event ledger (TravellerNetwork), so it
## agrees with everything else the laptop shows. The Captain can follow a
## traveller and read only the people they follow. No likes to chase, no
## counters: a feed to read with the morning coffee.

const PAGE_SIZE := 18
const IMAGE_SIZE := Vector2(176, 108)

static var following_only := false


static func build(laptop: LaptopView) -> Control:
	var page := laptop._page("Network")
	var filters := HBoxContainer.new()
	filters.name = "Filters"
	filters.add_theme_constant_override("separation", 8)
	page.add_child(filters)
	for choice: Array in [["Everyone", false], ["Following", true]]:
		var button := Button.new()
		button.name = "Filter_%s" % choice[0]
		button.text = Loc.t(String(choice[0]))
		button.toggle_mode = true
		button.set_pressed_no_signal(following_only == bool(choice[1]))
		var only := bool(choice[1])
		button.pressed.connect(func() -> void:
			following_only = only
			laptop.show_app(LaptopView.APP_NETWORK))
		filters.add_child(button)
	var followed := GameSession.get_followed_travellers()
	var posts := GameSession.get_network_posts(PAGE_SIZE, following_only)
	if posts.is_empty():
		laptop._text(page, &"Empty", "Follow a traveller from their posts to see them here." if following_only
			else "Quiet on the network for now. Sail on, and the world will have news.", &"MutedLabel")
	for post: Dictionary in posts:
		_post_card(laptop, page, post, followed)
	return page


static func _post_card(laptop: LaptopView, page: VBoxContainer, post: Dictionary, followed: Array) -> void:
	var card := PanelContainer.new()
	card.name = "Post_%d" % int(post.seq)
	card.theme_type_variation = &"SectionPanel"
	page.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var image := String(post.image)
	if image != "" and ResourceLoader.exists(TravellerNetwork.image_path(image)):
		var picture := TextureRect.new()
		picture.name = "Picture"
		picture.texture = load(TravellerNetwork.image_path(image)) as Texture2D
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.custom_minimum_size = IMAGE_SIZE
		row.add_child(picture)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var mine := String(post.author) == WorldChronicle.CAPTAIN
	var where := TravellerNetwork._place(String(post.port)) if String(post.port) != "" else ""
	var head := laptop._text(box, &"Author", "%s · %s%s" % [Loc.t("You") if mine else String(post.author_name),
		Simulation.format_game_time(float(post.t), false), (" · " + where) if where != "" else ""], &"MutedLabel")
	head.add_theme_color_override(&"font_color", UiTheme.color(&"heading"))
	laptop._text(box, &"Text", String(post.text))
	var notable := not mine and not WorldChronicle.population().has(String(post.author))
	if notable:
		var is_followed := String(post.author) in followed
		var follow := Button.new()
		follow.name = "Follow"
		follow.text = Loc.t("Following ✓") if is_followed else Loc.t("Follow %s") % String(post.author_name).get_slice(" ", 0)
		follow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		follow.flat = true
		var author := String(post.author)
		follow.pressed.connect(func() -> void:
			GameSession.set_following(author, not is_followed)
			laptop.show_app(LaptopView.APP_NETWORK))
		box.add_child(follow)
