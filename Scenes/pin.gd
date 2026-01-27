@tool
extends Control

@onready var pin_label: RichTextLabel = %PinText
@onready var toggle_visibility: Button = %ToggleVisibility

@export var pin_texture: Texture = null
@export var pin_text: String = ""
@export var pin_number: int = 0
#@export var map_entries: Array[MapData] = []
@export var world_position: Vector2

func _ready() -> void:
	toggle_visibility.icon = pin_texture
	pin_label.text = pin_text
	toggle_visibility.pressed.connect(text_visible)

func _process(_delta):
	position = get_viewport().get_canvas_transform() * world_position

func text_visible() -> void:
	if pin_label.visible == false:
			pin_label.visible = true
	else:
		pin_label.visible = false
	print("Is clicked!")

#func pin_settings() -> void:
	#for entries in map_entries:
		#pin_text.text = entries.info_text
		#toggle_visibility.icon = entries.pin_texture
