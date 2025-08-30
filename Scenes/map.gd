extends Control

@onready var place_of_interest: Button = %PlaceOfInterest
@onready var map_texture: TextureRect = %MapTexture
@onready var background_shader: ColorRect = %BackgroundShader
@onready var resen: Button = %Resen
@onready var ww_2: Button = %ww2

var resen_map := preload("res://Assets/Images/maps/k36-resen-1677.jpg")

# Change to packedscene. Figure out how to 
var ww2_kort := preload("res://Assets/Images/maps/ww2-kort.jpg")

func _ready() -> void:
	resen.pressed.connect(change_map_resen)
	ww_2.pressed.connect(change_map_ww2)

func change_map_resen() -> void:
	map_texture.texture = resen_map

func change_map_ww2() -> void:
	map_texture.texture = ww2_kort
#THIS IS FOR GIT
