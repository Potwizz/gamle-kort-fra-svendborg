extends Control

@onready var map_textureRect: TextureRect = %MapTexture
@onready var button_menu: VBoxContainer = %ButtonMenu
@onready var button = Button
@onready var info_box_button: Button = %InfoBoxButton
@onready var info_box_text: RichTextLabel = %InfoBoxText
#@onready var camera := get_viewport().get_camera_2d()

@export var map_entries: Array[MapData] = []

## AI code for UI scaling mobile
#@export var reference_resolution := Vector2(1920, 1200)
#@export var min_scale := 1.0
#@export var max_scale := 2.0

func _ready() -> void:
	#_update_ui_scale()
	#get_viewport().size_changed.connect(_update_ui_scale)
	map_buttons()
	info_box_button.pressed.connect(info_box_visible)
	

## AI function for ui scale
#func _update_ui_scale():
	#var viewport_size = get_viewport().get_visible_rect().size
#
	## Scale relative to height (best for mobile)
	#var scale_factor = viewport_size.y / reference_resolution.y
	#scale_factor = clamp(scale_factor, min_scale, max_scale)
	#scale = Vector2.ONE * scale_factor

# Create buttons on runtime and store MapEntries dictionary data for each button
func map_buttons() -> void:
	for entries in map_entries:
		button = Button.new()
		button_menu.add_child(button)
		button.text = entries.button_text
		button.theme = preload("res://Themes/location_theme.tres")
		button.name = entries.button_text
		button.pressed.connect(func() -> void:
			map_textureRect.texture = entries.map_texture
			info_box_text.text = entries.info_text
			)

func info_box_visible() -> void:
	if info_box_text.visible == false:
		info_box_text.visible = true
		#info_box_button.visible = false
	else:
		info_box_text.visible = false
		#info_box_button.visible = true
