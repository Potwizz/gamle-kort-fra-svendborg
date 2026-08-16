class_name Map extends Control

@onready var map_texture: TextureRect = %MapTexture
@onready var menu_bar: ColorRect = %MenuBar
@onready var image_viewer: ImageViewer = %ImageViewer
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var info_box_text: Panel = %BackgroundPanel
@onready var index_box: Control = %IndexBox
@onready var background_panel_index: Panel = %BackgroundPanelIndex

var focus_tween: Tween


var zoom := 1.0
var min_zoom := 0.5
var max_zoom := 3.0

# Mouse
var dragging := false
var last_mouse_pos := Vector2.ZERO
var drag_velocity := Vector2.ZERO
var velocity_tween: Tween

# Touch
var touch_positions := {}
var prev_touch_positions := {}
var session_max_fingers := 0  # Max fingers seen since all fingers last lifted
var touch_active := false  # Suppresses synthetic mouse events during touch

# Suppresses pin clicks once a gesture has moved past a small threshold,
# so releasing a genuine drag on top of a pin doesn't also activate it,
# while a near-stationary tap still clicks normally.
var gesture_start_pos := Vector2.ZERO
var pins_suppressed := false
const PIN_SUPPRESS_DRAG_THRESHOLD := 8.0


func _ready() -> void:
	map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	map_texture.anchor_left = 0
	map_texture.anchor_top = 0
	map_texture.anchor_right = 0
	map_texture.anchor_bottom = 0
	map_texture.clip_contents = false
	self.clip_contents = false

	zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# menu_bar lives under a separate CanvasLayer branch (Desktop-GUI), so
	# its size can settle on a different frame than the viewport's own
	# resize - re-run the layout whenever menu_bar's actual size changes,
	# for whatever reason, rather than trying to guess/poll for when
	# that's finished happening.
	menu_bar.resized.connect(_on_viewport_size_changed)

	# Nothing external ever calls show_map() - if a texture is already
	# assigned on map_texture (e.g. set directly in the editor's
	# Inspector rather than loaded at runtime), kick off the same
	# centering/zoom flow ourselves using it, instead of waiting forever
	# for an external call that never comes.
	if map_texture.texture:
		show_map(map_texture.texture)

	info_box_text.mouse_filter = Control.MOUSE_FILTER_PASS


## Once a gesture has moved past PIN_SUPPRESS_DRAG_THRESHOLD from where it
## started, disables clicking on every pin for the rest of this gesture.
## Idempotent - safe to call on every motion event, only actually acts once.
func _maybe_suppress_pins_for_drag(current_pos: Vector2) -> void:
	if pins_suppressed:
		return
	if current_pos.distance_to(gesture_start_pos) > PIN_SUPPRESS_DRAG_THRESHOLD:
		pins_suppressed = true
		_set_pins_input_enabled(false)


## Re-enables pin clicks if this gesture had suppressed them. Safe to call
## unconditionally on every release - it's a no-op if nothing was suppressed.
func _restore_pins_if_suppressed() -> void:
	if pins_suppressed:
		pins_suppressed = false
		_set_pins_input_enabled(true)


func _set_pins_input_enabled(enabled: bool) -> void:
	for pin_group in map_texture.get_children():
		for pin in pin_group.get_children():
			if pin.has_method("set_input_enabled"):
				pin.set_input_enabled(enabled)


func _on_zoom_in_pressed() -> void:
	_zoom_at_point(1.2, get_viewport_rect().size * 0.5)


func _on_zoom_out_pressed() -> void:
	_zoom_at_point(0.8, get_viewport_rect().size * 0.5)


func _usable_height() -> float:
	return get_viewport_rect().size.y - menu_bar.size.y


func _is_over_menu_bar(pos: Vector2) -> bool:
	return pos.y >= get_viewport_rect().size.y - menu_bar.size.y


func _is_over_text_box(pos: Vector2) -> bool:
	for box: Control in [info_box_text, index_box, background_panel_index]:
		if not box.is_visible_in_tree():
			continue
		if box.get_global_rect().has_point(pos):
			return true
	return false


func show_map(texture: Texture2D) -> void:
	map_texture.texture = texture
	map_texture.size = map_texture.texture.get_size()

	# On mobile web the browser canvas can still be resizing for a few
	# frames after load (address bar collapsing, safe-area insets settling,
	# orientation). Wait until the reported viewport size stops changing
	# before we use it to compute min_zoom / centering, otherwise the
	# initial view gets laid out against a stale size.
	await _wait_for_stable_viewport()

	_apply_min_zoom_centered_view()
	_update_pin_scales()
	_clamp_position()


