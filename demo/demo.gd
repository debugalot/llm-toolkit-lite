extends Control
## LLM Toolkit Lite demo: talk to the innkeeper of the Rusty Flagon through a model running on this
## machine (LM Studio, Ollama or llama.cpp). Replies stream in; the conversation is a plain Array of
## messages sent with each request.

const KNIGHT := preload("res://demo/images/knight.png")
const NUNITO := preload("res://demo/fonts/Nunito-Variable.ttf")

const BG := Color("#14162a")
const CARD := Color("#1e2140")
const FIELD := Color("#131528")
const LINE := Color("#323665")
const TEXT := Color("#ebe9f3")
const MUTED := Color(0.92, 0.91, 0.96, 0.58)
const TEAL := Color("#2ec4b6")
const GOLD := Color("#f4b544")
const RED := Color("#ff6b6b")
const SETTINGS := "user://llm_toolkit_lite_demo.cfg"
const FULL_URL := "https://debugalot.itch.io/llm-toolkit"

const INNKEEPER := "You are Sir Debugalot, a retired knight who now keeps the Rusty Flagon, an inn at the edge of the Dark Wood. Speak in character: warm, a little gruff, fond of bad puns about bugs. Answer in two or three sentences. Never mention being an AI."
const SERVERS := [
	{"name": "LM Studio", "url": "http://127.0.0.1:1234/v1", "hint": "the loaded model"},
	{"name": "Ollama", "url": "http://127.0.0.1:11434/v1", "hint": "e.g. llama3.2"},
	{"name": "llama.cpp", "url": "http://127.0.0.1:8080/v1", "hint": "the server's model"},
]
const FULL_FEATURES := [
	"JSON with schemas: repaired, adjusted and checked",
	"OpenAI, Claude and keyed servers",
	"Conversations that trim themselves",
	"Retries, queueing, thinking settings",
	"A mock provider for tests",
]

var llm := Llm.new()
var history: Array[Dictionary] = []   # {"role": "user" or "assistant", "content": ...}

var _server: OptionButton
var _url: LineEdit
var _model: LineEdit
var _stats: Label
var _chat_scroll: ScrollContainer
var _chat: VBoxContainer
var _entry: LineEdit
var _send: Button
var _stop: Button
var _task: LlmTask


func _ready() -> void:
	theme = _make_theme()
	llm.system_prompt = INNKEEPER
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)

	var header := HBoxContainer.new()
	page.add_child(header)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("The Rusty Flagon", 26, TEXT, 900))
	titles.add_child(_label("Talk to the innkeeper through a model running on this machine.", 14, MUTED))
	var badge := _label("LLM Toolkit Lite  ·  v%s" % Llm.VERSION, 13, TEAL, 800)
	badge.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(badge)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	page.add_child(body)
	_build_side(body)
	_build_talk(body)

	_load_settings()
	_apply_server(false)
	_greet()


# ------------------------------------------------------------------------------------------ side

