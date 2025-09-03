extends Control

@onready var map_textureRect: TextureRect = %MapTexture
@onready var button_menu: VBoxContainer = %ButtonMenu
@onready var button = Button
@onready var info_box_button: Button = %InfoBoxButton
@onready var info_box_text: RichTextLabel = %InfoBoxText

@export var map_entries: Array[MapData] = []

func _ready() -> void:
	map_buttons()
	info_box_button.pressed.connect(info_box_visible)

# Create buttons on runtime and store MapEntries dictionary data for each button
func map_buttons() -> void:
	for entries in map_entries:
		button = Button.new()
		button_menu.add_child(button)
		button.text = entries.button_text
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
