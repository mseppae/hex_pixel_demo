package main

// Sound effects: a swing as the attacker lunges, then the impact and the victim's cry
// (or death cry) the moment the hit lands.
//
// The sounds are built into the program, like the art. If the computer has no working
// sound device, the game just runs silently.
// To make new versions of the sounds, see art_source/sounds.py.

import "core:math/rand"
import rl "vendor:raylib"

Sound_Id :: enum {
	Swing_Light,
	Swing_Blade,
	Swing_Heavy,
	Hit_Blade,
	Hit_Blunt,
	Hurt_Goblin,
	Hurt_Ogre,
	Hurt_Player,
	Death_Goblin,
	Death_Ogre,
	Death_Player,
}

SOUND_FILES := [Sound_Id][]u8 {
	.Swing_Light  = #load("assets/sounds/swing_light.wav"),
	.Swing_Blade  = #load("assets/sounds/swing_blade.wav"),
	.Swing_Heavy  = #load("assets/sounds/swing_heavy.wav"),
	.Hit_Blade    = #load("assets/sounds/hit_blade.wav"),
	.Hit_Blunt    = #load("assets/sounds/hit_blunt.wav"),
	.Hurt_Goblin  = #load("assets/sounds/hurt_goblin.wav"),
	.Hurt_Ogre    = #load("assets/sounds/hurt_ogre.wav"),
	.Hurt_Player  = #load("assets/sounds/hurt_player.wav"),
	.Death_Goblin = #load("assets/sounds/death_goblin.wav"),
	.Death_Ogre   = #load("assets/sounds/death_ogre.wav"),
	.Death_Player = #load("assets/sounds/death_player.wav"),
}

// How loud each sound plays (1 = as loud as the file). Swooshes sit under the hits.
SOUND_VOLUMES := [Sound_Id]f32 {
	.Swing_Light  = 0.45,
	.Swing_Blade  = 0.5,
	.Swing_Heavy  = 0.65,
	.Hit_Blade    = 0.8,
	.Hit_Blunt    = 0.9,
	.Hurt_Goblin  = 0.7,
	.Hurt_Ogre    = 0.8,
	.Hurt_Player  = 0.75,
	.Death_Goblin = 0.8,
	.Death_Ogre   = 0.9,
	.Death_Player = 0.9,
}

// Each play is pitched up or down by up to this much, so repeated hits don't sound identical.
PITCH_VARIATION :: 0.08

// What kind of weapon a creature swings: decides the swoosh and the impact.
Weapon_Sound :: enum {
	Light, // daggers and fists: a quick, high swish
	Blade, // swords
	Heavy, // clubs: a slow, low whoosh and a thud
}

SWING_SOUNDS  := [Weapon_Sound]Sound_Id{.Light = .Swing_Light, .Blade = .Swing_Blade, .Heavy = .Swing_Heavy}
IMPACT_SOUNDS := [Weapon_Sound]Sound_Id{.Light = .Hit_Blade, .Blade = .Hit_Blade, .Heavy = .Hit_Blunt}

Sound_System :: struct {
	sounds:       [Sound_Id]rl.Sound,
	is_ready:     bool, // false if there is no sound device
	muted:        bool,
	times_played: [Sound_Id]int, // counted even when silent: handy for tests and debugging
}

init_sound_system :: proc(system: ^Sound_System) {
	rl.InitAudioDevice()
	system.is_ready = rl.IsAudioDeviceReady()
	if !system.is_ready do return
	for id in Sound_Id {
		bytes := SOUND_FILES[id]
		wave := rl.LoadWaveFromMemory(".wav", raw_data(bytes), i32(len(bytes)))
		system.sounds[id] = rl.LoadSoundFromWave(wave)
		rl.UnloadWave(wave)
		rl.SetSoundVolume(system.sounds[id], SOUND_VOLUMES[id])
	}
}

close_sound_system :: proc(system: ^Sound_System) {
	if !system.is_ready do return
	for sound in system.sounds do rl.UnloadSound(sound)
	rl.CloseAudioDevice()
}

play_sound :: proc(system: ^Sound_System, id: Sound_Id) {
	system.times_played[id] += 1
	if !system.is_ready || system.muted do return
	sound := system.sounds[id]
	rl.SetSoundPitch(sound, 1 + rand.float32_range(-PITCH_VARIATION, PITCH_VARIATION))
	rl.PlaySound(sound)
}
