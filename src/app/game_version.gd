class_name GameVersion
extends RefCounted
## The game's version, in one place.
##
## The owner's player-facing convention is 0.<milestone><letter>: 0.100a,
## 0.100b (fixes and refinements within a milestone), 0.101a (the next
## feature milestone), 0.200a (a large step). DISPLAY is that string; it is
## also project.godot's application/config/version (saves record it), and a
## test keeps the two equal. MACHINE is the same version for tools that need
## numbers only (letter a = 1, b = 2, ...), e.g. a Windows file version.
##
## The version is independent of the save format (SaveManager.SAVE_VERSION).

const DISPLAY := "0.113a"

## The game's public name, in one place (I027): the title screen, the loading
## and boot screens, the window title (project.godot's application/config/name,
## kept equal by test_branding), the opening story and the diagnostics read it.
## "Between Horizons" is the Captain's creative WORKING TITLE: a released game
## already has that name, so it is not cleared for store pages, installers or
## other public metadata - ask the Captain before any of those. The technical
## identifiers stay as they were: the save folder ("Little Captains Hat"),
## the repository, the internal ids and the save keys.
const DISPLAY_NAME := "Between Horizons"
## Its wordmark (tools/branding/make_horizon_branding.py).
const LOGO_PATH := "res://assets/branding/between_horizons_logo.svg"
const LOGO_SMALL_PATH := "res://assets/branding/png/between_horizons_logo_480.png"
## One line under the name (the last line of the opening story).
const TAGLINE := "The next horizon is yours to discover."
const MACHINE := "0.113.1"

## The development build identity (the label in the window's bottom-right
## corner, BuildLabel): which major iteration this checkpoint belongs to, an
## optional internal stage of it, and its channel. Committed with the code, so
## every checkout - a historical release branch too - names itself, never the
## iteration currently in development. Updated by hand at each checkpoint (see
## the Captain's Orders, *Major iteration branches*):
##   ITERATION "i024"   the major iteration (lower-case i, three digits);
##                      "" = not known: the label says so honestly
##   STAGE "" or "02"   an internal stage of it (shown as i024_02)
##   CHANNEL DEV        work in progress; TEST = the verified snapshot that a
##                      release/iNNN branch points at
## The build label's project code: "BH" for Between Horizons, the working
## title since I027 (it was "LCH", Little Captain's Hat, until I026; older
## release branches keep their own).
const PROJECT_CODE := "BH"
const ITERATION := "i027"
const STAGE := "03"
const CHANNEL := "DEV"
const CHANNELS: Array[String] = ["DEV", "TEST"]
## Project setting that shows or hides the label (true by default). A public
## export turns it off with a feature-tag override in project.godot:
## application/config/show_build_label.public_release=false
const SHOW_LABEL_SETTING := "application/config/show_build_label"
## Written by tools/write_build_info.py before an export (optional); in a run
## from the project the commit is read from the checkout's .git instead.
const BUILD_INFO_PATH := "res://build_info.json"

static var _commit := ""


## "i024" or "i024_02" (STAGE set), or "" when the iteration is not known.
static func checkpoint() -> String:
	return format_checkpoint(ITERATION, STAGE)


## `iteration` with its `stage` ("i042", "02" -> "i042_02").
static func format_checkpoint(iteration: String, stage: String) -> String:
	if iteration.is_empty():
		return ""
	return iteration if stage.is_empty() else "%s_%s" % [iteration, stage]


## The build label: "BH · i027 · DEV", with the short commit when it is known
## ("BH · i027 · DEV · 1a2b3c4"). Without a known iteration: "BH · dev-build"
## (never an invented or stale number).
static func build_label(with_commit := true) -> String:
	var parts: Array[String] = [PROJECT_CODE]
	var point := checkpoint()
	if point.is_empty():
		parts.append("dev-build")
	else:
		parts.append(point)
		parts.append(CHANNEL if CHANNEL in CHANNELS else "DEV")
	var commit := get_commit() if with_commit else ""
	if not commit.is_empty():
		parts.append(commit)
	return " · ".join(parts)


## Whether the label is shown (the project setting; on unless a public
## export overrides it).
static func shows_build_label() -> bool:
	return bool(ProjectSettings.get_setting(SHOW_LABEL_SETTING, true))


## "0.101a", or "0.101a (1a2b3c4)" when the commit is known.
static func describe() -> String:
	var commit := get_commit()
	return DISPLAY if commit.is_empty() else "%s (%s)" % [DISPLAY, commit]


## The short commit id of this build, or "" when unknown. Read once from
## build_info.json, or from the project's .git files (no git process is run).
static func get_commit() -> String:
	if _commit.is_empty():
		_commit = _read_commit()
		if _commit.is_empty():
			_commit = "-"
	return "" if _commit == "-" else _commit


static func _read_commit() -> String:
	if FileAccess.file_exists(BUILD_INFO_PATH):
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_INFO_PATH))
		if info is Dictionary and info.get("commit") is String:
			return String(info.commit).left(7)
	var head := FileAccess.get_file_as_string("res://.git/HEAD").strip_edges()
	if head.is_empty():
		return ""
	if not head.begins_with("ref: "):
		return head.left(7)
	var ref := head.trim_prefix("ref: ")
	var hash := FileAccess.get_file_as_string("res://.git/" + ref).strip_edges()
	if hash.is_empty():
		for line in FileAccess.get_file_as_string("res://.git/packed-refs").split("\n"):
			if line.ends_with(" " + ref):
				hash = line.get_slice(" ", 0)
	return hash.left(7)