## Polls get_viewport_rect().size AND _usable_height() once per frame
## until BOTH stop changing between two consecutive frames (or max_checks
## is hit, so this can never hang forever if something keeps nudging the
## size). Checking usable_height too - not just raw viewport size -
## matters because it depends on menu_bar.size.y, and menu_bar's own
## layout can still be settling for a frame or two even after the
## viewport itself has stopped resizing, on desktop as well as mobile.
func _wait_for_stable_viewport(max_checks: int = 15) -> void:
	await get_tree().process_frame
	var last_size := get_viewport_rect().size
	var last_usable_h := _usable_height()

	for i in max_checks:
		await get_tree().process_frame
		var current_size := get_viewport_rect().size
		var current_usable_h := _usable_height()
		if current_size == last_size and current_usable_h == last_usable_h:
			return
		last_size = current_size
		last_usable_h = current_usable_h


## Sets zoom to the minimum (most zoomed-out) value that still fully covers
## the viewport, and centers the texture within the usable area.
func _apply_min_zoom_centered_view() -> void:
	if map_texture.texture == null:
		return

	min_zoom = _get_min_zoom()
	zoom = min_zoom
	map_texture.scale = Vector2.ONE * zoom

	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	var tex := map_texture.texture.get_size() * zoom
	map_texture.position = Vector2((vp.x - tex.x) * 0.5, (usable_h - tex.y) * 0.5)


