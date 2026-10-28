class_name HandbookMenu
extends SimplePanel
## The Captain's Handbook (I022, The Captain's Academy): every part of the
## game on a short page, by chapter, with a search box. Always at hand: F1, or
## Captain's Handbook in the menu; a tip's "Read more" opens its page. Keys
## in the texts are the game's own bindings (Academy.fill). From here the
## First Voyage can be begun again and the tips shown again.

signal first_voyage_requested

var _search: LineEdit
var _list: ItemList
var _title: Label
var _body: Label
var _ids: Array[String] = []
var _shown := ""


func _ready() -> void:
	_build(Loc.t("Captain's Handbook"), 1160)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = Loc.t("Search the Handbook")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _refresh())
	_box.add_child(_search)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.custom_minimum_size = Vector2(0, 480)
	_box.add_child(row)
	_list = ItemList.new()
	_list.name = "Pages"
	_list.custom_minimum_size = Vector2(360, 480)
	_list.item_selected.connect(func(index: int) -> void:
		var id := String(_list.get_item_metadata(index))
		if not id.is_empty():
			show_page(id))
	row.add_child(_list)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	row.add_child(page)
	_title = Label.new()
	_title.name = "PageTitle"
	_title.theme_type_variation = &"HeaderLabel"
	page.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_body = Label.new()
	_body.name = "PageText"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(700, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_button("FirstVoyageButton", Loc.t("Begin the First Voyage again"), func() -> void:
		Academy.begin_first_voyage()
		first_voyage_requested.emit()
		close(), 260.0)
	var tips := _button("TipsButton", Loc.t("Show the tips again"), func() -> void: pass, 220.0)
	tips.pressed.connect(func() -> void:
		Academy.reset_tips()
		tips.disabled = true
		notify(Loc.t("The tips will show again as you come across each thing.")))
	_button("CloseButton", "Close", close)
	_refresh()
	if not _ids.is_empty():
		show_page(_ids[0])


## The pages listed (after the search), in order.
func listed() -> Array[String]:
	return _ids


func search(query: String) -> void:
	_search.text = query
	_refresh()


func _refresh() -> void:
	_ids = Academy.search(_search.text)
	_list.clear()
	var category := ""
	for id in _ids:
		var entry := Academy.page(id)
		if String(entry.category) != category:
			category = String(entry.category)
			var header := _list.add_item(Academy.category_title(category).to_upper())
			_list.set_item_selectable(header, false)
			_list.set_item_disabled(header, true)
			_list.set_item_metadata(header, "")
		var index := _list.add_item("   " + Loc.t(String(entry.title)))
		_list.set_item_metadata(index, id)
	if _ids.is_empty():
		_title.text = Loc.t("Nothing found")
		_body.text = Loc.t("No page mentions that. Try another word.")
	elif not _ids.has(_shown):
		show_page(_ids[0])
	else:
		_select(_shown)


## Shows page `id` (and selects it in the list).
func show_page(id: String) -> void:
	var entry := Academy.page(id)
	if entry.is_empty():
		return
	_shown = id
	_title.text = Loc.t(String(entry.title))
	_body.text = Academy.fill(String(entry.text))
	_select(id)


func shown_page() -> String:
	return _shown


func _select(id: String) -> void:
	for i in _list.item_count:
		if String(_list.get_item_metadata(i)) == id:
			_list.select(i)
			_list.ensure_current_is_visible()


func focus_default() -> void:
	_search.grab_focus()
