extends Node

const SHOTS := [
	preload("res://town/sound/shot_0.wav"), preload("res://town/sound/shot_1.wav"),
	preload("res://town/sound/shot_2.wav"), preload("res://town/sound/shot_3.wav")
]
const STEPS := [
	preload("res://town/sound/step_0.wav"), preload("res://town/sound/step_1.wav"),
	preload("res://town/sound/step_2.wav"), preload("res://town/sound/step_3.wav"),
	preload("res://town/sound/step_4.wav"), preload("res://town/sound/step_5.wav")
]
const RELOAD := preload("res://town/sound/reload_0.wav")
const MOODS := ["sunrise", "day", "sunset", "night"]
static var _cached_ambience: Array[AudioStreamOggVorbis] = []
var player: CharacterBody3D
var atmosphere: Node
var shots: Array[AudioStreamWAV] = []
var steps: Array[AudioStreamWAV] = []
var reload_sound: AudioStreamWAV
var shot_voice: AudioStreamPlayer
var step_voice: AudioStreamPlayer
var reload_voice: AudioStreamPlayer
var ambience: Array[AudioStreamPlayer] = []
var rng := RandomNumberGenerator.new()
var _reload_was_active := false
var _grounded := false
var _last_foot_phase := 0
var _foot_cooldown := 0.0
var _character_gain := 0.0
var _step_volume := 0.12
var _mix_elapsed := 0.0
var _hour := 17.5
var _built := false


func configure(character: CharacterBody3D, clock: Node = null) -> void:
	if is_instance_valid(player) and player.fired.is_connected(_on_fired):
		player.fired.disconnect(_on_fired)
	player = character
	atmosphere = clock
	if not player.fired.is_connected(_on_fired): player.fired.connect(_on_fired)
	if is_inside_tree(): _build()


func _ready() -> void:
	_build()


func _build() -> void:
	if _built: return
	_built = true
	rng.seed = 670024
	# Streams are immutable after preparation; independent voices share their PCM.
	if _cached_ambience.is_empty():
		for mood in MOODS:
			var stream := load("res://town/sound/mood_%s.ogg" % mood).duplicate() as AudioStreamOggVorbis
			stream.loop = true
			_cached_ambience.append(stream)
	shots.assign(SHOTS)
	steps.assign(STEPS)
	reload_sound = RELOAD
	shot_voice = _voice("Gunshot", 4)
	step_voice = _voice("Footstep", 1)
	reload_voice = _voice("Reload", 1)
	for index in MOODS.size():
		var voice := _voice("Ambient_" + MOODS[index], 1)
		voice.bus = "Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else "Master"
		voice.stream = _cached_ambience[index]
		voice.volume_linear = 0.0
		ambience.append(voice)


func _voice(label: String, polyphony: int) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.name = label
	voice.max_polyphony = polyphony
	voice.volume_linear = 0.0
	add_child(voice)
	return voice


func _process(delta: float) -> void:
	if not _built: return
	_mix_elapsed += delta
	if _mix_elapsed >= 0.05:
		if is_instance_valid(atmosphere): _hour = float(atmosphere.get("time_of_day"))
		var mood := 3
		if _hour >= 5.5 and _hour < 8.0: mood = 0
		elif _hour >= 8.0 and _hour < 16.5: mood = 1
		elif _hour >= 16.5 and _hour < 20.0: mood = 2
		for index in ambience.size():
			var voice := ambience[index]
			var target := 0.16 if index == mood else 0.0
			if target == 0.0 and not voice.playing: continue
			voice.volume_linear = lerpf(voice.volume_linear, target, 1.0 - exp(-_mix_elapsed * 1.4))
			if target > 0 and not voice.playing: voice.play()
			elif target == 0 and voice.volume_linear < 0.0001 and voice.playing: voice.stop()
		_mix_elapsed = 0.0
	var active := is_instance_valid(player) and bool(player.get("active"))
	if active or _character_gain > 0.0:
		_character_gain = lerpf(_character_gain, 1.0 if active else 0.0, 1.0 - exp(-delta * 45.0))
		if not active and _character_gain < 0.001: _character_gain = 0.0
		shot_voice.volume_linear = 0.28 * _character_gain
		step_voice.volume_linear = _step_volume * _character_gain
		reload_voice.volume_linear = 0.14 * _character_gain
	if not active:
		if _character_gain == 0.0:
			if shot_voice.playing: shot_voice.stop()
			if step_voice.playing: step_voice.stop()
			if reload_voice.playing: reload_voice.stop()
		_reload_was_active = false
		_grounded = false
		return
	var reloading := float(player.get("reload_time")) > 0.0
	if reloading and not _reload_was_active: on_reload()
	_reload_was_active = reloading
	_foot_cooldown = maxf(0.0, _foot_cooldown - delta)
	var grounded := player.is_on_floor() and not is_instance_valid(player.get("mount"))
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var motion: RefCounted = player.get("motion")
	var foot_phase := floori(float(motion.get("phase")) / PI)
	if grounded and speed > 0.25 and foot_phase != _last_foot_phase and _foot_cooldown <= 0.0:
		_play_step(speed > 4.0)
	elif grounded and not _grounded and _foot_cooldown <= 0.0 and speed > 0.2:
		_play_step(false)
	_last_foot_phase = foot_phase
	_grounded = grounded


func set_hour(hour: float) -> void:
	_hour = fposmod(hour, 24.0)


func _on_fired(_origin: Vector3, _destination: Vector3, _collider: Object) -> void:
	on_shot()


func on_shot() -> void:
	if not _can_play(): return
	shot_voice.stream = shots[rng.randi_range(0, shots.size() - 1)]
	shot_voice.pitch_scale = rng.randf_range(0.97, 1.035)
	shot_voice.play()


func on_reload() -> void:
	if not _can_play(): return
	reload_voice.stream = reload_sound
	reload_voice.pitch_scale = 1.0
	reload_voice.play()


func _play_step(running: bool) -> void:
	_step_volume = rng.randf_range(0.13, 0.17) if running else rng.randf_range(0.08, 0.12)
	step_voice.volume_linear = _step_volume * _character_gain
	step_voice.stream = steps[rng.randi_range(0, steps.size() - 1)]
	step_voice.pitch_scale = rng.randf_range(0.94, 1.07)
	step_voice.play()
	_foot_cooldown = 0.15


func _can_play() -> bool:
	return _built and is_instance_valid(player) and bool(player.get("active"))
