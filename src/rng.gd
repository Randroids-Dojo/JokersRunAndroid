class_name Mulberry32
extends RefCounted
## Bit-exact port of the web build's mulberry32 PRNG so seeded layouts (clouds, storm,
## rain shafts) match the browser version exactly.

var _a: int


func _init(seed_value: int) -> void:
	_a = seed_value & 0xffffffff


static func _imul(x: int, y: int) -> int:
	return (x * y) & 0xffffffff


func next() -> float:
	_a = (_a + 0x6d2b79f5) & 0xffffffff
	var t := _a
	t = _imul(t ^ (t >> 15), t | 1)
	t = t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & 0xffffffff)
	return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0
