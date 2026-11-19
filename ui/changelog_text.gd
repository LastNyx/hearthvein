class_name ChangelogText
extends RefCounted
## CHANGELOG.md to BBCode for the What's new panel (ticket 92), and the auto-open decision. Pure static helpers: tests
## feed strings. Subset: #/##/### headings, "- " bullets whose continuation lines are indented, plain paragraphs.

const H1_SIZE := 30
const H2_SIZE := 24
const H3_SIZE := 20
const HEADING_COLOR := "#f2d27a"
const UNRELEASED := "Unreleased"


## True when the "Unreleased" section is left out: in an exported build, as long as the file has a section for `version`.
static func hide_unreleased(md: String, version: String, is_editor: bool) -> bool:
	return not is_editor and has_section(md, version)


static func has_section(md: String, version: String) -> bool:
	for line in md.split("\n"):
		if line.begins_with("## ") and (line == "## " + version or line.begins_with("## " + version + " ")):
			return true
	return false


## Drops everything before the first "## " section (the file's "# Changelog" title and intro): the panel has its own
## "What's new" title.
static func drop_preamble(md: String) -> String:
	if md.begins_with("## "):
		return md
	var at := md.find("\n## ")
	return md if at < 0 else md.substr(at + 1)


static func to_bbcode(md: String, hide_unreleased_section: bool) -> String:
	var out: Array[String] = []
	var items: Array[String] = []  # the open bullet list
	var para := ""
	var skipping := false
	for raw in md.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.begins_with("#"):
			para = _flush_para(out, para)
			_flush_list(out, items)
		if line.begins_with("## "):
			skipping = hide_unreleased_section and line.substr(3).strip_edges().begins_with(UNRELEASED)
		elif line.begins_with("# "):
			skipping = false
		if skipping:
			continue
		if line.strip_edges() == "":
			para = _flush_para(out, para)
			_flush_list(out, items)
		elif line.begins_with("#"):
			para = _flush_para(out, para)
			_flush_list(out, items)
			var level := 0
			while level < line.length() and line[level] == "#":
				level += 1
			out.append(_heading(line.substr(level).strip_edges(), level))
		elif line.begins_with("- "):
			para = _flush_para(out, para)
			items.append(_esc(line.substr(2).strip_edges()))
		elif line.begins_with(" ") and not items.is_empty():
			items[items.size() - 1] += " " + _esc(line.strip_edges())
		else:
			_flush_list(out, items)
			para += ("" if para == "" else " ") + _esc(line.strip_edges())
	_flush_para(out, para)
	_flush_list(out, items)
	return "\n".join(out)


## Decides whether the panel opens by itself on launch, and stores `current` as the last seen version (saved when it
## changed). First ever launch (nothing stored): no, just store. Same version: no. A different one: yes.
static func auto_open(settings: GameSettings, current: String) -> bool:
	var last := settings.last_seen_version
	if last == current:
		return false
	settings.last_seen_version = current
	settings.save()
	return last != ""


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func _heading(text: String, level: int) -> String:
	var size := H1_SIZE if level <= 1 else (H2_SIZE if level == 2 else H3_SIZE)
	return "[font_size=%d][color=%s]%s[/color][/font_size]" % [size, HEADING_COLOR, _esc(text)]


static func _flush_para(out: Array[String], para: String) -> String:
	if para != "":
		out.append(para)
	return ""


static func _flush_list(out: Array[String], items: Array[String]) -> void:
	if not items.is_empty():
		out.append("[ul]" + "\n".join(items) + "[/ul]")
		items.clear()
