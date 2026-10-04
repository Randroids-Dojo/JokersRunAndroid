class_name Cfg
## Tuning values (same as the web build). Distances metres, speeds m/s, angles radians.

const SIM_STEP := 1.0 / 60.0

const P_CRUISE := 235.0
const P_BOOST := 410.0
const P_BRAKE := 140.0
const P_MIN_SPEED := 105.0
const P_MAX_SPEED := 480.0
const P_PITCH_RATE := 1.4
const P_ROLL_RATE := 3.2
const P_YAW_RATE := 0.5
const P_BANK_TURN := 0.6
const P_HP := 100.0
const P_BOOST_DRAIN := 0.14
const P_BOOST_REGEN := 0.16
const P_BOOST_REGEN_DELAY := 0.8
const P_ROLL_DURATION := 0.6
const P_ROLL_COOLDOWN := 1.0
const P_ROLL_JINK := 70.0
const P_CEILING := 6500.0
const P_REGEN_DELAY := 7.0
const P_REGEN_RATE := 2.5

const GUN_RATE := 18.0
const GUN_SPEED := 1150.0
const GUN_LIFE := 1.25
const GUN_DAMAGE := 6.0
const GUN_SPREAD := 0.004
const GUN_ASSIST_CONE := 0.08
const GUN_ASSIST_MAX := 0.045

const MSL_RELOAD := 2.0
const MSL_LAUNCH_BOOST := 40.0
const MSL_LOCK_CONE := 0.36
const MSL_LOCK_RANGE := 3300.0
const MSL_LOCK_TIME := 0.5

## Missile specs: [max_speed, accel, turn, life, damage, proximity]
const PLAYER_MISSILE := [640.0, 320.0, 2.6, 6.5, 100.0, 14.0]
const ENEMY_MISSILE := [520.0, 250.0, 2.0, 6.0, 24.0, 10.0]

const S_MISSILE_KILL := 1000
const S_GUN_KILL := 1500
const S_CLOSE_RANGE := 500
const S_CLOSE_DIST := 420.0
const S_NO_DAMAGE := 500
const S_SCOUT := 3000
const S_ACE := 10000
const S_ACE_COMBO := 5000
const S_CHECKPOINT := 300
const S_CLEAN := 500
const S_BULLSEYE := 250
const S_COMBO_WINDOW := 10.0
const S_COMBO_HIT_REFRESH := 5.0
const S_COMBO_DAMAGE_PENALTY := 2.0

const FLEET_SPEED := 18.0
const BOUNDARY_X := 17200.0
const AREA_RADIUS := 32000.0

const SUN_DIR := Vector3(-0.55, 0.42, 0.72)
const FOG_DENSITY := 0.000052

# HUD palette (matches the web CSS).
const C_HUD := Color("a6ffd0")
const C_HUD_DIM := Color(0.651, 1.0, 0.816, 0.55)
const C_HUD_FAINT := Color(0.651, 1.0, 0.816, 0.25)
const C_HOSTILE := Color("ff4d3d")
const C_TARGET := Color("ff9f1c")
const C_ACE := Color("ff4f7d")
const C_DRONE := Color("ffc23d")
const C_FRIEND := Color("63c9ff")
const C_GOLD := Color("ffd25a")
const C_COMBO := Color("7ff3ff")
const C_INK := Color("0a0d10")
