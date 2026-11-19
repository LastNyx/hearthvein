class_name UpdateCheck
extends Node
## Auto-update from GitHub releases (ticket 94). The static helpers are pure (tests feed JSON, bytes and temp files);
## the node part is the async HTTP: check() asks the releases API, download() fetches an asset to a file. Every
## failure is a log line plus an error string, never a block: the title never waits for this.

signal check_done(offer: Dictionary)
signal progress(fraction: float)
signal download_done(error: String)

const API_URL := "https://api.github.com/repos/LastNyx/hearthvein/releases/latest"
const THROTTLE_SECONDS := 24 * 3600
const TIMEOUT := 10.0

var _http: HTTPRequest
var _dl: HTTPRequest
var _dl_path := ""
var _dl_size := 0
var _dl_digest := ""


# ---------------------------------------------------------------- pure helpers

## "v1.2.10" or "1.2.10" -> [1, 2, 10]. Empty for anything else, pre-release tags ("1.2.0-rc1") included.
static func parse_version(s: String) -> Array[int]:
	var out: Array[int] = []
	var t := s.strip_edges().trim_prefix("v")
	if t == "":
		return out
	for part in t.split("."):
		if not part.is_valid_int() or part.begins_with("-") or part.begins_with("+"):
			return [] as Array[int]
		out.append(part.to_int())
	return out


## -1, 0 or 1 comparing a to b number by number (missing parts count as 0). 0 when either does not parse.
static func compare(a: String, b: String) -> int:
	var x := parse_version(a)
	var y := parse_version(b)
	if x.is_empty() or y.is_empty():
		return 0
	for i in maxi(x.size(), y.size()):
		var p := x[i] if i < x.size() else 0
		var q := y[i] if i < y.size() else 0
		if p != q:
			return -1 if p < q else 1
	return 0


static func is_newer(tag: String, current: String) -> bool:
	return not parse_version(tag).is_empty() and not parse_version(current).is_empty() and compare(tag, current) > 0


## "windows" (exported Windows build), "appimage" (exported Linux with $APPIMAGE) or "other" (editor, tar.gz, unknown).
static func install_kind(os_name: String, is_editor: bool, appimage_env: String) -> String:
	if is_editor:
		return "other"
	if os_name == "Windows":
		return "windows"
	if os_name == "Linux" and appimage_env != "":
		return "appimage"
	return "other"


static func asset_name(kind: String, version: String) -> String:
	match kind:
		"windows":
			return "Hearthvein-%s-setup.exe" % version
		"appimage":
			return "Hearthvein-%s-x86_64.AppImage" % version
	return ""


