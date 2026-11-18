extends GutTest
## Ticket 92: the What's new panel (CHANGELOG.md -> BBCode), the auto-open after an update, release_notes.sh.

const MD := "# Changelog\n\nIntro line one\nline two.\n\n## Unreleased\n\n### Added\n- First [x] item that wraps\n  onto a second line.\n- Second item.\n\n### Fixed\n- A fix.\n\n## 1.1.0 - 2026-11-17\n\nPlain paragraph.\n"

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_wn_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(cfg)


func after_each() -> void:
	get_tree().paused = false
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			DirAccess.remove_absolute(dir.path_join(f))
			f = d.get_next()
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


func _main(version: String = "9.9.9") -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	main.app_version = version
	add_child_autofree(main)
	return main


func test_markdown_subset_renders_headings_bullets_and_continuation_lines() -> void:
	var out := ChangelogText.to_bbcode(MD, false)
	assert_string_contains(out, "[font_size=%d]" % ChangelogText.H1_SIZE)
	assert_string_contains(out, "Unreleased[/color][/font_size]")
	assert_string_contains(out, "1.1.0 - 2026-11-17")
	assert_string_contains(out, "Added[/color][/font_size]")
	assert_string_contains(out, "[ul]First [lb]x] item that wraps onto a second line.\nSecond item.[/ul]", "bullets, wrapped line joined, [ escaped")
	assert_string_contains(out, "Intro line one line two.", "paragraph lines joined")
	assert_string_contains(out, "Plain paragraph.")
	assert_false(out.contains("- First"), "no raw Markdown dash left")


func test_unreleased_section_hidden_only_in_exports_when_the_version_has_a_section() -> void:
	assert_true(ChangelogText.hide_unreleased(MD, "1.1.0", false), "export, version in the file")
	assert_false(ChangelogText.hide_unreleased(MD, "1.1.0", true), "editor build shows it")
	assert_false(ChangelogText.hide_unreleased(MD, "2.0.0", false), "export, version not in the file")
	var hidden := ChangelogText.to_bbcode(MD, true)
	assert_false(hidden.contains("Unreleased"))
	assert_false(hidden.contains("First"))
	assert_string_contains(hidden, "Plain paragraph.")


func test_auto_open_first_launch_same_version_and_new_version() -> void:
	var s := GameSettings.new()
	s.path = cfg
	assert_false(ChangelogText.auto_open(s, "1.2.0"), "first launch: only stored")
	assert_eq(s.last_seen_version, "1.2.0")
	assert_false(ChangelogText.auto_open(s, "1.2.0"), "same version")
	assert_true(ChangelogText.auto_open(s, "1.3.0"), "new version opens")
	assert_eq(s.last_seen_version, "1.3.0")
	assert_false(ChangelogText.auto_open(s, "1.3.0"), "and only once")
	var back := GameSettings.new()
	back.path = cfg
	back.load_file()
	assert_eq(back.last_seen_version, "1.3.0", "written to the file")


func test_title_shows_version_label_and_button_opens_panel_esc_closes() -> void:
	var main := _main("1.2.3")
	await wait_process_frames(3)
	var title := main.get_node("TitleScreen")
	assert_eq((title.find_child("VersionLabel", true, false) as Label).text, "v1.2.3")
	var order: Array[String] = []
	for c in title.find_child("Milestones", true, false).get_parent().get_children():
		order.append(c.name)
	assert_eq(order[order.find("Milestones") + 1], "WhatsNew", "below Milestones")
	assert_null(main.get_node_or_null("WhatsNewPanel"), "first launch does not auto-open")
	(title.find_child("WhatsNew", true, false) as Button).pressed.emit()
	var panel := main.get_node("WhatsNewPanel") as WhatsNewPanel
	assert_string_contains(panel.text_label.get_parsed_text(), "Added")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	main._input(esc)
	await wait_process_frames(1)
	assert_null(main.get_node_or_null("WhatsNewPanel"), "Esc closes")
	(title.find_child("WhatsNew", true, false) as Button).pressed.emit()
	main.get_node("WhatsNewPanel").back_button.pressed.emit()
	await wait_process_frames(1)
	assert_null(main.get_node_or_null("WhatsNewPanel"), "Back closes")


func test_panel_opens_by_itself_after_an_update() -> void:
	var s := GameSettings.new()
	s.path = cfg
	s.last_seen_version = "0.0.1"
	s.save()
	var main := _main("1.2.3")
	await wait_process_frames(3)
	assert_not_null(main.get_node_or_null("WhatsNewPanel"))
	assert_eq(main.settings.last_seen_version, "1.2.3")


func _run_notes(args: Array[String]) -> Dictionary:
	var out: Array = []
	var code := OS.execute("bash", [ProjectSettings.globalize_path("res://packaging/release_notes.sh")] + args, out)
	return {"code": code, "out": out[0] if out.size() > 0 else ""}


func test_release_notes_prints_the_1_1_0_section_exactly() -> void:
	var r := _run_notes(["1.1.0"])
	assert_eq(r.code, 0)
	var md := FileAccess.get_file_as_string("res://CHANGELOG.md")
	var a := md.find("## 1.1.0 - 2026-11-17\n") + "## 1.1.0 - 2026-11-17\n".length()
	var b := md.find("## 1.0.0")
	var want := md.substr(a, b - a).strip_edges() + "\n"
	assert_eq(r.out, want)
	assert_true(r.out.begins_with("### Added"))
	assert_false(r.out.contains("1.0.0"))


func test_release_notes_fails_for_a_missing_version() -> void:
	assert_ne(_run_notes(["7.7.7"]).code, 0)
	assert_ne(_run_notes(["1.1"]).code, 0, "a prefix of a version is not a section")
	assert_eq(_run_notes(["1.1.1"]).code, 0)


func test_build_sh_checks_the_notes_before_building() -> void:
	var sh := FileAccess.get_file_as_string("res://packaging/build.sh")
	var check := sh.find("release_notes.sh")
	assert_gt(check, -1)
	assert_lt(check, sh.find("rm -rf build"), "the check runs before the build wipes and exports")


func test_export_presets_bundle_the_changelog() -> void:
	var cf := ConfigFile.new()
	assert_eq(cf.load("res://export_presets.cfg"), OK)
	var n := 0
	for sec in cf.get_sections():
		if sec.begins_with("preset.") and not sec.ends_with(".options"):
			n += 1
			assert_string_contains(str(cf.get_value(sec, "include_filter")), "CHANGELOG.md", sec)
	assert_eq(n, 2)
