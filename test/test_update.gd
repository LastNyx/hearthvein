extends GutTest
## Ticket 94: auto-update from GitHub releases. No network: JSON from test/fixtures/release_latest.json (a real
## releases/latest response, users stripped), bytes in temp files, URLs and installs through Main's seams.

const FIXTURE := "res://test/fixtures/release_latest.json"

var dir: String
var cfg: String


func before_each() -> void:
	dir = "/tmp/nyx-flash/hearthvein_upd_%d" % OS.get_process_id()
	cfg = dir + ".cfg"
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(cfg)


func after_each() -> void:
	var d := DirAccess.open(dir)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			DirAccess.remove_absolute(dir.path_join(f))
			f = d.get_next()
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(cfg)


func _json() -> String:
	return FileAccess.get_file_as_string(FIXTURE)


func _settings() -> GameSettings:
	var g := GameSettings.new()
	g.path = cfg
	return g


func _write(name: String, bytes: PackedByteArray) -> String:
	var p := dir.path_join(name)
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return p


func _main(version: String = "1.1.1", kind: String = "other") -> Node:
	var main: Node = load("res://ui/main.tscn").instantiate()
	main.saves_dir = dir
	main.settings_path = cfg
	main.app_version = version
	main.install_kind = kind
	main.update_dir = dir.path_join("updates")
	add_child_autofree(main)
	return main


# ---------------------------------------------------------------- version compare

func test_version_compare() -> void:
	assert_eq(UpdateCheck.compare("1.1.2", "1.1.10"), -1, "numbers, not text")
	assert_eq(UpdateCheck.compare("v1.2.0", "1.2"), 0)
	assert_eq(UpdateCheck.compare("2.0.0", "1.99.99"), 1)
	assert_true(UpdateCheck.is_newer("v1.1.10", "1.1.2"))
	assert_false(UpdateCheck.is_newer("v1.1.2", "1.1.2"))
	assert_false(UpdateCheck.is_newer("v1.2.0-rc1", "1.1.2"), "pre-release tags are ignored")
	assert_false(UpdateCheck.is_newer("nightly", "1.1.2"))


# ---------------------------------------------------------------- release JSON -> offer

func test_install_kind_from_inputs() -> void:
	assert_eq(UpdateCheck.install_kind("Windows", false, ""), "windows")
	assert_eq(UpdateCheck.install_kind("Linux", false, "/x/Hearthvein.AppImage"), "appimage")
	assert_eq(UpdateCheck.install_kind("Linux", false, ""), "other")
	assert_eq(UpdateCheck.install_kind("Linux", true, "/x/a.AppImage"), "other", "the editor never self-updates")
	assert_eq(UpdateCheck.install_kind("Windows", true, ""), "other")
	assert_eq(UpdateCheck.install_kind("macOS", false, ""), "other")


func test_offer_per_install_kind() -> void:
	var exe := UpdateCheck.offer_from_text(_json(), "1.1.1", "windows")
	assert_eq(exe["version"], "1.1.2")
	assert_eq(exe["asset_name"], "Hearthvein-1.1.2-setup.exe")
	assert_eq(exe["asset_size"], 28854277)
	assert_eq(exe["asset_digest"], "sha256:568df3de896c00f4e208bbfcce98189b1f55cd938e009e55afd7083066f9ef7d")
	assert_true(exe["downloadable"])
	assert_true(str(exe["notes"]).contains("Tools tab"))
	var app := UpdateCheck.offer_from_text(_json(), "1.1.1", "appimage")
	assert_eq(app["asset_name"], "Hearthvein-1.1.2-x86_64.AppImage")
	assert_true(str(app["asset_url"]).ends_with("Hearthvein-1.1.2-x86_64.AppImage"))
	var other := UpdateCheck.offer_from_text(_json(), "1.1.1", "other")
	assert_false(other["downloadable"])
	assert_true(str(other["html_url"]).ends_with("/tag/v1.1.2"))
	assert_true(UpdateCheck.offer_from_text(_json(), "1.1.2", "windows").is_empty(), "same version: nothing")
	assert_true(UpdateCheck.offer_from_text(_json(), "1.2.0", "windows").is_empty(), "older release: nothing")
	assert_true(UpdateCheck.offer_from_text("not json", "1.0.0", "windows").is_empty())


