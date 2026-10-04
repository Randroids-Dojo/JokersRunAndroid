class_name Score
extends RefCounted
## Score, combo meter, Hot Start multiplier, kill bonuses and checkpoint snapshots.

signal combo_broken

var total := 0.0
var hot_start := 1.0
var combo := 0
var combo_timer := 0.0
var combo_max := 0
var combo_breaks := 0
## Decay pauses outside of live combat beats.
var combo_frozen := true
var missile_kills := 0
var gun_kills := 0
var damage_taken := 0.0
var damage_since_kill := 0.0
var shots_fired := 0
var shots_hit := 0
var missiles_fired := 0
var missiles_hit := 0
var ace_bonus := false
var ace_combo_bonus := false
var tutorial_time := 0.0
var clean_count := 0
var _snapshot := {}

const _FIELDS := ["total", "hot_start", "combo", "combo_timer", "combo_max", "combo_breaks", "missile_kills", "gun_kills", "damage_taken", "shots_fired", "shots_hit", "missiles_fired", "missiles_hit", "ace_bonus", "ace_combo_bonus", "tutorial_time", "clean_count"]


func combo_mult() -> float:
	return 1.0 + mini(combo - 1, 10) * 0.2


func add(points: float) -> void:
	total += points


## Apply combat multipliers and return popup lines [{text, points?, kind}].
func kill(weapon: String, dist: float, base := -1, label := "") -> Array:
	var lines: Array = []
	combo += 1
	combo_max = maxi(combo_max, combo)
	combo_timer = Cfg.S_COMBO_WINDOW
	var sum := 0
	if base >= 0:
		lines.append({"text": label if label != "" else "TARGET DESTROYED", "points": base, "kind": "gold"})
		sum += base
	var w_base := Cfg.S_GUN_KILL if weapon == "gun" else Cfg.S_MISSILE_KILL
	lines.append({"text": "GUN KILL" if weapon == "gun" else "MISSILE KILL", "points": w_base, "kind": "kill"})
	sum += w_base
	if weapon == "gun":
		gun_kills += 1
	else:
		missile_kills += 1
	if dist < Cfg.S_CLOSE_DIST:
		lines.append({"text": "CLOSE RANGE", "points": Cfg.S_CLOSE_RANGE, "kind": "bonus"})
		sum += Cfg.S_CLOSE_RANGE
	if damage_since_kill <= 0.0:
		lines.append({"text": "NO DAMAGE BONUS", "points": Cfg.S_NO_DAMAGE, "kind": "bonus"})
		sum += Cfg.S_NO_DAMAGE
	damage_since_kill = 0.0
	var final_pts := int(round(sum * combo_mult() * hot_start))
	if combo >= 2:
		lines.append({"text": "COMBO x%d" % combo, "kind": "combo"})
	total += final_pts
	lines.append({"text": "+" + MathX.fmt_score(final_pts), "kind": "gold"})
	return lines


func hit() -> void:
	shots_hit += 1
	if combo > 0:
		combo_timer = maxf(combo_timer, Cfg.S_COMBO_HIT_REFRESH)


func damaged(amount: float) -> void:
	damage_taken += amount
	damage_since_kill += amount
	if combo > 0:
		combo_timer -= Cfg.S_COMBO_DAMAGE_PENALTY * minf(1.0, amount / 10.0)


func tick(dt: float) -> void:
	if combo <= 0 or combo_frozen:
		return
	combo_timer -= dt
	if combo_timer <= 0.0:
		combo = 0
		combo_timer = 0.0
		combo_breaks += 1
		combo_broken.emit()


func save() -> void:
	_snapshot = {}
	for f in _FIELDS:
		_snapshot[f] = get(f)


func restore() -> void:
	for f in _snapshot:
		set(f, _snapshot[f])
	damage_since_kill = 0.0


func reset() -> void:
	total = 0.0
	hot_start = 1.0
	combo = 0
	combo_timer = 0.0
	combo_max = 0
	combo_breaks = 0
	missile_kills = 0
	gun_kills = 0
	damage_taken = 0.0
	damage_since_kill = 0.0
	shots_fired = 0
	shots_hit = 0
	missiles_fired = 0
	missiles_hit = 0
	ace_bonus = false
	ace_combo_bonus = false
	tutorial_time = 0.0
	clean_count = 0
	_snapshot = {}


func rank() -> String:
	if total >= 170000:
		return "S"
	if total >= 115000:
		return "A"
	if total >= 70000:
		return "B"
	if total >= 35000:
		return "C"
	return "D"
