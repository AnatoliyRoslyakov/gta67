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

@onready var button_sdfgi: CheckBox = $%SDFGI
@onready var button_mute: TextureButton = %Mute
@onready var slider_volume: HSlider = %Volume

@onready var loading_screen: PanelContainer = %LoadingPanel

var town: Node3D = null

func _ready() -> void:
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

	# Hide SDFGI button if this is using a renderer that doesn't support it
	button_sdfgi.visible = RenderingServer.get_current_rendering_method() == "forward_plus"


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"back"):
		_on_back_pressed()


func focus_first_car() -> void:
	car_container.get_child(0).grab_focus.call_deferred()


func _load_vehicle(vehicle: Array) -> void:
	# Show loading screen and wait for it to be rendered
	loading_screen.visible = true
	await get_tree().process_frame
	await get_tree().process_frame

	var car: Node3D = preload("res://vehicles/car_base.tscn").instantiate()
	car.name = "car"
	var body := car.get_child(0) as VehicleBody3D
	body.set_script(preload("res://vehicles/polygon_vehicle.gd"))
	body.vehicle_scene = load("res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_%s_01.tscn" % vehicle[1])
	body.engine_force_value = vehicle[2]
	town = preload("res://town/town_scene.tscn").instantiate()

	if button_sunrise.button_pressed:
		town.mood = town.Mood.SUNRISE
	elif button_day.button_pressed:
		town.mood = town.Mood.DAY
	elif button_sunset.button_pressed:
		town.mood = town.Mood.SUNSET
	elif button_night.button_pressed:
		town.mood = town.Mood.NIGHT

	town.setup(car, _on_back_pressed, button_sdfgi.button_pressed)

	get_parent().add_child(town)
	hide()


func _on_back_pressed() -> void:
	if is_instance_valid(town):
		# Currently in the town, go back to main menu.
		town.queue_free()
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
