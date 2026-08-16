class_name ImageViewer extends Control

@onready var image_texture: TextureRect = %ImageTexture
@onready var next_button: Button = %NextButton
@onready var previous_button: Button = %PreviousButton
@onready var back_to_map: Button = %BackToMap
@onready var image_viewer: Control = %ImageViewer
@onready var image_texture_next: TextureRect = %ImageTextureNext
@onready var menu_bar: ColorRect = %MenuBar
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var image_text_button: Button = %ImageTextButton
@onready var image_text: RichTextLabel = %ImageText
@onready var info_box_text: Panel = %BackgroundPanel
@onready var index_box: Control = %IndexBox
@onready var image_desc: Control = %ImageDesc
@onready var image_text_box_close: Button = %ImageTextBoxClose
@onready var background_panel_index: Panel = %BackgroundPanelIndex
@onready var background_panel_image_text: Panel = %BackgroundPanelImageText


var zoom := 1.0
var min_zoom := 0.5
var max_zoom := 3.0
var current_image_index := 0
var dragging := false
var last_mouse_pos := Vector2.ZERO
var last_pinch_dist := -1.0
var touches := {}
var is_pinching := false
var tween: Tween
var is_animating := false
var drag_velocity := Vector2.ZERO
var velocity_tween: Tween
var swipe_offset: float = 0.0
var is_swiping := false
var swipe_neighbour_index := 0
var touch_active := false
var pinch_just_ended := false

const SWIPE_THRESHOLD := 0.3
const PRELOAD_WINDOW := 1  # how many images ahead/behind of the current one to prefetch
const MAX_CONCURRENT_PRELOADS := 2  # how many pin-preload downloads run at once
const PRELOAD_PACE_SECONDS := 0.2  # real-time pause between each worker's downloads
const IMAGE_MAX_WIDTH := 1200  # cap requested width via Cloudinary transform - tune to taste
const SWIPE_PREVIEW_MAX_WIDTH := 640  # much smaller/faster fallback shown only during an active drag

# Instead of holding actual Texture assets, we now hold URLs and resolve them
# to Texture2D on demand via HTTPRequest, caching the result per URL.
var image_urls: Array[String] = []
var local_image_data: Array[StreetImages] = []  # full resources, for text/etc.

var _texture_cache: Dictionary = {}   # url:String -> Texture2D
var _in_flight: Dictionary = {}       # url:String -> HTTPRequest (request currently in progress)


## We make a data argument that takes the local image data
## and in the loop we iterate on each entry to pull out its image URL.
## NOTE: this assumes StreetImages now exposes `image_url: String`
## instead of (or in addition to) a `street_image: Texture` field.
func load_images(data: Array[StreetImages]) -> void:
	local_image_data = data
	image_urls = []
	for entry in data:
		image_urls.append(_resized_image_url(entry.image_url))


## Rewrites a Cloudinary delivery URL to request a capped-width,
## auto-quality version instead of the full original, by inserting a
## transform segment right after "/upload/". Falls back to the URL
## unchanged if it doesn't look like a Cloudinary upload URL, so it's safe
## to call on any URL regardless of host.
##
## This matters more than it might look: a 3835px-wide source photo costs
## roughly (3835/1600)^2 ~= 5.7x more to decode and GPU-upload than the
## same photo capped at max_width, for zero visual benefit, since the
## viewer always displays images scaled down to fit the screen anyway.
## Deliberately omits f_auto: Cloudinary's f_auto can serve AVIF to
## browsers that advertise support for it, and Godot's Image class has no
## AVIF decoder - staying on the already-working webp/jpg/png keeps
## _decode_image's format handling valid. c_limit stops it from ever
## upscaling a source image that's already smaller than the cap.
##
## `max_width` defaults to IMAGE_MAX_WIDTH (the standard display size);
## pass SWIPE_PREVIEW_MAX_WIDTH to get the much smaller, faster variant
## used as a transient fallback during active swipes - see _setup_neighbour.
func _resized_image_url(url: String, max_width: int = IMAGE_MAX_WIDTH) -> String:
	var marker := "/upload/"
	var idx := url.find(marker)
	if idx == -1:
		return url
	var insert_at := idx + marker.length()
	var transform := "w_%d,c_limit,q_auto" % max_width
	return url.substr(0, insert_at) + transform + "/" + url.substr(insert_at)