func _input(event: InputEvent) -> void:
	if image_viewer.visible:
		return

	if event is InputEventMouseButton:
		if touch_active:  # Ignore synthetic mouse events fired by touch input
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _is_over_menu_bar(event.position):
					return
				if _is_over_text_box(event.position):
					return
				dragging = true
				gesture_start_pos = event.position
				drag_velocity = Vector2.ZERO
				if velocity_tween:
					velocity_tween.kill()
			else:
				if dragging:
					dragging = false
					_start_velocity_decay()
				_restore_pins_if_suppressed()
			last_mouse_pos = event.position

		if event.pressed:
			if _is_over_menu_bar(event.position):
				return
			if _is_over_text_box(event.position):
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at_point(1.1, event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at_point(0.9, event.position)

	elif event is InputEventMouseMotion and dragging:
		if _is_over_text_box(event.position):
			dragging = false
			_restore_pins_if_suppressed()
			return
		_maybe_suppress_pins_for_drag(event.position)
		var delta: Vector2 = event.position - last_mouse_pos
		drag_velocity = delta
		map_texture.position += delta
		_clamp_position()
		last_mouse_pos = event.position

	elif event is InputEventScreenTouch:
		if event.pressed:
			if _is_over_menu_bar(event.position):
				return
			if _is_over_text_box(event.position):
				return

			# Mark touch as active and kill any mouse-driven momentum
			touch_active = true
			dragging = false
			drag_velocity = Vector2.ZERO
			if velocity_tween:
				velocity_tween.kill()

			if touch_positions.is_empty():
				gesture_start_pos = event.position  # only at the start of a new gesture

			touch_positions[event.index] = event.position
			prev_touch_positions[event.index] = event.position

			if touch_positions.size() > session_max_fingers:
				session_max_fingers = touch_positions.size()

			if session_max_fingers >= 2:
				for idx in touch_positions.keys():
					prev_touch_positions[idx] = touch_positions[idx]
		else:
			touch_positions.erase(event.index)
			prev_touch_positions.erase(event.index)

			if touch_positions.is_empty():
				touch_active = false  # All fingers lifted — re-enable mouse events
				var was_single_finger := session_max_fingers == 1
				session_max_fingers = 0
				if was_single_finger:
					_start_velocity_decay()
				else:
					drag_velocity = Vector2.ZERO
				_restore_pins_if_suppressed()
			else:
				for idx in touch_positions.keys():
					prev_touch_positions[idx] = touch_positions[idx]

	elif event is InputEventScreenDrag:
		if _is_over_menu_bar(event.position):
			return
		if _is_over_text_box(event.position):
			return
		_maybe_suppress_pins_for_drag(event.position)
		touch_positions[event.index] = event.position
		if touch_positions.size() > session_max_fingers:
			session_max_fingers = touch_positions.size()


func _process(_delta: float) -> void:
	if image_viewer.visible:
		return
	if touch_positions.is_empty():
		return

	var count := touch_positions.size()
	var keys: Array = touch_positions.keys()

	# Single finger pan — only if this session never had 2+ fingers
	if count == 1 and session_max_fingers == 1:
		var idx = keys[0]
		var curr: Vector2 = touch_positions[idx]
		var prev: Vector2 = prev_touch_positions.get(idx, curr)
		var delta := curr - prev

		if delta.length() > 0.5:
			drag_velocity = delta
			map_texture.position += delta
			_clamp_position()

		prev_touch_positions[idx] = curr

	# Pinch zoom — only when 2+ fingers present
	elif count >= 2:
		var idx_a = keys[0]
		var idx_b = keys[1]

		var curr_a: Vector2 = touch_positions[idx_a]
		var curr_b: Vector2 = touch_positions[idx_b]
		var prev_a: Vector2 = prev_touch_positions.get(idx_a, curr_a)
		var prev_b: Vector2 = prev_touch_positions.get(idx_b, curr_b)

		var prev_dist := prev_a.distance_to(prev_b)
		var curr_dist := curr_a.distance_to(curr_b)

		if prev_dist > 5.0 and curr_dist > 5.0:
			var zoom_factor := curr_dist / prev_dist
			if abs(zoom_factor - 1.0) > 0.001:
				_zoom_at_point(zoom_factor, get_viewport_rect().size * 0.5)

		prev_touch_positions[idx_a] = curr_a
		prev_touch_positions[idx_b] = curr_b


func _gui_input(_event: InputEvent) -> void:
	pass


func _zoom_at_point(factor: float, center: Vector2) -> void:
	var new_zoom: float = clamp(zoom * factor, min_zoom, max_zoom)
	factor = new_zoom / zoom
	zoom = new_zoom

	map_texture.position = center + (map_texture.position - center) * factor
	map_texture.scale = Vector2.ONE * zoom

	_update_pin_scales()
	_clamp_position()


func _clamp_position_for(pos: Vector2, at_zoom: float) -> Vector2:
	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	var display_size := map_texture.texture.get_size() * at_zoom

	if display_size.x <= vp.x:
		pos.x = (vp.x - display_size.x) * 0.5
	else:
		pos.x = clamp(pos.x, vp.x - display_size.x, 0.0)

	if display_size.y <= usable_h:
		pos.y = (usable_h - display_size.y) * 0.5
	else:
		pos.y = clamp(pos.y, usable_h - display_size.y, 0.0)

	return pos


func _clamp_position() -> void:
	map_texture.position = _clamp_position_for(map_texture.position, zoom)


func _get_min_zoom() -> float:
	if map_texture.texture == null:
		return 1.0

	var texture_size := map_texture.texture.get_size()
	var vp := get_viewport_rect().size
	var usable_h := _usable_height()

	return max(vp.x / texture_size.x, usable_h / texture_size.y)


func reset_view() -> void:
	if map_texture.texture == null:
		return

	_apply_min_zoom_centered_view()
	_clamp_position()


func _start_velocity_decay() -> void:
	if drag_velocity.length() < 1.0:
		return

	if velocity_tween:
		velocity_tween.kill()

	velocity_tween = create_tween()
	velocity_tween.set_trans(Tween.TRANS_CUBIC)
	velocity_tween.set_ease(Tween.EASE_OUT)

	var start_velocity := drag_velocity
	velocity_tween.tween_method(_apply_velocity_step.bind(start_velocity), 1.0, 0.0, 0.6)


func _apply_velocity_step(t: float, start_velocity: Vector2) -> void:
	map_texture.position += start_velocity * t
	_clamp_position()


func _update_pin_scales() -> void:
	for pin_group in map_texture.get_children():
		for pin in pin_group.get_children():
			if pin.size == Vector2.ZERO:
				pin.size = Vector2(64, 64)
			if not pin.has_meta("map_coord"):
				pin.set_meta("map_coord", pin.position)
			# Offset by half the pin's display size so its center
			# stays locked to the map coordinate rather than its top-left.
			var half_size: Vector2 = pin.size * 0.5 / zoom
			pin.position = pin.get_meta("map_coord") - half_size
			pin.pivot_offset = Vector2.ZERO
			pin.scale = Vector2.ONE / zoom

func _on_viewport_size_changed() -> void:
	if map_texture.texture == null:
		return

	map_texture.size = map_texture.texture.get_size()
	_apply_min_zoom_centered_view()
	_update_pin_scales()
	_clamp_position()


## Smoothly pans/zooms the map so the given pin is centered in the viewport.
## target_zoom < 0 means "keep current zoom level".
func focus_on_pin(pin: Control, target_zoom: float = -1.0, duration: float = 0.6) -> void:
	if map_texture.texture == null:
		return

	# Stop any ongoing drag momentum or in-progress focus animation.
	dragging = false
	drag_velocity = Vector2.ZERO
	if velocity_tween:
		velocity_tween.kill()
	if focus_tween:
		focus_tween.kill()

	if not pin.has_meta("map_coord"):
		pin.set_meta("map_coord", pin.position)
	var map_coord: Vector2 = pin.get_meta("map_coord")

	if target_zoom < 0.0:
		target_zoom = zoom
	target_zoom = clamp(target_zoom, min_zoom, max_zoom)

	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	var target_center := Vector2(vp.x * 0.5, usable_h * 0.5)
	var target_position := _clamp_position_for(target_center - map_coord * target_zoom, target_zoom)

	var start_zoom := zoom
	var start_position := map_texture.position

	focus_tween = create_tween()
	focus_tween.set_trans(Tween.TRANS_CUBIC)
	focus_tween.set_ease(Tween.EASE_OUT)
	focus_tween.tween_method(
		func(t: float) -> void:
			zoom = lerp(start_zoom, target_zoom, t)
			map_texture.scale = Vector2.ONE * zoom
			map_texture.position = start_position.lerp(target_position, t)
			_update_pin_scales(),
		0.0, 1.0, duration
	)
