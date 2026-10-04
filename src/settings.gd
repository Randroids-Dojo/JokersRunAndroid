class_name Settings
extends RefCounted
## Player options and the best score, persisted to user://settings.cfg.

const PATH := "user://settings.cfg"
const KEYS := ["invert_pitch", "voice", "music", "reduced_motion", "mute", "assist", "tilt", "haptics"]

var invert_pitch := false
var voice := true
var music := true
var reduced_motion := false
var mute := false
## Touch: assisted steering (stick asks for a turn, the jet banks and pulls).
var assist := true
var tilt := false
var haptics := true
var best := 0


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in KEYS:
		set(k, bool(cf.get_value("settings", k, get(k))))
	best = int(cf.get_value("score", "best", 0))


func save_file() -> void:
	var cf := ConfigFile.new()
	for k in KEYS:
		cf.set_value("settings", k, get(k))
	cf.set_value("score", "best", best)
	cf.save(PATH)


func toggle(key: String) -> void:
	set(key, not bool(get(key)))
	save_file()