func _update_image_text() -> void:
	if local_image_data.is_empty() or current_image_index >= local_image_data.size():
		image_text.text = ""
		return
	image_text.text = local_image_data[current_image_index].image_text


func _ready() -> void:
	image_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	image_texture.anchor_left = 0
	image_texture.anchor_top = 0
	image_texture.anchor_right = 0
	image_texture.anchor_bottom = 0
	image_texture.clip_contents = false
	image_texture.z_index = 0

	image_texture_next.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	image_texture_next.anchor_left = 0
	image_texture_next.anchor_top = 0
	image_texture_next.anchor_right = 0
	image_texture_next.anchor_bottom = 0
	image_texture_next.clip_contents = false
	image_texture_next.z_index = 1

	self.clip_contents = false

	next_button.pressed.connect(next_image)
	previous_button.pressed.connect(previous_image)
	back_to_map.pressed.connect(change_scene)
	image_text_button.pressed.connect(_image_text_visible)
	image_text_box_close.pressed.connect(_image_text_visible)
	_add_bigger_hit_area(image_text_box_close, _image_text_visible)

	get_viewport().size_changed.connect(_on_viewport_size_changed)
	image_viewer.visibility_changed.connect(_on_image_viewer_visibility_changed)

	show_image()

	zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	zoom_out_button.pressed.connect(_on_zoom_out_pressed)


func _image_text_visible() -> void:
	if image_desc.visible == false:
		image_desc.visible = true
	else:
		image_desc.visible = false


## Closes the ImageDesc text box when a press (mouse or touch) lands
## outside it - the usual "click away to dismiss" pattern. Checked on
## press (not release), before _is_over_ui's own drag-start gate, so a tap
## outside the box both dismisses it AND can immediately start dragging/
## swiping the image beneath it in the same motion. Excludes the box
## itself and its own open/close buttons so those keep working normally
## via their own release-triggered toggle instead of being fought here.
func _maybe_close_image_desc(pos: Vector2) -> void:
	if not image_desc.visible:
		return
	if _is_over_controls(pos, [image_desc, background_panel_image_text, image_text_button, image_text_box_close]):
		return
	image_desc.visible = false


func _is_over_controls(pos: Vector2, controls: Array[Control]) -> bool:
	for control in controls:
		if control.get_global_rect().has_point(pos):
			return true
	return false


## Adds a fully invisible, larger Button on top of `button` so it's easier
## to tap on mobile, without changing `button`'s own size, position, or
## appearance at all. Assumes `button` is freely positioned (anchors/manual
## position), NOT laid out inside a Container - a Container would just
## re-lay out the new sibling and ignore the position/size set below.
func _add_bigger_hit_area(button: Button, on_pressed: Callable, padding: float = 16.0) -> void:
	var hit_area := Button.new()
	hit_area.flat = true
	hit_area.focus_mode = Control.FOCUS_NONE
	hit_area.mouse_filter = Control.MOUSE_FILTER_STOP

	# Fully transparent in every state, so nothing is drawn - this button
	# exists purely to catch taps, not to be seen.
	var empty_style := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		hit_area.add_theme_stylebox_override(state, empty_style)

	var parent := button.get_parent()
	parent.add_child(hit_area)
	parent.move_child(hit_area, button.get_index() + 1)  # draw on top, after button

	hit_area.position = button.position - Vector2(padding, padding)
	hit_area.size = button.size + Vector2(padding, padding) * 2
	hit_area.pressed.connect(on_pressed)


func _on_zoom_in_pressed() -> void:
	var center := get_viewport_rect().size * 0.5
	_zoom_at_point(1.2, center)