func _build_side(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 320
	col.add_theme_constant_override("separation", 12)
	parent.add_child(col)
	var card := _card(col, "Server")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	card.add_child(grid)
	_server = OptionButton.new()
	for s in SERVERS:
		_server.add_item(s.name)
	_server.item_selected.connect(func(_i): _apply_server(true))
	_row(grid, "Server", _server)
	_url = LineEdit.new()
	_url.text_changed.connect(func(_t): _rebuild_provider())
	_row(grid, "URL", _url)
	_model = LineEdit.new()
	_model.text_changed.connect(func(_t): _rebuild_provider())
	_row(grid, "Model", _model)
	_stats = _label("Start the server, load a model, then say hello.", 13, MUTED)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(_stats)

	var full := _card(col, "The full LLM Toolkit adds")
	for f in FULL_FEATURES:
		var line := _label("◆  " + f, 14, TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		full.add_child(line)
	var get_it := Button.new()
	get_it.text = "Get LLM Toolkit  ·  $5"
	get_it.theme_type_variation = "GoldButton"
	get_it.pressed.connect(func(): OS.shell_open(FULL_URL))
	full.add_child(get_it)
	full.add_child(_label("Same code: upgrading is replacing the folder.", 12, MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(spacer)


func _apply_server(user_changed: bool) -> void:
	var s: Dictionary = SERVERS[_server.selected]
	if user_changed:
		_url.text = s.url
		_model.text = ""
	_model.placeholder_text = s.hint
	_rebuild_provider()


func _rebuild_provider() -> void:
	llm.cancel_all()
	llm.provider = LlmProvider.new()
	llm.provider.base_url = _url.text.strip_edges()
	llm.provider.model = _model.text.strip_edges()
	_save_settings()


# ------------------------------------------------------------------------------------------ talk

func _build_talk(parent: Control) -> void:
	var talk := HBoxContainer.new()
	talk.size_flags_horizontal = SIZE_EXPAND_FILL
	talk.add_theme_constant_override("separation", 14)
	parent.add_child(talk)
	var portrait_card := PanelContainer.new()
	portrait_card.custom_minimum_size.x = 180
	talk.add_child(portrait_card)
	var pcol := VBoxContainer.new()
	pcol.alignment = BoxContainer.ALIGNMENT_CENTER
	portrait_card.add_child(pcol)
	var knight := TextureRect.new()
	knight.texture = KNIGHT
	knight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knight.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	knight.custom_minimum_size = Vector2(150, 230)
	pcol.add_child(knight)
	var nm := _label("Sir Debugalot", 17, TEXT, 900)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcol.add_child(nm)
	var role := _label("Keeper of the Rusty Flagon", 12, MUTED)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pcol.add_child(role)
	var new_chat := Button.new()
	new_chat.text = "New conversation"
	new_chat.pressed.connect(_new_conversation)
	pcol.add_child(new_chat)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	talk.add_child(right)
	var log_card := PanelContainer.new()
	log_card.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(log_card)
	_chat_scroll = ScrollContainer.new()
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_card.add_child(_chat_scroll)
	_chat = VBoxContainer.new()
	_chat.size_flags_horizontal = SIZE_EXPAND_FILL
	_chat.add_theme_constant_override("separation", 10)
	_chat_scroll.add_child(_chat)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	right.add_child(bar)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Say something to the innkeeper…"
	_entry.size_flags_horizontal = SIZE_EXPAND_FILL
	_entry.text_submitted.connect(func(_t): _say())
	bar.add_child(_entry)
	_send = Button.new()
	_send.text = "Send"
	_send.theme_type_variation = "PrimaryButton"
	_send.custom_minimum_size.x = 90
	_send.pressed.connect(_say)
	bar.add_child(_send)
	_stop = Button.new()
	_stop.text = "Stop"
	_stop.disabled = true
	_stop.pressed.connect(func(): if _task: _task.cancel())
	bar.add_child(_stop)


func _greet() -> void:
	_bubble("Sir Debugalot", "Welcome to the Rusty Flagon, traveller! Pull up a stool. Ask about rooms, ale, or the rumours from the Dark Wood.", false)


func _new_conversation() -> void:
	if _task:
		_task.cancel()
	history.clear()
	for c in _chat.get_children():
		c.queue_free()
	_greet()


func _say() -> void:
	var text := _entry.text.strip_edges()
	if text == "" or (_task and not _task.is_done()):
		return
	_entry.clear()
	_bubble("You", text, true)
	history.append({"role": "user", "content": text})
	var reply := _bubble("Sir Debugalot", "▌", false)
	var label: Label = reply.get_meta("text")
	var note: Label = reply.get_meta("note")
	_busy(true)
	# The last 20 messages are plenty for an innkeeper, and keep the prompt short.
	_task = llm.chat(history.slice(-20), {"max_tokens": 1024})
	_task.text_delta.connect(func(_piece): label.text = _task.text.strip_edges(true, false) + "▌"; _scroll_down())
	var r := await _task.wait()
	if r.ok:
		label.text = r.text
		history.append({"role": "assistant", "content": r.text})
	else:
		history.pop_back()   # Unanswered: leave it out of the next request.
		if r.error.kind == LlmError.CANCELLED:
			label.text = (r.text + " …") if r.text != "" else "(stopped)"
		else:
			label.text = r.text if r.text != "" else "…"
			note.visible = true
			note.text = "✕  " + r.error.message
			note.modulate = RED
	_show_stats(r)
	_busy(false)
	_scroll_down()


func _bubble(who: String, text: String, mine: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", _box(Color("#26407a") if mine else Color("#2a2e57"), Color.TRANSPARENT, 12, Vector4(14, 10, 14, 11)))
	bubble.custom_minimum_size.x = 120
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	bubble.add_child(col)
	col.add_child(_label(who, 12, TEAL if not mine else Color("#9ec3ff"), 800))
	var body := _label(text, 15, TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 120
	col.add_child(body)
	var note := _label("", 12, MUTED)
	note.visible = false
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	row.add_child(bubble)
	_chat.add_child(row)
	bubble.set_meta("text", body)
	bubble.set_meta("note", note)
	# Bubbles grow with their text up to most of the width.
	var fit := func() -> void:
		var max_w := maxf(200.0, _chat.size.x * 0.78)
		var font := body.get_theme_font("font")
		var w := font.get_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 30.0
		bubble.custom_minimum_size.x = clampf(w, 140.0, max_w)
	body.resized.connect(fit)
	fit.call()
	body.draw.connect(fit)
	_scroll_down()
	return bubble


func _scroll_down() -> void:
	await get_tree().process_frame
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _busy(on: bool) -> void:
	_send.disabled = on
	_stop.disabled = not on


func _show_stats(r: LlmResult) -> void:
	var lines := PackedStringArray()
	lines.append(("✓ " if r.ok else "✕ ") + (r.model if r.model != "" else llm.provider.describe()))
	lines.append("%.1f s" % r.seconds + ("  ·  %.0f tokens/s" % r.tokens_per_second() if r.tokens_per_second() > 0.0 else ""))
	if r.usage.has("input_tokens"):
		lines.append("%d tokens in, %d out" % [int(r.usage.get("input_tokens", 0)), int(r.usage.get("output_tokens", 0))])
	_stats.text = "\n".join(lines)
	_stats.add_theme_color_override("font_color", MUTED if r.ok else RED)


# ------------------------------------------------------------------------------------------ settings

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("demo", "server", _server.selected)
	cfg.set_value("demo", "url", _url.text)
	cfg.set_value("demo", "model", _model.text)
	cfg.save(SETTINGS)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) != OK:
		_server.selected = 0
		_url.text = SERVERS[0].url
		return
	_server.selected = clampi(int(cfg.get_value("demo", "server", 0)), 0, SERVERS.size() - 1)
	_url.text = str(cfg.get_value("demo", "url", SERVERS[_server.selected].url))
	_model.text = str(cfg.get_value("demo", "model", ""))


# ------------------------------------------------------------------------------------------ look

func _card(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(_label(title.to_upper(), 12, TEAL, 800))
	return col


func _row(grid: GridContainer, text: String, control: Control) -> void:
	grid.add_child(_label(text, 14, MUTED))
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(control)


func _label(text: String, size: int, color: Color, weight: int = 500) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _ui_font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _ui_font(weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = NUNITO
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return f


static func _box(fill: Color, border: Color, radius: int, pad := Vector4.ZERO, width := 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = border
	b.set_border_width_all(width if border.a > 0.0 else 0)
	b.set_corner_radius_all(radius)
	b.content_margin_left = pad.x
	b.content_margin_top = pad.y
	b.content_margin_right = pad.z
	b.content_margin_bottom = pad.w
	b.anti_aliasing = true
	return b


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _ui_font(500)
	t.default_font_size = 15
	for type in ["Label", "Button", "OptionButton", "LineEdit", "PopupMenu"]:
		t.set_color("font_color", type, TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(CARD, LINE, 12, Vector4(18, 16, 18, 16)))
	t.set_stylebox("normal", "LineEdit", _box(FIELD, LINE, 7, Vector4(10, 7, 10, 7)))
	t.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, TEAL, 7, Vector4(10, 7, 10, 7), 2))
	t.set_color("caret_color", "LineEdit", TEAL)
	t.set_color("selection_color", "LineEdit", Color(TEAL, 0.3))
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(Color("#2a2e57"), LINE, 7, Vector4(12, 6, 12, 6)))
		t.set_stylebox("hover", type, _box(Color("#343a6d"), Color(TEAL, 0.6), 7, Vector4(12, 6, 12, 6)))
		t.set_stylebox("pressed", type, _box(Color("#22264a"), TEAL, 7, Vector4(12, 6, 12, 6)))
		t.set_stylebox("disabled", type, _box(Color("#20234a"), LINE, 7, Vector4(12, 6, 12, 6)))
		t.set_stylebox("focus", type, _box(Color.TRANSPARENT, TEAL, 7, Vector4(12, 6, 12, 6), 2))
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, TEAL)
		t.set_color("font_disabled_color", type, Color(TEXT, 0.35))
	for variant in [["PrimaryButton", TEAL], ["GoldButton", GOLD]]:
		var v: String = variant[0]
		var c: Color = variant[1]
		t.set_type_variation(v, "Button")
		t.set_stylebox("normal", v, _box(c, Color.TRANSPARENT, 9, Vector4(14, 6, 14, 6)))
		t.set_stylebox("hover", v, _box(c.lightened(0.15), Color.TRANSPARENT, 9, Vector4(14, 6, 14, 6)))
		t.set_stylebox("pressed", v, _box(c.darkened(0.15), Color.TRANSPARENT, 9, Vector4(14, 6, 14, 6)))
		t.set_stylebox("disabled", v, _box(Color(c, 0.35), Color.TRANSPARENT, 9, Vector4(14, 6, 14, 6)))
		t.set_stylebox("focus", v, _box(Color.TRANSPARENT, Color.WHITE, 9, Vector4(14, 6, 14, 6), 2))
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			t.set_color(k, v, BG)
		t.set_font("font", v, _ui_font(800))
		t.set_font_size("font_size", v, 16)
	t.set_stylebox("panel", "PopupMenu", _box(Color("#24284c"), LINE, 8, Vector4(6, 6, 6, 6)))
	t.set_stylebox("hover", "PopupMenu", _box(Color(TEAL, 0.22), Color.TRANSPARENT, 5))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "ScrollContainer", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	t.set_stylebox("scroll", "VScrollBar", _box(Color.TRANSPARENT, Color.TRANSPARENT, 4, Vector4(4, 0, 0, 0)))
	t.set_stylebox("grabber", "VScrollBar", _box(Color(LINE, 0.9), Color.TRANSPARENT, 4, Vector4(4, 0, 0, 0)))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(TEAL, 0.5), Color.TRANSPARENT, 4, Vector4(4, 0, 0, 0)))
	t.set_stylebox("grabber_pressed", "VScrollBar", _box(TEAL, Color.TRANSPARENT, 4, Vector4(4, 0, 0, 0)))
	return t
