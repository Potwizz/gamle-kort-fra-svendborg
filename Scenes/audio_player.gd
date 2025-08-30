extends Control

@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer
@onready var timer: Timer = %Timer
@onready var h_slider: HSlider = %HSlider
@onready var _time_display: Label = %Label
@onready var play_button: Button = %PlayButton

var pause_icon = preload("res://Assets/Icons/pause.png")
var play_icon = preload("res://Assets/Icons/cursor_right.png")


func _ready() -> void:
		play_button.pressed.connect(play_audio)


# For updating the playback tracker for audio.
func _physics_process(_delta: float) -> void:
	audio_time_tracker()


## Playback sound code
# A play and pause button. Can continue from where the audio left off.
func play_audio() -> void:
	if audio_stream_player.playing == true:
		audio_stream_player.stream_paused = true
		play_button.icon = play_icon
	elif audio_stream_player.stream_paused == true:
		audio_stream_player.stream_paused = false
		play_button.icon = pause_icon
	else:
		audio_stream_player.playing = true
		play_button.icon = pause_icon

# Tracks current time for playback. (IMPLEMENT VISUAL SECONDS LATER)
func audio_time_tracker() -> void:
	var current_audio_time = audio_stream_player.get_playback_position()
	var audio_length = audio_stream_player.stream.get_length()
	#timer.wait_time = audio_stream_player.stream.get_length()
	h_slider.max_value = audio_length
	h_slider.value = current_audio_time
	_time_display.text = str("%0.1f" % current_audio_time) + '/' + str("%0.1f" % audio_length)
	
