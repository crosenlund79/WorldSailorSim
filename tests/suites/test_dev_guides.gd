extends RefCounted
## Iteration 004b: the developer guides (DEV_GUIDES/) and the in-game viewer.
## Every link and repository path in the guides exists; the viewer opens from
## the main menu (development builds), lists and shows the guides, scrolls,
## closes, and copes with missing files.

const APP_SCENE := preload("res://src/app/app.tscn")
const GUIDES := ["README.md", "SPRITES.md", "COMPANION_ANIMATION.md", "VESSEL_ART.md", "AUDIO.md", "WEATHER.md", "CAPTAINS_HAT.md", "HARBOURS.md", "LIFE_ABOARD.md", "BOAT_CARE.md", "CHART_REGIONS.md", "MODDING_FUTURE.md", "ART_DIRECTION.md"]
## Documents whose Markdown links are checked.
const LINKED_DOCS := ["res://README.md", "res://docs/README.md", "res://docs/technical/ARCHITECTURE.md", "res://docs/artwork/ART_PIPELINE.md",
	"res://docs/iterations/i004/ITERATION_004B_REPORT.md", "res://docs/iterations/i005/ITERATION_005A_REPORT.md",
	"res://docs/iterations/i005/ITERATION_005B_REPORT.md", "res://docs/iterations/i005/ITERATION_005C_REPORT.md", "res://docs/iterations/i005/WINDOWS_ACCEPTANCE_I005.md",
	"res://docs/iterations/i006/ITERATION_006_REPORT.md", "res://docs/iterations/i006/WINDOWS_ACCEPTANCE_I006.md", "res://docs/revisions/v0.100a/VISUAL_IDENTITY_V01_REPORT.md",
	"res://docs/revisions/v0.100a/WINDOWS_ACCEPTANCE_VISUAL_V01.md"]
const PATH_ROOTS := ["assets/", "data/", "src/", "tools/", "tests/", "Visuals/", "DEV_GUIDES/", "docs/"]

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_files_and_links()
	_test_markdown_conversion()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_viewer()
	await _test_missing_guides()
	app.queue_free()
	await t.frames(2)


func _test_files_and_links() -> void:
	for file in GUIDES:
		t.check(FileAccess.file_exists("res://DEV_GUIDES/" + file), "[guides] DEV_GUIDES/%s exists" % file)
	var index := FileAccess.get_file_as_string("res://DEV_GUIDES/README.md")
	for file in GUIDES.slice(1):
		t.check(index.contains("(%s)" % file), "[guides] the index links %s" % file)
	t.check(FileAccess.get_file_as_string("res://README.md").contains("DEV_GUIDES/README.md"), "[guides] README.md links the guide index")
	t.check(FileAccess.get_file_as_string("res://docs/technical/ARCHITECTURE.md").contains("DEV_GUIDES/"), "[guides] docs/technical/ARCHITECTURE.md points to DEV_GUIDES")
	var docs: Array = LINKED_DOCS.duplicate()
	for file in GUIDES:
		docs.append("res://DEV_GUIDES/" + file)
	var link := RegEx.create_from_string("\\]\\(([^)\\s]+)\\)")
	var code := RegEx.create_from_string("`([^`\\s]+)`")
	for doc: String in docs:
		if not FileAccess.file_exists(doc):
			t.check(false, "[guides] %s exists" % doc)
			continue
		var text := FileAccess.get_file_as_string(doc)
		var broken := []
		for m in link.search_all(text):
			var target := m.get_string(1)
			if target.begins_with("http") or target.begins_with("#") or target.begins_with("mailto:"):
				continue
			target = target.split("#")[0]
			var path := doc.get_base_dir().path_join(target).simplify_path()
			if not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
				broken.append(target)
		t.check(broken.is_empty(), "[guides] every link in %s resolves %s" % [doc.get_file(), broken if broken else ""])
		if not doc.contains("DEV_GUIDES"):
			continue
		var missing := []
		for m in code.search_all(text):
			var token := m.get_string(1).trim_prefix("res://")
			if "<" in token or "*" in token or "|" in token or not PATH_ROOTS.any(func(r: String) -> bool: return token.begins_with(r)):
				continue
			var path := "res://" + token.trim_suffix("/")
			if not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
				missing.append(token)
		t.check(missing.is_empty(), "[guides] every repository path in %s exists %s" % [doc.get_file(), missing if missing else ""])


