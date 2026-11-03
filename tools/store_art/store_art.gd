extends Node
## Composes the itch.io cover and screenshots for LLM Toolkit Lite. Not part of the addon; left out of
## the release zip.
##   godot --path . res://tools/store_art/store_art.tscn -- --out=<folder> --demo=<folder with demo_talk.png>
## Also writes the Asset Library icon and previews to assetlib/.

const NUNITO := preload("res://demo/fonts/Nunito-Variable.ttf")
const KNIGHT := preload("res://demo/images/knight.png")
const NIGHT := Color("#14162a")
const CARD := Color("#1e2140")
const FIELD := Color("#131528")
const LINE := Color("#323665")
const TEAL := Color("#2ec4b6")
const GOLD := Color("#f4b544")
const TEXT := Color("#ebe9f3")
const MUTED := Color(0.92, 0.91, 0.96, 0.62)
const CODE := Color("#cdcfe0")

var out := "user://store"
var demo := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--demo="):
			demo = a.trim_prefix("--demo=")
	DirAccess.make_dir_recursive_absolute(out)
	await _render(Vector2i(630, 500), _cover, "cover.png")
	await _render(Vector2i(1280, 720), _code_shot, "shot1_code.png")
	var shot := demo.path_join("demo_talk.png")
	if demo != "" and FileAccess.file_exists(shot):
		Image.load_from_file(shot).save_png(out.path_join("shot2_demo.png"))
	await _render(Vector2i(1280, 720), _compare_shot, "shot3_compare.png")
	await _render_icon(ProjectSettings.globalize_path("res://assetlib/icon.png"))
	for pair in [["shot1_code.png", "preview_code.png"], ["shot2_demo.png", "preview_demo.png"]]:
		var img := Image.load_from_file(out.path_join(pair[0])) if FileAccess.file_exists(out.path_join(pair[0])) else null
		if img != null:
			img.save_png(ProjectSettings.globalize_path("res://assetlib/" + pair[1]))
	print("store art written to ", out)
	get_tree().quit()


func _render(size: Vector2i, build: Callable, file: String) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Control.new()
	root.size = size
	vp.add_child(root)
	var bg := ColorRect.new()
	bg.color = NIGHT
	bg.size = size
	root.add_child(bg)
	build.call(root, Vector2(size))
	for i in 3:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out.path_join(file))
	vp.queue_free()