func _on_zoom_out_pressed() -> void:
	var center := get_viewport_rect().size * 0.5
	_zoom_at_point(0.8, center)


func _usable_height() -> float:
	return get_viewport_rect().size.y - menu_bar.size.y


func _is_over_menu_bar(pos: Vector2) -> bool:
	return pos.y >= get_viewport_rect().size.y - menu_bar.size.y


func _is_over_ui(pos: Vector2) -> bool:
	if _is_over_menu_bar(pos):
		return true
	if _is_over_text_box(pos):
		return true
	if next_button.get_global_rect().has_point(pos):
		return true
	if previous_button.get_global_rect().has_point(pos):
		return true
	if back_to_map.get_global_rect().has_point(pos):
		return true
	if image_text_button.get_global_rect().has_point(pos):
		return true
	if image_text_box_close.get_global_rect().has_point(pos):
		return true
	return false

func _is_over_text_box(pos: Vector2) -> bool:
	for box: Control in [image_desc, index_box, info_box_text, background_panel_index, background_panel_image_text]:
		if not box.is_visible_in_tree():
			continue
		if box.get_global_rect().has_point(pos):
			return true
	return false


# ---------------------------------------------------------------------------
# Remote texture loading
# ---------------------------------------------------------------------------

## Resolves a texture for `url`, downloading it if it isn't cached yet.
## Safe to call multiple times concurrently for the same URL - concurrent
## callers will share the same in-flight request instead of firing duplicates.
## If `reusable_request` is given, that HTTPRequest node is used instead of
## creating and destroying a new one for this call - see _preload_worker,
## which keeps one persistent node per worker to avoid the alloc/free churn
## of a fresh node per download (a likely source of hitches on Web export).
func _get_texture(url: String, reusable_request: HTTPRequest = null) -> Texture2D:
	if url.is_empty():
		return null

	if _texture_cache.has(url):
		return _texture_cache[url]

	if _in_flight.has(url):
		var existing: HTTPRequest = _in_flight[url]
		await existing.request_completed
		return _texture_cache.get(url, null)

	var req: HTTPRequest = reusable_request
	var owns_request := false
	if req == null:
		req = HTTPRequest.new()
		add_child(req)
		owns_request = true

	_in_flight[url] = req

	var start_err := req.request(url)
	if start_err != OK:
		push_error("Could not start request for %s (error %d)" % [url, start_err])
		_in_flight.erase(url)
		if owns_request:
			req.queue_free()
		return null

	var result: Array = await req.request_completed
	_in_flight.erase(url)

	var http_result: int = result[0]
	var response_code: int = result[1]
	var headers: PackedStringArray = result[2]
	var body: PackedByteArray = result[3]

	if owns_request:
		req.queue_free()

	if http_result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("Image request failed for %s (result=%d, code=%d)" % [url, http_result, response_code])
		return null

	var texture := _decode_image(body, url, headers)
	if texture:
		_texture_cache[url] = texture
	return texture


func _decode_image(body: PackedByteArray, url: String, headers: PackedStringArray) -> Texture2D:
	var image := Image.new()
	var err: Error

	var content_type := ""
	for h in headers:
		if h.to_lower().begins_with("content-type:"):
			content_type = h.to_lower()
			break

	var lower_url := url.to_lower()
	if "png" in content_type or lower_url.ends_with(".png"):
		err = image.load_png_from_buffer(body)
	elif "webp" in content_type or lower_url.ends_with(".webp"):
		err = image.load_webp_from_buffer(body)
	else:
		err = image.load_jpg_from_buffer(body)

	if err != OK:
		push_error("Could not decode image data from %s (error %d)" % [url, err])
		return null

	return ImageTexture.create_from_image(image)