func test_missing_asset_and_prerelease() -> void:
	var d: Dictionary = JSON.parse_string(_json())
	d["assets"] = []
	var o := UpdateCheck.offer_from_text(JSON.stringify(d), "1.1.1", "appimage")
	assert_eq(o["version"], "1.1.2", "still offered")
	assert_false(o["downloadable"], "but only through the download page")
	d = JSON.parse_string(_json())
	d["prerelease"] = true
	assert_true(UpdateCheck.offer_from_text(JSON.stringify(d), "1.1.1", "windows").is_empty())


# ---------------------------------------------------------------- throttle, toggle, skipped

func test_throttle_toggle_and_skipped() -> void:
	var s := _settings()
	assert_true(UpdateCheck.should_check(s, 1_000_000), "never checked")
	s.update_last_check = 1_000_000
	assert_true(UpdateCheck.should_check(s, 1_000_000 + 60), "checks on every launch, even a minute after the last")
	s.check_updates = false
	assert_false(UpdateCheck.should_check(s, 1_000_000 + 99 * 3600), "toggle off")
	s.check_updates = true
	s.update_skipped_version = "1.1.2"
	var o := UpdateCheck.offer_from_text(_json(), "1.1.1", "other")
	assert_true(UpdateCheck.is_skipped(o, s))
	s.update_skipped_version = "1.1.1"
	assert_false(UpdateCheck.is_skipped(o, s))


func test_settings_round_trip() -> void:
	var a := _settings()
	a.check_updates = false
	a.update_last_check = 1_700_000_000
	a.update_skipped_version = "1.2.3"
	assert_eq(a.save(), OK)
	var b := _settings()
	b.load_file()
	assert_false(b.check_updates)
	assert_eq(b.update_last_check, 1_700_000_000)
	assert_eq(b.update_skipped_version, "1.2.3")
	assert_true(_settings().check_updates, "default on")


# ---------------------------------------------------------------- download verify

func test_verify_size_and_digest() -> void:
	var bytes := "fake installer".to_utf8_buffer()
	var p := _write("a.bin", bytes)
	var sha := FileAccess.get_sha256(p)
	assert_eq(UpdateCheck.verify_file(p, bytes.size(), "sha256:" + sha), "")
	assert_true(FileAccess.file_exists(p), "a good file stays")
	assert_ne(UpdateCheck.verify_file(p, bytes.size() + 1, ""), "", "wrong size")
	assert_false(FileAccess.file_exists(p), "a failed file is deleted")
	p = _write("b.bin", bytes)
	assert_ne(UpdateCheck.verify_file(p, bytes.size(), "sha256:" + "0".repeat(64)), "", "wrong digest")
	assert_false(FileAccess.file_exists(p))
	p = _write("c.bin", bytes)
	assert_eq(UpdateCheck.verify_file(p, 0, ""), "", "no size and no digest: nothing to check")
	assert_ne(UpdateCheck.verify_file(dir.path_join("nope"), 0, ""), "", "missing file")


func test_replace_file_makes_executable_and_swaps() -> void:
	var target := _write("game.AppImage", "old".to_utf8_buffer())
	var fresh := _write("game.AppImage.new", "new".to_utf8_buffer())
	assert_eq(UpdateCheck.replace_file(fresh, target), "")
	assert_eq(FileAccess.get_file_as_string(target), "new")
	assert_false(FileAccess.file_exists(fresh))
	assert_true(FileAccess.get_unix_permissions(target) & 0x40 != 0, "executable")
	assert_ne(UpdateCheck.replace_file(dir.path_join("gone.new"), target), "", "failure reports and keeps the old file")
	assert_eq(FileAccess.get_file_as_string(target), "new")


# ---------------------------------------------------------------- UI

