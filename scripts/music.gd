extends Node
## The soundtrack player, registered as the `Music` autoload. Ported from
## TCG-RPG's music player (two players, 1.6 s crossfades, playlists per
## place, each place remembering where its music was).
##
## The pieces are composed offline (tools/music/musket_music.py) and listed in
## data/music.json with the places ("contexts") they belong to:
##   menu, intro (the wreck), map (marching by day), camp (night),
##   battle, nest (lizard country).
## Auto mode follows the game; picking a track in the player switches to
## manual until Auto is turned back on. In battle the music sits lower so the
## muskets carry.

signal track_changed(track: Dictionary)
signal state_changed

const CATALOGUE := "res://data/music.json"
const SETTINGS := "user://settings.cfg"
const FADE := 1.6
const BATTLE_GAIN := 0.55
const THEME_NAMES := {"calder": "The Regiment", "land": "The Coast", "night": "The Camp", "horde": "The Horde"}

var tracks: Array = []
var by_id := {}
var playlist: Array = []
var index := 0
var current: Dictionary = {}
var auto := true
var shuffle := true
var paused := false
var enabled := true
var volume := 0.75
var context := ""
var _resume := {}
var _players: Array = []
var _active := 0
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(CATALOGUE):
		var data = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))
		if typeof(data) == TYPE_ARRAY:
			tracks = data
	for t in tracks:
		by_id[t["id"]] = t
	# Music has its own bus, so the game can lower it without touching effects.
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Music")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80
		p.finished.connect(_on_finished.bind(i))
		add_child(p)
		_players.append(p)
	_load_settings()


func label(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	return "%s · %s" % [THEME_NAMES.get(t["theme"], ""), String(t["kind"]).capitalize()]


func for_context(kind: String) -> Array:
	var out := []
	for t in tracks:
		if kind in t["contexts"]:
			out.append(t["id"])
	return out


## What part of the game we're in. Leaving a place remembers where its music
## was; coming back picks it up again (a new battle moves on to the next one).
func set_context(kind: String) -> void:
	if kind == context:
		return
	if context != "" and not current.is_empty() and not playlist.is_empty():
		var op: AudioStreamPlayer = _players[_active]
		_resume[context] = {"playlist": playlist.duplicate(), "index": index, "id": current["id"],
			"pos": op.get_playback_position() if op.playing else 0.0}
	context = kind
	_apply_bus()
	if not auto and not current.is_empty():
		return
	if _resume.has(kind):
		var r: Dictionary = _resume[kind]
		playlist = r["playlist"]
		index = clampi(int(r["index"]), 0, playlist.size() - 1)
		if kind == "battle":
			index = (index + 1) % playlist.size()
			_play(playlist[index])
			return
		if not current.is_empty() and current["id"] == r["id"]:
			return
		_play(r["id"], float(r["pos"]))
		return
	var list := for_context(kind)
	if list.is_empty():
		return
	if not current.is_empty() and list.has(current["id"]) and _players[_active].playing:
		_order(list, list.find(current["id"]))
		return
	_set_playlist(list, 0, kind == "menu")


func choose(track_id: String) -> void:
	if not by_id.has(track_id):
		return
	auto = false
	var list := []
	for t in tracks:
		list.append(t["id"])
	_set_playlist(list, list.find(track_id))
	state_changed.emit()


func set_auto(on: bool) -> void:
	auto = on
	if on:
		var c := context
		context = ""
		set_context(c)
	state_changed.emit()
	_save_settings()


func set_shuffle(on: bool) -> void:
	shuffle = on
	if not current.is_empty() and not playlist.is_empty():
		var now: String = current["id"]
		var base: Array = playlist.duplicate()
		base.sort_custom(func(a, b): return tracks.find(by_id[a]) < tracks.find(by_id[b]))
		_order(base, base.find(now))
		index = playlist.find(now)
	state_changed.emit()
	_save_settings()


func set_enabled(on: bool) -> void:
	enabled = on
	_apply_bus()
	state_changed.emit()
	_save_settings()


func next() -> void:
	if playlist.is_empty():
		return
	index = (index + 1) % playlist.size()
	_play(playlist[index])


func prev() -> void:
	if playlist.is_empty():
		return
	index = (index - 1 + playlist.size()) % playlist.size()
	_play(playlist[index])


func toggle_pause() -> void:
	paused = not paused
	_players[_active].stream_paused = paused
	state_changed.emit()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_bus()
	state_changed.emit()
	_save_settings()


## Volume lives on the bus: the crossfades only move the players.
func _apply_bus() -> void:
	var i := AudioServer.get_bus_index("Music")
	if i < 0:
		return
	var v := volume * (BATTLE_GAIN if context == "battle" else 1.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, not enabled or volume <= 0.001)


func _set_playlist(list: Array, start: int, keep_first: bool = true) -> void:
	if list.is_empty():
		return
	if shuffle and not keep_first:
		start = randi() % list.size()
	_order(list, clampi(start, 0, list.size() - 1))
	_play(playlist[index])


func _order(list: Array, start: int) -> void:
	if not shuffle:
		playlist = list.duplicate()
		index = start
		return
	var first = list[start]
	var rest: Array = list.duplicate()
	rest.remove_at(start)
	rest.shuffle()
	playlist = [first] + rest
	index = 0


func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		return AudioStreamOggVorbis.load_from_file(path)
	return null


func _play(track_id: String, from_pos: float = 0.0) -> void:
	var t: Dictionary = by_id.get(track_id, {})
	if t.is_empty():
		return
	var stream := _load_stream(t["file"])
	if stream == null:
		push_warning("Music: missing " + String(t["file"]))
		return
	current = t
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var p: AudioStreamPlayer = _players[_active]
	p.stream = stream
	p.volume_db = -40.0
	p.stream_paused = false
	paused = false
	p.play(from_pos)
	# A quick second change must not let the earlier fade-out silence the
	# player we're reusing: stop the old tween first.
	if _fade and _fade.is_valid():
		_fade.kill()
	var tw := create_tween().set_parallel(true)
	_fade = tw
	tw.tween_property(p, "volume_db", 0.0, FADE)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.chain().tween_callback(old.stop)
	track_changed.emit(t)
	state_changed.emit()


func _on_finished(which: int) -> void:
	if which == _active and not paused:
		next()


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		volume = float(cf.get_value("music", "volume", 0.75))
		auto = bool(cf.get_value("music", "auto", true))
		shuffle = bool(cf.get_value("music", "shuffle", true))
		enabled = bool(cf.get_value("music", "enabled", true))
	_apply_bus()


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("music", "volume", volume)
	cf.set_value("music", "auto", auto)
	cf.set_value("music", "shuffle", shuffle)
	cf.set_value("music", "enabled", enabled)
	cf.save(SETTINGS)