## Fire-and-forget prefetch of the images around the current index so
## swiping/paging feels instant once the user actually triggers it. Also
## warms the small SWIPE_PREVIEW_MAX_WIDTH version of each neighbour -
## cheap on its own, and means _setup_neighbour's preview fallback often
## finds one already cached instead of starting a fetch from scratch when
## a swipe outruns the standard-resolution download.
func _preload_neighbours() -> void:
	if image_urls.size() <= 1:
		return
	for offset in range(1, PRELOAD_WINDOW + 1):
		var next_i := (current_image_index + offset) % image_urls.size()
		var prev_i := (current_image_index - offset + image_urls.size()) % image_urls.size()
		_get_texture(image_urls[next_i])
		_get_texture(image_urls[prev_i])
		_get_texture(_resized_image_url(local_image_data[next_i].image_url, SWIPE_PREVIEW_MAX_WIDTH))
		_get_texture(_resized_image_url(local_image_data[prev_i].image_url, SWIPE_PREVIEW_MAX_WIDTH))


## Public entry point for warming the cache from outside this node - e.g.
## the map scene, right after it loads, before any pin has been clicked.
## Fire-and-forget: kicks off a download if `url` isn't already cached or
## in flight, and does nothing if it already is. Safe to call redundantly.
func preload_url(url: String) -> void:
	_get_texture(url)


## Convenience for warming just the FIRST image of many pins at once - e.g.
## called once from the map scene's _ready() with every pin's image array,
## so opening any pin's viewer for the first time doesn't show a blank
## frame while that first image downloads.
##
## Deliberately throttled rather than firing every request in the same
## frame: with many pins, kicking off dozens of HTTPRequest nodes plus
## their eventual image decodes/texture uploads all at once is what causes
## a visible hitch on boot, especially on mobile. Instead this waits a
## moment for the map's own first frames to settle, then runs only a
## handful of downloads at a time (MAX_CONCURRENT_PRELOADS) with a real
## pause between each one (PRELOAD_PACE_SECONDS), spreading the cost over
## a longer stretch of time instead of bursting it into a few frames.
func preload_first_images(pins_data: Array) -> void:
	var urls: Array[String] = []
	for pin_images in pins_data:
		if pin_images == null or pin_images.is_empty():
			continue
		var first_entry: StreetImages = pin_images[0]
		if not first_entry.image_url.is_empty():
			urls.append(_resized_image_url(first_entry.image_url))

	if urls.is_empty():
		return

	# Let the map's own boot-time work (layout, pin scaling, first render)
	# finish before adding any network/decode load on top of it.
	await get_tree().create_timer(0.3).timeout

	var queue := urls.duplicate()
	var worker_count: int = min(MAX_CONCURRENT_PRELOADS, queue.size())
	for i in worker_count:
		_preload_worker(queue)  # fire-and-forget - each one drains the shared queue


## Drains `queue` one URL at a time: waits for each download+decode to
## fully finish (via _get_texture) before starting the next, then pauses
## for PRELOAD_PACE_SECONDS of real time (not just one frame) so the
## decode+texture-upload cost of consecutive images is spread further
## apart instead of clustering. Multiple workers run in parallel (spawned
## by preload_first_images) to bound total concurrency without going back
## to firing everything at once - fewer workers plus a real pause trades
## total preload time for a smoother spread, which is the right trade for
## a background cache-warm the user isn't blocked on.
##
## Uses ONE persistent HTTPRequest node for the worker's entire run rather
## than creating/destroying one per download - on Web export, repeatedly
## allocating and freeing nodes is a likely trigger for WASM heap-growth
## pauses (the browser has to copy the whole linear memory block to grow
## it), which would show up as a hitch right as each new download starts.
func _preload_worker(queue: Array[String]) -> void:
	var req := HTTPRequest.new()
	add_child(req)

	while not queue.is_empty():
		var url: String = queue.pop_front()
		await _get_texture(url, req)
		if not queue.is_empty():
			await get_tree().create_timer(PRELOAD_PACE_SECONDS).timeout

	req.queue_free()


# ---------------------------------------------------------------------------

