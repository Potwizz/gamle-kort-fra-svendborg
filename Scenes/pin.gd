@tool
extends Control

@onready var toggle_visibility: Button = %ToggleVisibility
@onready var image_button: Button = %ImageButton
@onready var image_viewer: Control= %ImageViewer
@onready var image_text_button: Button = %ImageTextButton
@onready var image_text: RichTextLabel = %ImageText
@onready var pins_texture: TextureRect = %PinsTexture

@export var hover_scale := 1.1      # how much bigger on hover (1.1 = +10%)
@export var hover_duration := 0.1

var _hover_tween: Tween
var _pin_rest_scale := Vector2.ONE
var _hover_count := 0

#@export var pin_texture: Texture = null
@export var pin_street_name: String = ""
##@export var pin_number: int = 1
@export var base_scale := Vector2.ONE
@export var scale_strength := 1.0
@export var reference_height := 1080.0
@export var street_images: Array[StreetImages] = []

# Tween config for the pop/fold
@export var pop_duration := 0.18
@export var fold_duration := 0.12

var _popup_tween: Tween
# Controls that pop/fold together, each mapped to its resting scale.
var _popup_targets: Array[Control] = []
var _rest_scales := {}

# Popup visibility state: shown if pinned (clicked) OR hovering (preview).
var _popup_pinned := false
var _popup_hovering := false
var _popup_shown := false

# Pointer-type tracking so the hover preview only runs for a real mouse.
var _last_pointer_was_touch := false
var _touch_active := false

func _ready() -> void:
	#toggle_visibility.icon = pin_texture
	image_button.text = pin_street_name
	toggle_visibility.pressed.connect(_image_visible)
	##toggle_visibility.text = str(pin_number)
	image_button.pressed.connect(_open_link)
	# Everything that should share the pop/fold animation.
	_popup_targets = [image_button]
	for node in _popup_targets:
		_rest_scales[node] = node.scale  # remember editor scale to animate back to

	_pin_rest_scale = pins_texture.scale

	# Treat hover over the pin OR the flat button on top of it as one hover.
	for node in [pins_texture, toggle_visibility]:
		node.mouse_entered.connect(_on_pin_hover_entered)
		node.mouse_exited.connect(_on_pin_hover_exited)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_last_pointer_was_touch = true
		_touch_active = event.pressed
	elif event is InputEventScreenDrag:
		_last_pointer_was_touch = true
		_touch_active = true
	elif event is InputEventMouseMotion:
		# Ignore the emulated motion a touch generates; only a real mouse
		# move (no active touch) counts as "using the mouse".
		if not _touch_active:
			_last_pointer_was_touch = false

func text_visible() -> void:
	# Clicking the pin toggles the "pinned open" state.
	_popup_pinned = not _popup_pinned
	_refresh_popup()
	print("Is clicked!")

func _refresh_popup() -> void:
	# Show if either reason is active; only animate on an actual change.
	var should_show := _popup_pinned or _popup_hovering
	if should_show == _popup_shown:
		return
	_popup_shown = should_show
	if should_show:
		_show_popup()
	else:
		_hide_popup()

func _show_popup() -> void:
	_kill_popup_tween()
	_popup_tween = create_tween().set_parallel()
	_popup_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for node in _popup_targets:
		node.pivot_offset = node.size * 0.5  # scale from center
		node.visible = true
		node.scale = Vector2.ZERO
		_popup_tween.tween_property(node, "scale", _rest_scales[node], pop_duration)

func _hide_popup() -> void:
	_kill_popup_tween()
	_popup_tween = create_tween().set_parallel()
	_popup_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	for node in _popup_targets:
		node.pivot_offset = node.size * 0.5
		_popup_tween.tween_property(node, "scale", Vector2.ZERO, fold_duration)
	# chain() runs this AFTER the parallel fold batch completes.
	_popup_tween.chain().tween_callback(_hide_popup_targets)

func _hide_popup_targets() -> void:
	for node in _popup_targets:
		node.hide()

func _kill_popup_tween() -> void:
	if _popup_tween and _popup_tween.is_running():
		_popup_tween.kill()


## Temporarily suppresses this pin's clickability without changing how it
## looks - called by Map while a drag/pan gesture is in progress. Needed
## because Godot's Button can "pick up" a press that started elsewhere if
## the pointer passes over it while the mouse/touch is still held down,
## so releasing a map-drag on top of a pin would otherwise fire its click.
func set_input_enabled(enabled: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	toggle_visibility.mouse_filter = filter
	image_button.mouse_filter = filter

func _image_visible() -> void:
	image_viewer.load_images(street_images)
	image_viewer.current_image_index = 0
	image_viewer.visible = true

	# Force the pin popup closed, playing the same fold animation
	# that hover-exit uses, regardless of current hover/pinned state.
	_popup_pinned = false
	_popup_hovering = false
	_refresh_popup()

func _on_pin_hover_entered() -> void:
	_hover_count += 1
	if _hover_count == 1:
		_scale_pin(_pin_rest_scale * hover_scale)
		if not _last_pointer_was_touch:   # preview only for mouse hover
			_popup_hovering = true
			_refresh_popup()

func _on_pin_hover_exited() -> void:
	_hover_count = max(_hover_count - 1, 0)
	if _hover_count == 0:
		_scale_pin(_pin_rest_scale)
		_popup_hovering = false
		_refresh_popup()

func _scale_pin(target_scale: Vector2) -> void:
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()

	# Anchor point in local coords (center of the pin).
	var anchor := pins_texture.size * 0.5
	# Where that anchor sits in the parent right now.
	var anchor_global := pins_texture.position + anchor * pins_texture.scale

	_hover_tween = create_tween().set_parallel()
	_hover_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(pins_texture, "scale", target_scale, hover_duration)
	# Move position so the anchor stays at anchor_global as scale grows.
	var target_pos := anchor_global - anchor * target_scale
	_hover_tween.tween_property(pins_texture, "position", target_pos, hover_duration)


func _open_link(url: String) -> void:
	if OS.has_feature("JavaScript"):
		JavaScriptBridge.eval("window.open('%s', '_blank').focus();" % url)
	else:
		OS.shell_open(url)


func _open_link_press() -> void:
	_open_link("https://svendborghistorie.dk/historier/kirker-og-menigheder/312-vor-frue-kirke?highlight=WyJ2b3IiLCJmcnVlIiwia2lya2UiXQ==")
