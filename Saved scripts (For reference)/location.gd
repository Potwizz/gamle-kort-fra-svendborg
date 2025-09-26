class_name Location extends Control

@onready var texture_rect: TextureRect = %TextureRect
@onready var next_button: Button = %NextButton
@onready var previous_button: Button = %PreviousButton
@onready var rich_text_label: RichTextLabel = %RichTextLabel
@onready var fullscreen_image: TextureRect = %FullscreenImage
@onready var fullscreen_button: Button = %FullscreenButton
@onready var fullscreen_exit_button: Button = %FullscreenExitButton
@onready var image_viewer: HBoxContainer = %ImageViewer
@onready var fullscreen_viewer: CenterContainer = %FullscreenViewer
@onready var back_to_map: Button = %BackToMap
@onready var audio_player: Control = %AudioPlayer

@export var backToMap = "res://Scenes/map.tscn"

var image_array = [
	preload("res://Assets Prototyping/df.PNG"),
	preload("res://Assets Prototyping/fdf.PNG"),
	preload("res://Assets Prototyping/fsdgfg.PNG")
]
# Holds the current index of the displayed image
var current_image_index := 0

func _ready() -> void:
	show_image()
	back_to_map.pressed.connect(change_scene)
	next_button.pressed.connect(next_image)
	previous_button.pressed.connect(previous_image)
	fullscreen_button.pressed.connect(show_fullscreen_image)
	fullscreen_exit_button.pressed.connect(func() -> void:
		fullscreen_viewer.visible = false
		image_viewer.visible = true
		rich_text_label.visible = true
		audio_player.visible = true
		)

## Image code
# Shows current index image in the TextureRect texture property.
func show_image() -> void:
	var current_item = image_array[current_image_index]
	texture_rect.texture = current_item

# For viewing the images, taking up most of the screen space.
func show_fullscreen_image() -> void:
	var current_item = image_array[current_image_index]
	fullscreen_image.texture = current_item
	fullscreen_viewer.visible = true
	
	audio_player.visible = false
	image_viewer.visible = false
	rich_text_label.visible = false

# Advances to next image in the array and calls show_image to display the new image.
func next_image() -> void:
	# Why does size not use index numbers? + 1 to match array size from 1-X and not 0-X
	if current_image_index + 1 == image_array.size():
		current_image_index = 0
	else:
		current_image_index += 1
	show_image()

# Regress to previous image in the array and displays it.
func previous_image() -> void:
	if current_image_index == 0:
		current_image_index = image_array.size() - 1
	else:
		current_image_index -= 1
	show_image()


func change_scene() -> void:
	get_tree().change_scene_to_file(backToMap)
