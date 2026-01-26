extends Camera2D

#@onready var _map_texture: TextureRect = %MapTexture
@onready var _camera_2d: Camera2D = %Camera2D
@onready var map_texture: TextureRect = %MapTexture
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var zoom_out_button_mobile: Button = %ZoomOutButtonMobile
@onready var zoom_in_button_mobile: Button = %ZoomInButtonMobile

## Max zoom in
var zoom_in := 2.0
## Max zoom out
var zoom_out := 0.5

#func _ready() -> void:
	##_camera_2d.limit_left = 0.0
	##_camera_2d.limit_top = 0.0
	##_camera_2d.limit_right = map_texture.size.x
	##_camera_2d.limit_bottom = map_texture.size.y

func _ready() -> void:
	zoom_in_button.pressed.connect(ZoomIn)
	zoom_out_button.pressed.connect(ZoomOut)
	zoom_in_button_mobile.pressed.connect(ZoomIn)
	zoom_out_button_mobile.pressed.connect(ZoomOut)

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

func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			if event.button_mask == MOUSE_BUTTON_MASK_LEFT:
				position -= event.screen_relative / zoom
		#if event is InputEventMouseButton:
			#if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				#zoom += Vector2(0.1, 0.1) 
