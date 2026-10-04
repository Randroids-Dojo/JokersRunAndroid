class_name Controls
extends RefCounted
## One frame of merged input (touch, keyboard, gamepad, tilt). The flight model and mission
## read only this, exactly like the web build's ControlState.

var pitch := 0.0
var roll := 0.0
var yaw := 0.0
var boost := false
var brake := false
var roll_tap := 0
## Assisted steering: desired turn (-1..1). The flight model banks and pulls for you.
var turn := 0.0
var assist := false
var guns := false
var missile := false
var target_next := false
var look := false
var order := 0
var pause := false
var confirm := false
var skip := false
var taps: Array[Vector2] = []
## The last input came from the touchscreen (hides keyboard hints).
var using_touch := false


func consume_edges() -> void:
	missile = false
	target_next = false
	roll_tap = 0
	order = 0
	taps.clear()


static func neutral() -> Controls:
	return Controls.new()
