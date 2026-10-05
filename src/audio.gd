class_name GameAudio
extends Node
## Pre-rendered sound effects (from tools/synth.mjs), engine and alert loops, music with
## crossfades, and the recorded radio voices (tools/voice_sync.mjs).

const POOL := 14

var muted := false
var voice_on := true
var music_volume := 0.5
var _gains := {}
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _engine: AudioStreamPlayer
var _engine_boost: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _lock_locking: AudioStreamPlayer
var _lock_locked: AudioStreamPlayer
var _alert_slow: AudioStreamPlayer
var _alert_fast: AudioStreamPlayer
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur: AudioStreamPlayer
var _track := ""
var _last_shot := 0.0
var _voice: AudioStreamPlayer
var _voice_req := 0
var _clips := {}  # "WHO|text" -> {file, dur}
var _boost_level := 0.0


func _ready() -> void:
	_gains = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/gains.json"))
	for n in ["gun", "boom_big", "boom_small", "missile", "hit", "player_hit", "player_hit_heavy", "chime", "bonus", "combo", "radio", "klaxon", "beep", "beep_final", "catapult", "flare", "whoosh", "stinger", "click", "dry"]:
		_streams[n] = load("res://assets/audio/%s.wav" % n)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_engine = _loop("engine")
	_engine_boost = _loop("engine_boost")
	_wind = _loop("wind")
	_lock_locking = _loop("lock_locking")
	_lock_locked = _loop("lock_locked")
	_alert_slow = _loop("alert_slow")
	_alert_fast = _loop("alert_fast")
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	add_child(_music_a)
	add_child(_music_b)
	_music_cur = _music_a
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = _db(0.8 * 0.85)
	add_child(_voice)
	_clips = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/voice.json"))


func _looped(name: String) -> AudioStreamWAV:
	var s: AudioStreamWAV = load("res://assets/audio/%s.wav" % name)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(round(s.get_length() * s.mix_rate))
	return s


func _loop(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _looped(name)
	p.volume_db = -80.0
	add_child(p)
	return p


func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.00001))


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)
	if m:
		stop_speech()


func set_music_volume(v: float) -> void:
	music_volume = v
	if _music_cur.playing:
		_music_cur.volume_db = _db(_music_gain(_track) * v)


func _music_gain(track: String) -> float:
	return float(_gains.get("music_" + track, 1.0))


func play(name: String, vol := 1.0, pitch := 1.0) -> void:
	if vol < 0.01 or not _streams.has(name):
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = _db(vol * float(_gains.get(name, 1.0)) * 0.85)
	p.play()


func update_engine(speed: float, throttle: float, boosting: bool, active: bool, dt: float) -> void:
	var on := 1.0 if active else 0.0
	var s := speed / 400.0
	_boost_level = MathX.damp(_boost_level, 1.0 if boosting else 0.0, 8.0, dt)
	_set_loop(_engine, on * (0.12 + throttle * 0.22) * 0.9, 0.82 + s * 0.38 + throttle * 0.08)
	_set_loop(_engine_boost, on * _boost_level * 0.32, 0.9 + s * 0.2)
	_set_loop(_wind, on * minf(0.32, s * s * 0.22) * 0.8, 0.7 + s * 0.6)


func _set_loop(p: AudioStreamPlayer, linear: float, pitch := 1.0) -> void:
	if linear < 0.002:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.play()
	p.volume_db = _db(linear)
	p.pitch_scale = clampf(pitch, 0.5, 2.0)


func set_lock_tone(state: String) -> void:
	_set_loop(_lock_locking, 0.064 if state == "locking" else 0.0)
	_set_loop(_lock_locked, 0.064 if state == "locked" else 0.0)


func set_missile_alert(level: int) -> void:
	_set_loop(_alert_slow, 0.076 if level == 1 else 0.0)
	_set_loop(_alert_fast, 0.076 if level >= 2 else 0.0)


func gunshot(vol := 0.32) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_shot < 0.03:
		return
	_last_shot = now
	play("gun", vol, randf_range(0.92, 1.08))


func enemy_gun(vol: float) -> void:
	play("gun", vol, 1.3)


func explosion(vol: float, big: bool) -> void:
	play("boom_big" if big else "boom_small", vol, randf_range(0.85, 1.15))


func missile_launch(vol := 0.5) -> void:
	play("missile", vol)


func hit_tick(vol := 0.2) -> void:
	play("hit", vol)


func player_hit(heavy: bool) -> void:
	play("player_hit_heavy" if heavy else "player_hit", 1.0)


func chime(level := 0) -> void:
	play("chime", 1.0, pow(2.0, level * 2.0 / 12.0))


func bonus() -> void:
	play("bonus", 1.0)


func combo_tick(n: int) -> void:
	play("combo", 1.0, pow(2.0, mini(n, 12) * 2.0 / 12.0))


func radio_blip() -> void:
	play("radio", 1.0)


func klaxon() -> void:
	play("klaxon", 1.0)


func countdown_beep(final := false) -> void:
	play("beep_final" if final else "beep", 1.0)


func catapult() -> void:
	play("catapult", 1.0)


func flare() -> void:
	play("flare", 1.0)


func whoosh(vol: float) -> void:
	play("whoosh", vol)


func stinger() -> void:
	play("stinger", 1.0)


func click() -> void:
	play("click", 1.0)


func dry() -> void:
	play("dry", 1.0)


func set_track(track: String, immediate := false) -> void:
	if track == _track:
		return
	_track = track
	var old := _music_cur
	if track == "none":
		old.stop()
		return
	var next := _music_b if old == _music_a else _music_a
	next.stream = _looped("music_" + track)
	next.volume_db = _db(_music_gain(track) * music_volume)
	next.play()
	_music_cur = next
	if old.playing:
		if immediate:
			old.stop()
		else:
			var tw := create_tween()
			tw.tween_property(old, "volume_db", -60.0, 0.6)
			tw.tween_callback(old.stop)


## Plays the line's radio clip, cutting off any line still playing. Returns the clip length
## in seconds (0 when nothing plays) so the caption can stay up as long.
func speak(text: String, who: String) -> float:
	stop_speech()
	var clip: Dictionary = _clips.get("%s|%s" % [who, text], {})
	if clip.is_empty():
		push_warning("No radio clip for %s: %s" % [who, text])
		return 0.0
	if not voice_on or muted:
		return 0.0
	_voice.stream = load("res://assets/" + str(clip.file))
	_start_voice(_voice_req)
	return float(clip.dur) + 0.08


func _start_voice(req: int) -> void:
	await get_tree().create_timer(0.08, false).timeout  # after the squelch
	if req == _voice_req:
		_voice.play()


func stop_speech() -> void:
	_voice_req += 1
	_voice.stop()


func pause_all(p: bool) -> void:
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stream_paused = p
