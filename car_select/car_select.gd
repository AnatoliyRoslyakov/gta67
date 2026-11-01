extends Control

var audio_master: int = AudioServer.get_bus_index("Master")

const VEHICLES := [
	["Sedan", "Sedan", 3000.0],
	["Muscle", "Muscle", 4200.0],
	["Compact", "Small", 2600.0],
	["Hatchback", "Medium", 2800.0],
	["Taxi", "Taxi", 3000.0],
	["Police", "Police", 3800.0],
	["Van", "Van", 2800.0],
	["Ambulance", "Ambo", 3000.0],
]

@onready var car_container: GridContainer = %CarContainer

@onready var button_sunrise: CheckBox = %Sunrise
@onready var button_day: CheckBox = %Day
@onready var button_sunset: CheckBox = %Sunset
@onready var button_night: CheckBox = %Night

@onready var button_reflections: CheckBox = %Reflections
@onready var button_mute: TextureButton = %Mute
@onready var slider_volume: HSlider = %Volume

@onready var loading_screen: PanelContainer = %LoadingPanel
@onready var loading_text: Label = %LoadingPanel/CenterContainer/Label

var town: Node3D = null
var _loading := false
var _loaded_scenes: Dictionary = {}

func _ready() -> void:
	$Subtitle.text = "v%s   ·   Truck Town   ·   Choose your vehicle" % ProjectSettings.get_setting("application/config/version", "2.0.1")
	var loading_layer := CanvasLayer.new()
	loading_layer.layer = 100
	add_child(loading_layer)
	loading_screen.reparent(loading_layer)
	for vehicle in VEHICLES:
		var button := Button.new()
		button.text = vehicle[0]
		button.custom_minimum_size = Vector2(190, 68)
		button.pressed.connect(_load_vehicle.bind(vehicle))
		car_container.add_child(button)
	car_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	car_container.position.y -= 40
	# Automatically focus the first item for gamepad accessibility.
	focus_first_car()

	# Initialize audio slider.
	slider_volume.value = AudioServer.get_bus_volume_linear(audio_master)

	button_reflections.visible = RenderingServer.get_current_rendering_method() == "forward_plus"
	if "--drive" in OS.get_cmdline_user_args():
		_load_vehicle.call_deferred(VEHICLES[0])


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"back") and not is_instance_valid(town) and not _loading:
		_on_back_pressed()


func focus_first_car() -> void:
	car_container.get_child(0).grab_focus.call_deferred()


func _load_vehicle(vehicle: Array) -> void:
	if _loading or is_instance_valid(town): return
	_loading = true
	CityPerformance.loading = true
	# Show loading screen and wait for it to be rendered
	loading_screen.visible = true
	loading_text.text = "Загрузка города…"
	await get_tree().process_frame
	await get_tree().process_frame

	var model_path := "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_%s_01.tscn" % vehicle[1]
	var paths := ["res://town/town_scene.tscn", "res://vehicles/car_base.tscn", model_path]
	for path in paths:
		if _loaded_scenes.has(path): continue
		if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
			_loading_failed()
			return
	var complete := false
	while not complete:
		complete = true
		var total := 0.0
		for path in paths:
			if _loaded_scenes.has(path):
				total += 1.0
				continue
			var progress: Array = []
			var status := ResourceLoader.load_threaded_get_status(path, progress)
			if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_loading_failed()
				return
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_loaded_scenes[path] = ResourceLoader.load_threaded_get(path)
				total += 1.0
			else:
				complete = false
				if not progress.is_empty(): total += float(progress[0])
		loading_text.text = "Загрузка города · %d%%" % roundi(total / paths.size() * 100)
		await get_tree().process_frame
	var car: Node3D = _loaded_scenes["res://vehicles/car_base.tscn"].instantiate()
	car.name = "car"
	var body := car.get_child(0) as VehicleBody3D
	body.set_script(preload("res://vehicles/polygon_vehicle.gd"))
	body.vehicle_scene = _loaded_scenes[model_path]
	body.engine_force_value = vehicle[2]
	loading_text.text = "Подготовка улиц и транспорта…"
	await get_tree().process_frame
	town = _loaded_scenes["res://town/town_scene.tscn"].instantiate()

	if button_sunrise.button_pressed:
		town.mood = town.Mood.SUNRISE
	elif button_day.button_pressed:
		town.mood = town.Mood.DAY
	elif button_sunset.button_pressed:
		town.mood = town.Mood.SUNSET
	elif button_night.button_pressed:
		town.mood = town.Mood.NIGHT

	town.setup(car, _on_back_pressed, button_reflections.button_pressed)

	get_parent().add_child(town)
	town.player_body.set_controlled(false)
	# Keep the loading overlay while the first shader variants and city actors
	# are prepared, rather than exposing those startup frames as gameplay.
	while not town.traffic.initialized:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	town.player_body.set_controlled(true)
	loading_screen.hide()
	hide()
	_loading = false
	CityPerformance.loading = false
	if not CityPerformance._focused: town.gameplay.open_menu()


func _loading_failed() -> void:
	_loading = false
	CityPerformance.loading = false
	loading_screen.hide()
	var message := AcceptDialog.new()
	message.dialog_text = "Не удалось загрузить город. Проверьте локальную папку Assets/Synty/PolygonCity."
	message.title = "Загрузка города"
	message.confirmed.connect(message.queue_free)
	message.canceled.connect(message.queue_free)
	add_child(message)
	message.popup_centered()


func _on_back_pressed() -> void:
	if _loading: return
	if is_instance_valid(town):
		# Currently in the town, go back to main menu.
		town.queue_free()
		town = null
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		loading_screen.visible = false
		show()
		# Automatically focus the first item for gamepad accessibility.
		focus_first_car()
	else:
		# In main menu, exit the game.
		get_tree().quit()


func _on_mute_toggled(muted: bool) -> void:
	AudioServer.set_bus_mute(audio_master, muted)


func _on_volume_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_linear(audio_master, value)