func _test_markdown_conversion() -> void:
	var bb := MarkdownLite.to_bbcode("# Title\n\nSome **bold**, *italic* and `code [x]`.\n\n- item\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```\nraw [text]\n```\n[link](SPRITES.md)")
	t.check(bb.contains("[b]Title[/b]") and bb.contains("[b]bold[/b]") and bb.contains("[i]italic[/i]"), "[guides] headings and emphasis convert")
	t.check(bb.contains("[code]code [lb]x][/code]") and bb.contains("[code]raw [lb]text][/code]"),
		"[guides] code is shown literally (brackets escaped)")
	t.check(bb.contains("•  item") and bb.contains("1") and not bb.contains("---"), "[guides] lists and tables are readable")
	t.check(bb.contains("link[/color] (SPRITES.md)") and MarkdownLite.to_bbcode("[SPRITES.md](SPRITES.md)").count("SPRITES.md") == 1,
		"[guides] links show their text and, when different, their target")


func _test_viewer() -> void:
	var menu := app.router.current_screen as MainMenu
	t.check(DevGuides.is_available(), "[guides] available when running from the project (debug build)")
	var button := menu.find_child("DevGuidesButton", true, false) as Button
	t.check(button != null and button.is_visible_in_tree(), "[guides] the main menu offers 'Developer guides'")
	await t.click(button)
	await t.frames(3)
	var viewer := app.modals.get_top() as DevGuidesMenu
	if not t.check(viewer != null, "[guides] the guide viewer opens"):
		return
	t.check_eq(viewer.guides.size(), GUIDES.size(), "[guides] it lists the %d guides" % GUIDES.size())
	var titles := viewer.guides.map(func(g: Dictionary) -> String: return g.title)
	t.check(titles[0] == "Developer guides" and "Companion artwork and poses" in titles, "[guides] by title, index first (%s)" % ", ".join(titles))
	var content := viewer.find_child("Content", true, false) as RichTextLabel
	t.check(content.get_parsed_text().contains("Where things belong"), "[guides] the index is shown as readable text")
	var companion_button := viewer.find_child("COMPANION_ANIMATION", true, false) as Button
	await t.click(companion_button)
	await t.frames(3)
	t.check((viewer.find_child("GuideTitle", true, false) as Label).text == "Companion artwork and poses"
		and content.get_parsed_text().contains("Visuals/Cat/Cat_resting.png") and not content.get_parsed_text().contains("**"),
		"[guides] choosing a guide shows it, formatted")
	t.check(not content.get_parsed_text().contains("[") and content.get_parsed_text().contains("--only=companion"),
		"[guides] no markup is left in the displayed text; commands keep their characters")
	var features := (content.get_theme_font(&"mono_font") as FontVariation).opentype_features if content.get_theme_font(&"mono_font") is FontVariation else {}
	t.check(features.values().has(0) and features.size() == 3, "[guides] font ligatures are off in the viewer (so -- stays two hyphens)")
	await t.frames(2)
	var bar := content.get_v_scroll_bar()
	t.check(bar.max_value > bar.page + 1.0, "[guides] long guides scroll (%d of %d px visible)" % [bar.page, bar.max_value])
	bar.value = bar.max_value
	await t.frames(2)
	t.check(bar.value > 0.0, "[guides] scrolling works")
	await t.screenshot("60_dev_guides_viewer")
	await t.click(viewer.find_child("CloseButton", true, false) as Button)
	await t.frames(2)
	t.check(app.modals.is_empty() and app.router.current_screen is MainMenu, "[guides] Close returns to the main menu")
	await t.click(button)
	await t.frames(2)
	await t.press_action(&"pause")
	t.check(app.modals.is_empty(), "[guides] Esc closes it too")


func _test_missing_guides() -> void:
	DevGuides.guides_dir = "res://no_such_guides"
	t.check(not DevGuides.is_available() and DevGuides.list_guides().is_empty(), "[guides] without the files the feature is unavailable")
	app.open_dev_guides()
	await t.frames(2)
	t.check(app.modals.is_empty(), "[guides] and the viewer is not opened")
	var viewer := (load("res://src/ui/dev_guides_menu.tscn") as PackedScene).instantiate() as DevGuidesMenu
	t.add_child(viewer)
	await t.frames(2)
	t.check((viewer.find_child("GuideTitle", true, false) as Label).text == "No developer guides", "[guides] an empty viewer explains why, without errors")
	DevGuides.guides_dir = DevGuides.DEFAULT_DIR
	viewer.show_guide("res://DEV_GUIDES/NOT_THERE.md")
	t.check((viewer.find_child("Content", true, false) as RichTextLabel).get_parsed_text().contains("could not be read"), "[guides] a missing guide file shows a message")
	viewer.queue_free()
	await t.frames(1)


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)
