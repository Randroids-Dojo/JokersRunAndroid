# Joker's Run: Android

Native Android build of [Joker's Run](https://github.com/Randroids-Dojo/JokersRunAndroid), the arcade flight combat demo from [JokersRunArcade](https://github.com/Randroids-Dojo/JokersRunArcade) ([play the web version](https://jokers-run-arcade.vercel.app)). You get the same Mission 01 as the web build: launch off the carrier, run the timed flight check, shoot three training drones, stop the scouts, dogfight, run the canyon chase, beat the two-stage ace, catch the final scout, then the epilogue.

**[Download the APK](https://github.com/Randroids-Dojo/JokersRunAndroid/releases/latest/download/JokersRun.apk)** (arm64, Android 7.0+)

## Install

1. Open the download link on your phone. If you downloaded on a computer instead, copy `JokersRun.apk` to the phone.
2. Open the file. Android asks you to allow installs from that app (your browser or file manager). Allow it, then tap **Install**.
3. Launch **Joker's Run**. The game runs in landscape.

Or, with USB debugging on: `adb install JokersRun.apk`.

## Controls

The touch layout matches the web build's mobile controls:

| Touch | Action |
| --- | --- |
| Left thumb, drag anywhere on the left half | Floating flight stick. With assisted steering on (the default), push where you want to go and the jet banks and pulls for you |
| GUN (hold) | Guns. The button glows white when the lead circle sits on the target |
| MSL | Missile. The ring fills while locking and turns red when locked |
| BOOST | Tap to light the afterburner, tap again to cancel. Hold for momentary boost |
| BRAKE (hold) | Slow down and turn tighter |
| ROLL | Barrel roll. It turns into **EVADE** when a missile is close |
| TGT | Tap for the next target. Hold to look at the target |
| Tap an enemy | Target it |
| COVER ME / SCOUTS / SPLIT | Wingman orders, when they are available |
| ❚❚ or the Android back gesture | Pause |

The pause menu has assisted steering, tilt steering (gravity sensor, recalibrated at every launch), haptics, invert pitch, radio voice, music, reduced shake and sound. Settings and your best score are saved.

Gamepads and keyboards also work, with the same bindings as the web build: left stick or W/S/A/D to fly, RT/Shift boost, LT/X brake, X/Space guns, A/F missile, B/R roll, Y/Tab target, D-pad or 1/2/3 for wingman orders, Start/Esc to pause.

## How it is built

**Godot 4.6, Forward Mobile renderer (Vulkan), typed GDScript.** The renderer falls back to OpenGL ES 3 (Compatibility) on devices without usable Vulkan.

- **Same world and data.** `tools/gen_terrain.ts` runs the web build's terrain code to bake the identical heightfield. The cloud, storm and rain layouts use a bit-exact port of the web build's seeded RNG. Every tuning value, AI brain, scoring rule and mission beat is a line-for-line port.
- **Same look.** The materials are custom shaders that reproduce the web lighting (hemisphere + sun + explosion lights, exp² fog), the ocean, sky, clouds and particles. Each material does three.js ACES Filmic tone mapping and sRGB encoding itself, and the engine's final pass is set to an identity. Transparent effects therefore blend on display values exactly as they do in the browser. Side-by-side screenshots against the web build match closely on both the Vulkan and the GLES3 paths.
- **Same sound.** `tools/synth.mjs` renders the web build's Web Audio instruments, effects and four music loops offline to WAV. The radio lines are the web build's recorded voice clips (five ElevenLabs voices with a radio filter), copied by `tools/voice_sync.mjs`.
- **Built for phones.** It has a fixed 60 Hz simulation with sub-stepping and slow motion. The terrain is displaced on the GPU from one texture, and tracers and clouds are drawn with single MultiMesh draws. Shaders are baked at export to avoid first-use hitches. The sky is a far-plane dome rather than a radiance cubemap. An adaptive render-scale governor holds the frame rate.

## Build

You need Godot 4.6 with export templates, the Android SDK (build-tools 35+), and JDK 17+.

```sh
# Release APK (signing credentials come from the environment, never the repo)
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=jokersrun
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
godot --path . --export-release "Android" build/JokersRun.apk
```

Run without `--headless` so the shader baker can use the GPU.

## Verification

`src/selftest.gd` is an automated on-device test. It is on in the `Android Selftest` export preset (feature tag `selftest`, installs as a separate "Joker's Run Selftest" app next to the game), or on desktop with `godot --path . -- --selftest=<mode> --quit`:

- `touch` sends synthetic multi-touch through the real input pipeline and checks launch, skip, stick, assisted turn, guns while steering, the boost latch, brake, roll, missile, pause and resume.
- `full` runs `touch`, then the test bot flies the entire mission to the debrief and checks that every radio line played its voice clip.
- `shots` and `screens` take reference screenshots for comparison with `tools/web_shots.mjs` and `tools/web_screens.mjs`.
- `diag` and `storm` shoot fixed views of the transparent effects for comparison with `tools/web_diag.mjs`.

Results go to the log as `SELFTEST PASS/FAIL` lines (`adb logcat -s godot`), and screenshots go to `user://shots/`.

To test on a phone over Wi-Fi, turn on Wireless debugging, choose "Pair device with pairing code", then:

```sh
adb pair <ip>:<pairing-port> <code>
adb connect <ip>:<port>
adb install --user 0 -r build/JokersRun-selftest.apk   # --user 0 skips a work profile
adb shell run-as com.randroids.jokersrun.selftest sh -c 'echo full > files/selftest_mode.txt'
adb shell monkey -p com.randroids.jokersrun.selftest -c android.intent.category.LAUNCHER 1
adb exec-out run-as com.randroids.jokersrun.selftest cat files/shots/01_title.png > title.png
```

Godot's export restarts the adb server, so run `adb connect` again after exporting.

## Assets

Chakra Petch font, SIL Open Font License (`assets/fonts/OFL.txt`). The radio voice clips in `assets/voice/` come from the web build (`JokersRunArcade/scripts/voice/`); after regenerating them there, run `node tools/voice_sync.mjs`. Everything else is generated by the tools in `tools/`.