func test_title_button_panel_and_buttons_by_kind() -> void:
	var main := _main("1.1.1", "windows")
	var title := main.get_node("TitleScreen") as TitleScreen
	assert_null(title.update_button, "no offer, no button")
	main.show_update_offer(UpdateCheck.offer_from_text(_json(), "1.1.1", "windows"))
	assert_eq(title.update_button.text, "Update 1.1.2 available")
	title.update_button.pressed.emit()
	var panel := main.get_node("UpdatePanel") as UpdatePanel
	assert_true(panel.text_label.text.contains("Tools tab"), "release notes")
	assert_eq(panel.primary_button.text, "Download and install")
	assert_eq(panel.skip_button.text, "Skip this version")
	panel.later_button.pressed.emit()
	assert_null(main.get_node_or_null("UpdatePanel"), "Later closes")
	assert_not_null(title.update_button, "and the button stays")
	main.install_kind = "appimage"
	main.show_update_offer(UpdateCheck.offer_from_text(_json(), "1.1.1", "appimage"))
	main.open_update_panel()
	assert_eq(main.get_node("UpdatePanel").primary_button.text, "Download and restart")
	main.close_update_panel()
	main.show_update_offer(UpdateCheck.offer_from_text(_json(), "1.1.1", "other"))
	main.open_update_panel()
	var other: UpdatePanel = main.get_node("UpdatePanel")
	assert_eq(other.primary_button.text, "Open download page")
	var opened: Array[String] = []
	main.open_fn = func(u: String) -> void: opened.append(u)
	other.primary_button.pressed.emit()
	assert_eq(opened.size(), 1)
	assert_true(opened[0].ends_with("/tag/v1.1.2"))


func test_skip_this_version() -> void:
	var main := _main()
	main.show_update_offer(UpdateCheck.offer_from_text(_json(), "1.1.1", "other"))
	main.open_update_panel()
	main.get_node("UpdatePanel").skip_button.pressed.emit()
	assert_null(main.get_node_or_null("UpdatePanel"))
	assert_null(main.title_screen.update_button, "button gone")
	var s := _settings()
	s.load_file()
	assert_eq(s.update_skipped_version, "1.1.2", "saved")
	main.show_update_offer(UpdateCheck.offer_from_text(_json(), "1.1.1", "other"))
	assert_true(main.update_offer.is_empty(), "the same version is not offered again")


func test_settings_toggle() -> void:
	var s := _settings()
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	panel.setup(s)
	var box := panel.get_node("UpdatesToggle") as CheckBox
	assert_eq(box.text, "Check for updates")
	assert_true(box.button_pressed)
	box.button_pressed = false
	panel.set_check_updates(false)
	var back := _settings()
	back.load_file()
	assert_false(back.check_updates)


func test_failed_download_shows_error_and_page_button() -> void:
	var main := _main("1.1.1", "windows")
	var offer := UpdateCheck.offer_from_text(_json(), "1.1.1", "windows")
	offer["asset_url"] = "http://127.0.0.1:1/none"  # nothing listens: the download fails, no real network
	main.show_update_offer(offer)
	main.open_update_panel()
	var panel: UpdatePanel = main.get_node("UpdatePanel")
	panel.primary_button.pressed.emit()
	assert_true(panel.progress_bar.visible or panel.primary_button.disabled, "busy while downloading")
	await wait_for_signal(main.updater.download_done, 10.0)
	assert_true(panel.message_label.visible, "error shown")
	assert_true(panel.page_button.visible, "download page offered")
	assert_false(panel.primary_button.disabled)
	assert_false(FileAccess.file_exists(main.update_dir.path_join("Hearthvein-1.1.2-setup.exe")), "no partial file")


func test_finished_download_installs_and_quits() -> void:
	var main := _main("1.1.1", "appimage")
	var app := _write("Hearthvein.AppImage", "old".to_utf8_buffer())
	main.appimage_path = app
	var launched: Array[String] = []
	var quits: Array[bool] = []
	main.launch_fn = func(p: String) -> void: launched.append(p)
	main.quit_fn = func() -> void: quits.append(true)
	main.show_update_offer(UpdateCheck.offer_from_text(_json(), "1.1.1", "appimage"))
	main.open_update_panel()
	_write("Hearthvein.AppImage.new", "new".to_utf8_buffer())
	main._updating = true
	main._on_update_downloaded("", app + ".new")
	assert_eq(FileAccess.get_file_as_string(app), "new")
	assert_eq(launched, [app])
	assert_eq(quits.size(), 1)
