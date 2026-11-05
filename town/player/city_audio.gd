extends Node

# Original one-shot Foley is synthesized in memory; no imported audio asset is required.
const RATE := 24000
const MOODS := ["sunrise", "day", "sunset", "night"]
static var _cached_shots: Array[AudioStreamWAV] = []
static var _cached_steps: Array[AudioStreamWAV] = []
static var _cached_reload: AudioStreamWAV
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
	if _cached_reload == null:
		for variant in 4: _cached_shots.append(_synthesize("shot", variant))
		for variant in 6: _cached_steps.append(_synthesize("step", variant))
		_cached_reload = _synthesize("reload", 1)
		for mood in MOODS:
			var stream := load("res://town/sound/mood_%s.ogg" % mood).duplicate() as AudioStreamOggVorbis
			stream.loop = true
			_cached_ambience.append(stream)
	shots.assign(_cached_shots)
	steps.assign(_cached_steps)
	reload_sound = _cached_reload
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
	if is_instance_valid(atmosphere): _hour = float(atmosphere.get("time_of_day"))
	var mood := 3
	if _hour >= 5.5 and _hour < 8.0: mood = 0
	elif _hour >= 8.0 and _hour < 16.5: mood = 1
	elif _hour >= 16.5 and _hour < 20.0: mood = 2
	for index in ambience.size():
		var voice := ambience[index]
		var target := 0.06 if index == mood else 0.0
		voice.volume_linear = lerpf(voice.volume_linear, target, 1.0 - exp(-delta * 1.4))
		if target > 0 and not voice.playing: voice.play()
		elif target == 0 and voice.volume_linear < 0.0001 and voice.playing: voice.stop()
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


func _synthesize(kind: String, variant: int) -> AudioStreamWAV:
	var duration := 0.34 if kind == "shot" else (1.30 if kind == "reload" else 0.18)
	var count := int(duration * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var noise := RandomNumberGenerator.new()
	noise.seed = 670000 + variant * 97 + kind.hash()
	var low := 0.0
	var mid := 0.0
	var peak := 0.001
	for index in count:
		var t := float(index) / RATE
		var white := noise.randf_range(-1.0, 1.0)
		low = lerpf(low, white, 0.07)
		mid = lerpf(mid, white, 0.48)
		var sample := 0.0
		if kind == "shot":
			# Broadband muzzle transient with a short, soft low-frequency body.
			var attack := 1.0 - exp(-t * 1800.0)
			var body := sin(TAU * (115.0 * t - 65.0 * t * t)) * exp(-t * 42.0)
			sample = attack * ((mid - low) * exp(-t * 34.0) + low * exp(-t * 14.0) * 0.32 + body * 0.24)
		elif kind == "step":
			# Heel then sole: damped contact and texture, with no sustained oscillator.
			for contact in [0.0, 0.043]:
				var age: float = t - contact
				if age >= 0.0:
					var envelope := (1.0 - exp(-age * 800.0)) * exp(-age * 65.0)
					sample += envelope * (low * 1.4 + mid * 0.24 + sin(TAU * (90.0 + variant * 5.0) * age) * 0.18)
		else:
			# Magazine release, insertion and slide movement; each contact has a soft attack.
			for contact in [0.04, 0.58, 1.04, 1.13]:
				var age: float = t - contact
				if age >= 0.0 and age < 0.15:
					var envelope := (1.0 - exp(-age * 1100.0)) * exp(-age * 70.0)
					sample += envelope * ((mid - low) * 0.7 + low * 0.5 + sin(TAU * 1250.0 * age) * exp(-age * 85.0) * 0.08)
		# Sample-accurate fades prevent discontinuities at both ends of every buffer.
		sample *= clampf(t / 0.002, 0.0, 1.0) * clampf((duration - t) / 0.015, 0.0, 1.0)
		samples[index] = sample
		peak = maxf(peak, absf(sample))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for index in count: pcm.encode_s16(index * 2, int(samples[index] / peak * 26000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	return stream
