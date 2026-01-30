extends Camera2D

#@onready var _map_texture: TextureRect = %MapTexture
@onready var _camera_2d: Camera2D = %Camera2D
@onready var map_texture: TextureRect = %MapTexture
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton

@export var zoom_speed: float = 0.005
@export var drag_speed: float = 1.0
@export var min_zoom: float = 0.2
@export var max_zoom: float = 2.0

## Max zoom in
var zoom_in := 2.0
## Max zoom out
var zoom_out := 0.5

#func _ready() -> void:
	#_camera_2d.limit_left = 0.0
	#_camera_2d.limit_top = 0.0
	#_camera_2d.limit_right = map_texture.size.x
	#_camera_2d.limit_bottom = map_texture.size.y

func _ready() -> void:
	zoom_in_button.pressed.connect(ZoomIn)
	zoom_out_button.pressed.connect(ZoomOut)

func _process(_delta: float) -> void:
	var current_zoom_x = _camera_2d.zoom.x
	var current_zoom_y = _camera_2d.zoom.y
	if Input.is_action_just_pressed("Scroll Up"):
		if current_zoom_x < zoom_in:
			_camera_2d.zoom.x = current_zoom_x + 0.2
			_camera_2d.zoom.y = current_zoom_y + 0.2
	if Input.is_action_just_pressed("Scroll Down"):
		if current_zoom_x > zoom_out:
			_camera_2d.zoom.x = current_zoom_x - 0.2
			_camera_2d.zoom.y = current_zoom_y - 0.2
	
	#if Input.is_action_just_pressed("Scroll Up"):
		#zoom -= Vector2.ONE * zoom_speed
	#
	#if Input.is_action_just_pressed("Scroll Down"):
		#zoom += Vector2.ONE * zoom_speed
	#
	#zoom = Vector2.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.001))
	#zoom = zoom.clamp(Vector2.ONE * min_zoom, Vector2.ONE * max_zoom)

func ZoomIn() -> void:
	var current_zoom_x = _camera_2d.zoom.x
	var current_zoom_y = _camera_2d.zoom.y
	if current_zoom_x < zoom_in:
		_camera_2d.zoom.x = current_zoom_x + 0.4
		_camera_2d.zoom.y = current_zoom_y + 0.4

func ZoomOut() -> void:
	var current_zoom_x = _camera_2d.zoom.x
	var current_zoom_y = _camera_2d.zoom.y
	if current_zoom_x >= zoom_out:
			_camera_2d.zoom.x = current_zoom_x - 0.2
			_camera_2d.zoom.y = current_zoom_y - 0.2

#func _unhandled_input(event: InputEvent) -> void:
		#if event is InputEventMouseMotion:
			#if event.button_mask == MOUSE_BUTTON_MASK_LEFT:
				#position -= event.screen_relative / zoom
		#if event is InputEventMouseButton:
			#if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				#zoom += Vector2(0.1, 0.1) 

var _touches: Dictionary = {}
var _last_distance: float = 0.0
var _last_drag_pos: Vector2 = Vector2.ZERO

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
			_last_distance = 0.0
			_last_drag_pos = Vector2.ZERO

	if event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index] = event.position

		if _touches.size() == 1:
			_handle_drag(event)

	if _touches.size() == 2:
		_handle_pinch()

func _handle_drag(event: InputEventScreenDrag):
	if _last_drag_pos == Vector2.ZERO:
		_last_drag_pos = event.position
		return

	var delta := event.position - _last_drag_pos
	position -= delta * drag_speed / zoom.x
	_last_drag_pos = event.position

func _handle_pinch():
	var points := _touches.values()
	var distance: float = points[0].distance_to(points[1])

	if _last_distance > 0.0:
		var delta := distance - _last_distance
		var new_zoom := zoom.x + delta * zoom_speed
		new_zoom = clamp(new_zoom, min_zoom, max_zoom)
		zoom = Vector2(new_zoom, new_zoom)

	_last_distance = distance