## The Asset Library icon: the addon's speech bubble, large, on a rounded night square, with a LITE tag.
func _render_icon(path: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.transparent_bg = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(512, 512)
	vp.add_child(root)
	var square := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = NIGHT
	box.border_color = LINE
	box.set_border_width_all(4)
	box.set_corner_radius_all(72)
	box.anti_aliasing = true
	square.add_theme_stylebox_override("panel", box)
	square.size = Vector2(512, 512)
	root.add_child(square)
	_glow(root, Vector2(256, 220), 240, Color(TEAL, 0.22))
	var svg := FileAccess.get_file_as_string("res://addons/llm_toolkit/icon.svg").replace("#e0e0e0", "#" + TEXT.to_html(false)).replace("#8da5f3", "#" + TEAL.to_html(false))
	var img := Image.new()
	img.load_svg_from_string(svg, 22.0)
	var bubble := TextureRect.new()
	bubble.texture = ImageTexture.create_from_image(img)
	bubble.position = Vector2(256 - img.get_width() / 2.0, 40)
	root.add_child(bubble)
	var tag := PanelContainer.new()
	var tag_box := StyleBoxFlat.new()
	tag_box.bg_color = GOLD
	tag_box.set_corner_radius_all(14)
	tag_box.content_margin_left = 26
	tag_box.content_margin_right = 26
	tag_box.content_margin_top = 4
	tag_box.content_margin_bottom = 8
	tag.add_theme_stylebox_override("panel", tag_box)
	var word := _label("LITE", 64, NIGHT, 900)
	tag.add_child(word)
	root.add_child(tag)
	await RenderingServer.frame_post_draw
	tag.position = Vector2(256 - tag.size.x / 2.0, 372)
	for i in 3:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	vp.get_texture().get_image().save_png(path)
	vp.queue_free()


# ------------------------------------------------------------------------------------------ pieces

func _cover(root: Control, size: Vector2) -> void:
	_glow(root, Vector2(470, 250), 320, Color(TEAL, 0.18))
	_text(root, "LLM Toolkit", Vector2(34, 70), 50, TEXT, 800)
	var tag := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = GOLD
	box.set_corner_radius_all(8)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 3
	box.content_margin_bottom = 4
	tag.add_theme_stylebox_override("panel", box)
	tag.position = Vector2(38, 138)
	tag.add_child(_label("LITE  ·  FREE", 17, NIGHT, 900))
	root.add_child(tag)
	_text(root, "for Godot 4", Vector2(186, 141), 20, TEAL, 700)
	var y := 206.0
	for line in ["Local models", "Replies stream in", "Pure GDScript", "Commercial use OK"]:
		_text(root, "✓", Vector2(36, y), 19, TEAL, 800)
		_text(root, line, Vector2(64, y), 19, TEXT, 600)
		y += 34.0
	_text(root, "LM Studio  ·  Ollama  ·  llama.cpp", Vector2(36, y + 8), 15, MUTED, 600)
	var knight := TextureRect.new()
	knight.texture = KNIGHT
	knight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knight.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	knight.position = Vector2(410, 200)
	knight.size = Vector2(200, 270)
	root.add_child(knight)
	var bubble := _bubble(root, "Sir Debugalot", "Welcome to the Rusty Flagon! The room by the hearth is free▌", Vector2(352, 58), 250)
	bubble.rotation_degrees = -3.0
	_text(root, "by Sir Debugalot  ·  ExcaliBug", Vector2(36, size.y - 46), 14, MUTED, 600)


func _code_shot(root: Control, size: Vector2) -> void:
	_glow(root, Vector2(1000, 400), 420, Color(TEAL, 0.14))
	_text(root, "Talk to a local model from GDScript.", Vector2(64, 52), 40, TEXT, 800)
	_text(root, "Replies stream in. The game never stops.", Vector2(64, 100), 40, TEAL, 800)
	var panel := _panel(root, Vector2(64, 196), Vector2(700, 0), CARD)
	var rich := _code_label(panel, 18, 9)
	var kw := "[color=#ff7085]%s[/color]"
	var ty := "[color=#8effda]%s[/color]"
	var fn := "[color=#66e6ff]%s[/color]"
	var cm := "[color=#7f84a8]%s[/color]"
	rich.text = "\n".join(PackedStringArray([
		"%s llm := %s.%s(%s.%s())" % [kw % "var", ty % "Llm", fn % "new", ty % "LlmProvider", fn % "lm_studio"],
		"llm.system_prompt = %s" % _s("\"You keep the inn.\""),
		"",
		"%s task := llm.%s(%s)" % [kw % "var", fn % "chat", _s("\"Any rooms free tonight?\"")],
		"task.text_delta.%s(%s(piece): speech.text += piece)" % [fn % "connect", kw % "func"],
		"%s result := %s task.%s()" % [kw % "var", kw % "await", fn % "wait"],
		"",
		"%s %s result.ok:" % [kw % "if", kw % "not"],
		"    %s(result.error.message)" % (fn % "print"),
		cm % "    # Cannot connect to 127.0.0.1:1234. Is the server running?",
	]))
	var knight := TextureRect.new()
	knight.texture = KNIGHT
	knight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knight.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	knight.position = Vector2(1000, 330)
	knight.size = Vector2(220, 340)
	root.add_child(knight)
	_bubble(root, "You", "Any rooms free tonight?", Vector2(830, 200), 360, true)
	_bubble(root, "Sir Debugalot", "The room by the hearth is free, two silver a night. The mattress was debugged only last▌", Vector2(800, 286), 300)


func _compare_shot(root: Control, size: Vector2) -> void:
	_glow(root, Vector2(900, 400), 460, Color(GOLD, 0.08))
	_text(root, "Lite, or the full LLM Toolkit?", Vector2(64, 46), 40, TEXT, 800)
	_text(root, "Same code: upgrading is replacing the addon folder.", Vector2(66, 100), 19, MUTED, 500)
	var rows := [
		["Streamed text, cancel, timeouts, clear errors", true],
		["LM Studio, Ollama, llama.cpp", true],
		["OpenAI, Claude, any server with an API key", false],
		["JSON with schemas: repaired, adjusted, checked", false],
		["Conversations that trim themselves", false],
		["Retries with backoff, a queue per server", false],
		["Thinking models: reasoning kept apart, effort", false],
		["Model lists, a mock provider for tests", false],
	]
	_text(root, "LITE  ·  FREE", Vector2(782, 160), 16, TEAL, 900)
	_text(root, "FULL  ·  $5", Vector2(1006, 160), 16, GOLD, 900)
	var y := 204.0
	for i in rows.size():
		if i % 2 == 0:
			var band := ColorRect.new()
			band.color = Color(CARD, 0.9)
			band.position = Vector2(48, y - 9)
			band.size = Vector2(1184, 50)
			root.add_child(band)
		_text(root, rows[i][0], Vector2(66, y), 20, TEXT, 600)
		_text(root, "✓" if rows[i][1] else "—", Vector2(826, y - 2), 22, TEAL if rows[i][1] else Color(MUTED, 0.4), 900)
		_text(root, "✓", Vector2(1042, y - 2), 22, GOLD, 900)
		y += 54.0


# ------------------------------------------------------------------------------------------ helpers

func _bubble(root: Control, who: String, text: String, at: Vector2, width: float, mine := false) -> PanelContainer:
	var bubble := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#26407a") if mine else Color("#2a2e57")
	box.set_corner_radius_all(14)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 11
	box.content_margin_bottom = 13
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 16
	box.shadow_offset = Vector2(0, 6)
	bubble.add_theme_stylebox_override("panel", box)
	bubble.position = at
	bubble.custom_minimum_size.x = width
	root.add_child(bubble)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	bubble.add_child(col)
	col.add_child(_label(who, 13, Color("#9ec3ff") if mine else TEAL, 800))
	var body := _label(text, 17, TEXT, 500)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = width - 32
	col.add_child(body)
	bubble.pivot_offset = Vector2(width * 0.5, 40)
	return bubble


func _panel(root: Control, at: Vector2, min_size: Vector2, fill: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = LINE
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", box)
	panel.position = at
	panel.custom_minimum_size = min_size
	panel.pivot_offset = min_size * 0.5
	root.add_child(panel)
	return panel


func _code_label(parent: Control, size: int, spacing: int) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.autowrap_mode = TextServer.AUTOWRAP_OFF
	rich.custom_minimum_size = Vector2(maxf(0.0, parent.custom_minimum_size.x - 44), 0)
	rich.add_theme_font_override("normal_font", _mono())
	rich.add_theme_font_size_override("normal_font_size", size)
	rich.add_theme_constant_override("line_separation", spacing)
	rich.add_theme_color_override("default_color", CODE)
	parent.add_child(rich)
	return rich


func _s(text: String) -> String:
	return "[color=#ffeda1]%s[/color]" % text.replace("[", "[lb]")


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _label(text: String, size: int, color: Color, weight := 500) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _text(root: Control, text: String, at: Vector2, size: int, color: Color, weight := 500) -> Label:
	var l := _label(text, size, color, weight)
	l.position = at
	root.add_child(l)
	return l


## A soft round glow behind the art.
func _glow(root: Control, center: Vector2, radius: float, color: Color) -> void:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.position = center - Vector2(radius, radius)
	r.size = Vector2(radius, radius) * 2.0
	root.add_child(r)


func _font(weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = NUNITO
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f


func _mono() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	return f
