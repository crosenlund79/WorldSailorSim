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

const DISPLAY := "0.109a"
const MACHINE := "0.109.1"
## Written by tools/write_build_info.py before an export (optional); in a run
## from the project the commit is read from the checkout's .git instead.
const BUILD_INFO_PATH := "res://build_info.json"

static var _commit := ""


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