func show_image() -> void:
	if image_urls.is_empty():
		return

	var texture: Texture2D = await _get_texture(image_urls[current_image_index])
	if texture == null:
		return

	image_texture.texture = texture

	await get_tree().process_frame

	image_texture.size = texture.get_size()

	min_zoom = _get_min_zoom()
	zoom = min_zoom

	image_texture.scale = Vector2.ONE * zoom

	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	var tex := texture.get_size() * zoom
	image_texture.position = Vector2((vp.x - tex.x) * 0.5, (usable_h - tex.y) * 0.5)

	image_texture_next.texture = null
	image_texture_next.visible = false
	_clamp_position()
	_update_image_text()

	_preload_neighbours()


func next_image() -> void:
	if is_animating or image_urls.size() <= 1:
		return
	var next_index := (current_image_index + 1) % image_urls.size()
	await _animate_transition(next_index, 1)
	current_image_index = next_index
	_update_image_text()
	_preload_neighbours()


func previous_image() -> void:
	if is_animating or image_urls.size() <= 1:
		return
	var next_index := (current_image_index - 1 + image_urls.size()) % image_urls.size()
	await _animate_transition(next_index, -1)
	current_image_index = next_index
	_update_image_text()
	_preload_neighbours()


func change_scene() -> void:
	if image_viewer.visible == true:
		image_viewer.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if touch_active:  # Ignore synthetic mouse events fired by touch input
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_maybe_close_image_desc(event.position)
				if _is_over_ui(event.position):
					return
				dragging = true
				drag_velocity = Vector2.ZERO
				if velocity_tween:
					velocity_tween.kill()
			else:
				if dragging:
					dragging = false
					if is_swiping:
						_finish_swipe()
					else:
						_start_velocity_decay()
			last_mouse_pos = event.position

		if event.pressed:
			if _is_over_ui(event.position):
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at_point(1.1, event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at_point(0.9, event.position)

	elif event is InputEventMouseMotion and dragging:
		if _is_over_ui(event.position):
			# Pointer moved over a UI panel (ImageDesc, IndexBox, etc.)
			# mid-drag - stop treating this as an image gesture instead of
			# letting the motion keep panning/swiping underneath it. This
			# mirrors the touch path, which already re-checks _is_over_ui
			# on every InputEventScreenDrag rather than only at the start.
			if is_swiping:
				_cancel_swipe()
			dragging = false
			drag_velocity = Vector2.ZERO
			last_mouse_pos = event.position
			return

		var delta: Vector2 = event.position - last_mouse_pos
		last_mouse_pos = event.position
		if is_animating:
			# A transition is already playing - ignore the drag entirely
			# instead of nudging image_texture.position underneath it,
			# which is what corrupted the display on fast repeated swipes.
			drag_velocity = Vector2.ZERO
			return
		if zoom <= min_zoom:
			_update_swipe(delta.x)
		else:
			drag_velocity = delta
			image_texture.position += delta
			_clamp_position()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_maybe_close_image_desc(event.position)
			if _is_over_ui(event.position):
				return

			touch_active = true
			dragging = false
			drag_velocity = Vector2.ZERO
			if velocity_tween:
				velocity_tween.kill()

			touches[event.index] = event.position
			if event.index == 0:
				is_pinching = false
			if touches.size() >= 2:
				is_pinching = true
				last_pinch_dist = -1.0
				drag_velocity = Vector2.ZERO
				if velocity_tween:
					velocity_tween.kill()
				if is_swiping:
					_cancel_swipe()
		else:
			touches.erase(event.index)
			last_pinch_dist = -1.0
			var was_pinching := is_pinching

			if touches.size() < 2:
				is_pinching = false
				if was_pinching:
					pinch_just_ended = true
					drag_velocity = Vector2.ZERO
					if velocity_tween:
						velocity_tween.kill()

			if touches.is_empty():
				touch_active = false
				pinch_just_ended = false

			if event.index == 0 and not is_pinching:
				if is_swiping:
					_finish_swipe()
				elif not was_pinching and not pinch_just_ended:
					_start_velocity_decay()

	elif event is InputEventScreenDrag:
		if not touches.has(event.index):
			return
		if _is_over_ui(event.position):
			touches.erase(event.index)
			return
		touches[event.index] = event.position

		if touches.size() == 1 and not is_pinching and not pinch_just_ended:
			if is_animating:
				# A transition is already playing - ignore the drag entirely
				# instead of nudging image_texture.position underneath it,
				# which is what corrupted the display on fast repeated swipes.
				drag_velocity = Vector2.ZERO
			elif zoom <= min_zoom:
				_update_swipe(event.relative.x)
			else:
				drag_velocity = event.relative
				image_texture.position += event.relative
				_clamp_position()
		elif touches.size() == 2:
			is_pinching = true
			var points: Array = touches.values()
			var current_dist: float = points[0].distance_to(points[1])

			if last_pinch_dist < 0.0:
				last_pinch_dist = current_dist
				return

			var zoom_factor := current_dist / last_pinch_dist
			var center := get_viewport_rect().size * 0.5
			_zoom_at_point(zoom_factor, center)
			last_pinch_dist = current_dist


func _setup_neighbour(direction: int) -> void:
	if image_urls.size() <= 1:
		return
	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	swipe_neighbour_index = (current_image_index + 1) % image_urls.size() if direction < 0 else (current_image_index - 1 + image_urls.size()) % image_urls.size()

	var nb_url := image_urls[swipe_neighbour_index]
	var nb_texture: Texture2D = _texture_cache.get(nb_url, null)

	if nb_texture == null:
		# Standard resolution isn't ready yet (preloading missed it, or the
		# user is swiping unusually fast). Keep warming it in the
		# background regardless, but also try a much smaller, faster
		# "quick preview" so the drag has something to show instead of
		# going blank - it's fine for this to look soft since the image is
		# actively sliding across the screen. _finish_swipe always
		# upgrades to the standard resolution before actually committing
		# to this image, so a preview shown here never ends up "stuck".
		_get_texture(nb_url)

		var preview_url := _resized_image_url(local_image_data[swipe_neighbour_index].image_url, SWIPE_PREVIEW_MAX_WIDTH)
		nb_texture = _texture_cache.get(preview_url, null)
		if nb_texture == null:
			_get_texture(preview_url)
			image_texture_next.texture = null
			image_texture_next.visible = false
			return

	var nb_size := nb_texture.get_size()
	var nb_zoom: float = min(vp.x / nb_size.x, usable_h / nb_size.y)
	var nb_display := nb_size * nb_zoom
	var nb_centered_y: float = (usable_h - nb_display.y) * 0.5

	image_texture_next.texture = nb_texture
	image_texture_next.size = nb_size
	image_texture_next.scale = Vector2.ONE * nb_zoom
	image_texture_next.position = Vector2(image_texture.position.x + vp.x * -direction, nb_centered_y)
	image_texture_next.visible = true


func _update_swipe(delta_x: float) -> void:
	if image_urls.size() <= 1:
		return
	if image_texture.texture == null:
		return
	var vp := get_viewport_rect().size
	var usable_h := _usable_height()

	if not is_swiping:
		is_swiping = true
		swipe_offset = 0.0
		_setup_neighbour(int(sign(delta_x)))

	swipe_offset += delta_x

	var expected_index := (current_image_index + 1) % image_urls.size() if swipe_offset < 0 else (current_image_index - 1 + image_urls.size()) % image_urls.size()
	if expected_index != swipe_neighbour_index:
		_setup_neighbour(int(sign(swipe_offset)))

	var cur_display := image_texture.texture.get_size() * zoom
	var cur_centered_x: float = (vp.x - cur_display.x) * 0.5
	var cur_centered_y: float = (usable_h - cur_display.y) * 0.5
	image_texture.position = Vector2(cur_centered_x + swipe_offset, cur_centered_y)

	if image_texture_next.texture == null:
		return  # neighbour still downloading - just move the current image for now

	var nb_tex_size := image_texture_next.texture.get_size()
	var nb_zoom: float = image_texture_next.scale.x
	var nb_display := nb_tex_size * nb_zoom
	var nb_centered_y: float = (usable_h - nb_display.y) * 0.5
	var swipe_sign: float = 1.0 if swipe_offset > 0 else -1.0
	image_texture_next.position = Vector2(cur_centered_x + swipe_offset + vp.x * -swipe_sign, nb_centered_y)


func _finish_swipe() -> void:
	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	is_swiping = false

	if image_texture_next.texture == null:
		# The neighbour hasn't finished downloading yet. If the user swiped
		# far enough to commit to switching, don't just abandon the swipe
		# and leave them stuck on the old image - fall back to a normal
		# animated transition, which waits for the download and then plays
		# the transition once it's ready.
		var committed: bool = abs(swipe_offset) >= vp.x * SWIPE_THRESHOLD
		var target_index := swipe_neighbour_index
		var direction: int = 1 if swipe_offset < 0 else -1

		var snap_back_display := image_texture.texture.get_size() * zoom
		image_texture.position = Vector2((vp.x - snap_back_display.x) * 0.5, (usable_h - snap_back_display.y) * 0.5)
		swipe_offset = 0.0
		image_texture_next.visible = false

		if committed:
			await _animate_transition(target_index, direction)
			current_image_index = target_index
			_update_image_text()
			_preload_neighbours()
		return

	is_animating = true

	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	var cur_display := image_texture.texture.get_size() * zoom
	var cur_centered_x: float = (vp.x - cur_display.x) * 0.5

	var nb_tex_size := image_texture_next.texture.get_size()
	var nb_zoom: float = image_texture_next.scale.x
	var nb_display := nb_tex_size * nb_zoom
	var nb_centered_x: float = (vp.x - nb_display.x) * 0.5

	var swipe_sign: float = 1.0 if swipe_offset > 0 else -1.0

	if abs(swipe_offset) >= vp.x * SWIPE_THRESHOLD:
		tween.tween_property(image_texture, "position:x", cur_centered_x + vp.x * swipe_sign, 0.25)
		tween.tween_property(image_texture_next, "position:x", nb_centered_x, 0.25)

		await tween.finished

		var committed_index := swipe_neighbour_index
		# Whatever was shown during the drag might have been a small
		# "quick preview" fallback (see _setup_neighbour) rather than the
		# standard resolution. Always resolve to the standard version
		# before actually committing - this is an instant cache hit if it
		# already finished downloading in the background, and only
		# genuinely waits if it hasn't, so committed images are never
		# left stuck at preview quality.
		var final_texture: Texture2D = await _get_texture(image_urls[committed_index])
		if final_texture == null:
			final_texture = image_texture_next.texture  # fall back to whatever we had rather than nothing

		current_image_index = committed_index
		var final_size := final_texture.get_size()
		var committed_zoom: float = min(vp.x / final_size.x, usable_h / final_size.y)
		zoom = committed_zoom
		min_zoom = committed_zoom
		var final_display := final_size * committed_zoom
		var final_centered_x: float = (vp.x - final_display.x) * 0.5
		var final_centered_y: float = (usable_h - final_display.y) * 0.5
		image_texture.texture = final_texture
		image_texture.size = final_size
		image_texture.scale = Vector2.ONE * zoom
		image_texture.position = Vector2(final_centered_x, final_centered_y)
		_clamp_position()
		_update_image_text()
		_preload_neighbours()
	else:
		tween.tween_property(image_texture, "position:x", cur_centered_x, 0.25)
		tween.tween_property(image_texture_next, "position:x", nb_centered_x + vp.x * -swipe_sign, 0.25)

		await tween.finished

	swipe_offset = 0.0
	image_texture_next.texture = null
	image_texture_next.visible = false
	is_animating = false


func _cancel_swipe() -> void:
	is_swiping = false
	swipe_offset = 0.0
	image_texture_next.texture = null
	image_texture_next.visible = false

	if image_texture.texture == null:
		return

	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	var cur_display := image_texture.texture.get_size() * zoom
	image_texture.position = Vector2((vp.x - cur_display.x) * 0.5, (usable_h - cur_display.y) * 0.5)


func _zoom_at_point(factor: float, center: Vector2) -> void:
	var new_zoom: float = clamp(zoom * factor, min_zoom, max_zoom)
	factor = new_zoom / zoom
	zoom = new_zoom

	image_texture.position = center + (image_texture.position - center) * factor
	image_texture.scale = Vector2.ONE * zoom

	_clamp_position()


func _clamp_position() -> void:
	if image_texture.texture == null:
		return

	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	var display_size := image_texture.texture.get_size() * zoom
	var pos := image_texture.position

	if display_size.x <= vp.x:
		pos.x = (vp.x - display_size.x) * 0.5
	else:
		pos.x = clamp(pos.x, vp.x - display_size.x, 0.0)

	if display_size.y <= usable_h:
		pos.y = (usable_h - display_size.y) * 0.5
	else:
		pos.y = clamp(pos.y, usable_h - display_size.y, 0.0)

	image_texture.position = pos


func _get_min_zoom() -> float:
	if image_texture.texture == null:
		return 1.0

	var texture_size := image_texture.texture.get_size()
	var vp := get_viewport_rect().size
	var usable_h := _usable_height()

	var scale_x := vp.x / texture_size.x
	var scale_y := usable_h / texture_size.y

	return min(scale_x, scale_y)


func _animate_transition(next_index: int, direction: int) -> void:
	is_animating = true

	var next_texture: Texture2D = await _get_texture(image_urls[next_index])
	if next_texture == null:
		is_animating = false
		return

	var vp := get_viewport_rect().size
	var usable_h := _usable_height()

	var next_texture_size := next_texture.get_size()
	var next_min_zoom: float = min(vp.x / next_texture_size.x, usable_h / next_texture_size.y)
	var next_zoom := next_min_zoom

	image_texture_next.texture = next_texture
	image_texture_next.size = next_texture_size
	image_texture_next.scale = Vector2.ONE * next_zoom
	image_texture_next.visible = true

	var next_display_size := next_texture_size * next_zoom
	var next_pos := Vector2(
		(vp.x - next_display_size.x) * 0.5,
		(usable_h - next_display_size.y) * 0.5
	)

	image_texture_next.position = Vector2(next_pos.x + vp.x * direction, next_pos.y)

	if tween:
		tween.kill()
	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	tween.tween_property(image_texture, "position:x", image_texture.position.x - vp.x * direction, 0.35)
	tween.tween_property(image_texture_next, "position:x", next_pos.x, 0.35)

	await tween.finished

	zoom = next_zoom
	min_zoom = next_min_zoom

	image_texture.texture = next_texture
	image_texture.size = next_texture_size
	image_texture.scale = Vector2.ONE * zoom
	image_texture.position = Vector2(next_pos.x, next_pos.y)
	_clamp_position()

	image_texture_next.texture = null
	image_texture_next.visible = false
	is_animating = false


func _on_viewport_size_changed() -> void:
	if image_texture.texture == null:
		return

	image_texture.size = image_texture.texture.get_size()

	min_zoom = _get_min_zoom()
	zoom = min_zoom
	image_texture.scale = Vector2.ONE * zoom

	var vp := get_viewport_rect().size
	var usable_h := _usable_height()
	var tex := image_texture.texture.get_size() * zoom
	image_texture.position = Vector2((vp.x - tex.x) * 0.5, (usable_h - tex.y) * 0.5)

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
	image_texture.position += start_velocity * t
	_clamp_position()


func _on_image_viewer_visibility_changed() -> void:
	if image_viewer.visible:
		show_image()