## The releases API text -> an offer, or {} (not JSON, draft, pre-release, not newer). The offer: version, notes (the
## release body), html_url, kind and downloadable; when the install kind has an asset in the release also asset_name,
## asset_url, asset_size, asset_digest ("" when the API gives none). No asset: downloadable false (page button only).
static func offer_from_text(text: String, current: String, kind: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:  # an instance: no engine error line on bad text
		return {}
	var d: Dictionary = json.data
	if d.get("draft", false) == true or d.get("prerelease", false) == true:
		return {}
	var tag := str(d.get("tag_name", ""))
	if not is_newer(tag, current):
		return {}
	var version := ".".join(PackedStringArray(parse_version(tag).map(func(n: int) -> String: return str(n))))
	var offer := {
		"version": version, "notes": str(d.get("body", "")), "html_url": str(d.get("html_url", "")),
		"kind": kind, "downloadable": false,
	}
	var want := asset_name(kind, version)
	var assets: Variant = d.get("assets", [])
	if want != "" and assets is Array:
		for a: Variant in assets:
			if a is Dictionary and str((a as Dictionary).get("name", "")) == want:
				var ad: Dictionary = a
				var url := str(ad.get("browser_download_url", ""))
				if url != "":
					offer["asset_name"] = want
					offer["asset_url"] = url
					offer["asset_size"] = int(ad.get("size", 0))
					offer["asset_digest"] = str(ad.get("digest", ""))
					offer["downloadable"] = true
				break
	return offer


## Whether to ask GitHub now: the toggle is on and the last check was 24 h or more ago (a clock set back counts as due).
static func should_check(settings: GameSettings, now: int) -> bool:
	if not settings.check_updates:
		return false
	return now < settings.update_last_check or now - settings.update_last_check >= THROTTLE_SECONDS


static func is_skipped(offer: Dictionary, settings: GameSettings) -> bool:
	return not offer.is_empty() and str(offer.get("version", "")) == settings.update_skipped_version


## Checks a downloaded file: size (when known) and sha256 ("sha256:<hex>" or bare hex, when given). Returns "" when
## fine, else the reason. A failed file is deleted.
static func verify_file(path: String, size: int, digest: String) -> String:
	var err := ""
	if not FileAccess.file_exists(path):
		err = "The download is missing."
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		var got := f.get_length() if f != null else -1
		f = null
		if size > 0 and got != size:
			err = "The download is the wrong size (%d bytes, expected %d)." % [got, size]
		elif digest != "":
			var want := digest.trim_prefix("sha256:").to_lower()
			if FileAccess.get_sha256(path) != want:
				err = "The download is damaged (checksum mismatch)."
	if err != "":
		DirAccess.remove_absolute(path)
	return err


## chmod +x the verified `new_path` and rename it over `target` (the running AppImage). "" or the reason; the .new file
## is deleted on failure.
static func replace_file(new_path: String, target: String) -> String:
	var out: Array = []
	if OS.execute("chmod", ["+x", new_path], out) != 0:
		DirAccess.remove_absolute(new_path)
		return "Could not make the new version executable."
	if DirAccess.rename_absolute(new_path, target) != OK:
		DirAccess.remove_absolute(new_path)
		return "Could not replace the old version."
	return ""


# ---------------------------------------------------------------- async HTTP

static func _headers() -> PackedStringArray:
	return PackedStringArray(["User-Agent: Hearthvein/%s" % str(ProjectSettings.get_setting("application/config/version", "")),
		"Accept: application/vnd.github+json"])


## Asks `url` for the latest release; emits check_done with the offer or {} (also after any failure, with a log line).
func check(url: String, current: String, kind: String) -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		_http.queue_free()
		_http = null
		var offer := {}
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("Update check failed (result %d, HTTP %d)" % [result, code])
		else:
			offer = offer_from_text(body.get_string_from_utf8(), current, kind)
		check_done.emit(offer))
	if _http.request(url, _headers()) != OK:
		push_warning("Update check could not start")
		_http.queue_free()
		_http = null
		check_done.emit({})


## Downloads `url` to `path`, then verifies it; emits download_done with "" or the error (the file is gone on error).
func download(url: String, path: String, size: int, digest: String) -> void:
	if _dl != null:
		return
	_dl_path = path
	_dl_size = size
	_dl_digest = digest
	DirAccess.remove_absolute(path)
	_dl = HTTPRequest.new()
	_dl.use_threads = true
	_dl.download_file = path
	add_child(_dl)
	_dl.request_completed.connect(_on_download_completed)
	if _dl.request(url, _headers()) != OK:
		_fail_download("Could not start the download.")


func _on_download_completed(result: int, code: int, _h: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail_download("The download failed (result %d, HTTP %d)." % [result, code])
		return
	var err := verify_file(_dl_path, _dl_size, _dl_digest)
	_finish_download(err)


func _fail_download(err: String) -> void:
	push_warning("Update download: " + err)
	DirAccess.remove_absolute(_dl_path)
	_finish_download(err)


func _finish_download(err: String) -> void:
	if _dl != null:
		_dl.queue_free()
		_dl = null
	download_done.emit(err)


func _process(_delta: float) -> void:
	if _dl != null:
		var total := _dl.get_body_size() if _dl.get_body_size() > 0 else _dl_size
		if total > 0:
			progress.emit(clampf(float(_dl.get_downloaded_bytes()) / float(total), 0.0, 1.0))
