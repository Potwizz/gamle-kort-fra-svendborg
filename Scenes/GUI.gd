class_name GUIScript extends CanvasLayer
@onready var info_box_button: Button = %InfoBoxButton
@onready var info_box_text: Control = %InfoBox
@onready var map_pins: Control = %Pins
#@onready var camera := get_viewport().get_camera_2d()
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var index_box: Control = %IndexBox
@onready var index_button: Button = %IndexButton
@onready var visible_pins_button: Button = %VisiblePinsButton
@onready var index_buttons_container: VBoxContainer = %IndexButtonsContainer
@onready var pins: Control = %Pins
@onready var info_box_button_close: Button = %InfoBoxButtonClose
@onready var map: Map = get_tree().get_first_node_in_group("map")
@onready var index_box_close: Button = %IndexBoxClose
@onready var background_panel_index: Panel = %BackgroundPanelIndex
@onready var background_panel: Panel = %BackgroundPanel

func _ready() -> void:
	preload("res://Scenes/map.tscn")
	info_box_button.pressed.connect(info_box_visible)
	index_button.pressed.connect(_index_box_visible)
	visible_pins_button.pressed.connect(_pins_visible)
	_index_buttons()
	info_box_button_close.pressed.connect(info_box_visible)
	index_box_close.pressed.connect(_index_box_visible)
	_add_bigger_hit_area(info_box_button_close, info_box_visible)
	_add_bigger_hit_area(index_box_close, _index_box_visible)
	_preload_pin_images.call_deferred()


## Closes InfoBox/IndexBox when a press (mouse or touch) lands outside
## them - the usual "click away to dismiss" pattern. Checked on press
## (not release) specifically so this can't race with the toggle buttons:
## pressing an already-open box's own open/close button is excluded below,
## so that button's own release-triggered toggle still works normally
## instead of being closed here first and immediately reopened by it.
func _input(event: InputEvent) -> void:
	var pos: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	else:
		return

	if info_box_text.visible and not _is_over_controls(pos, [info_box_text, info_box_button, info_box_button_close, background_panel]):
		info_box_text.visible = false

	if index_box.visible and not _is_over_controls(pos, [index_box, index_button, index_box_close, background_panel_index]):
		index_box.visible = false


func _is_over_controls(pos: Vector2, controls: Array[Control]) -> bool:
	for control in controls:
		if control.get_global_rect().has_point(pos):
			return true
	return false


func _preload_pin_images() -> void:
	var all_pin_image_sets: Array = []
	for entries in pins.get_children():
		all_pin_image_sets.append(entries.street_images)
	map.image_viewer.preload_first_images(all_pin_image_sets)


## Adds a fully invisible, larger Button on top of `button` so it's easier
## to tap on mobile, without changing `button`'s own size, position, or
## appearance at all. Assumes `button` is freely positioned (anchors/manual
## position), NOT laid out inside a Container - a Container would just
## re-lay out the new sibling and ignore the position/size set below.
func _add_bigger_hit_area(button: Button, on_pressed: Callable, padding: float = 16.0) -> void:
	var hit_area := Button.new()
	hit_area.flat = true
	hit_area.focus_mode = Control.FOCUS_NONE
	hit_area.mouse_filter = Control.MOUSE_FILTER_STOP

	# Fully transparent in every state, so nothing is drawn - this button
	# exists purely to catch taps, not to be seen.
	var empty_style := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit_area.add_theme_stylebox_override(state, empty_style)

	var parent := button.get_parent()
	parent.add_child(hit_area)
	parent.move_child(hit_area, button.get_index() + 1)  # draw on top, after button

	hit_area.position = button.position - Vector2(padding, padding)
	hit_area.size = button.size + Vector2(padding, padding) * 2
	hit_area.pressed.connect(on_pressed)


## Create buttons on runtime and store MapEntries dictionary data for each button
#func map_buttons() -> void:
	#for entries in map_entries:
		#button = Button.new()
		#button_menu.add_child(button)
		#button.text = entries.button_text
		#button.theme = preload("res://Themes/location_theme.tres")
		#button.name = entries.button_text
		#button.pressed.connect(func() -> void:
			#map_textureRect.texture = entries.map_texture
			#info_box_text.text = entries.info_text
			#)
func _index_buttons() -> void:
	for entries in pins.get_children():
		var button = Button.new()
		index_buttons_container.add_child(button)
		button.text = entries.pin_street_name
		button.pressed.connect(func() -> void:
			map.focus_on_pin(entries, 2.0)
			index_box.visible = false  # optional: close the index after selecting
			if map_pins.visible == false:
				map_pins.visible = true
		)
func info_box_visible() -> void:
	if info_box_text.visible == false:
		info_box_text.visible = true
		index_box.visible = false
	else:
		info_box_text.visible = false
		#info_box_button.visible = true
func _index_box_visible() -> void:
	if index_box.visible == false:
		index_box.visible = true
		info_box_text.visible = false
	else:
		index_box.visible = false
func _pins_visible() -> void:
	if map_pins.visible == false:
		map_pins.visible = true
		#info_box_button.visible = false
	else:
		map_pins.visible = false
		#info_box_button.visible = true
