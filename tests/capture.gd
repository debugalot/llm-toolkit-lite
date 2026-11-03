extends Node
## Windowed: plays the demo against tests/mock_server.gd (scripted, streamed replies) and saves a
## screenshot mid-reply.
##   godot --path . res://tests/capture.tscn -- --out=<folder> [--live]
## --live talks to LM Studio on this machine instead and saves demo_talk_live.png.

const MockServer := preload("res://tests/mock_server.gd")
const REPLIES := [
	"The room by the hearth is free, two silver a night, breakfast included. The mattress was debugged only last week, so you'll sleep with nothing crawling about.",
	"Strange lights in the Dark Wood again, they say. Last fellow who went looking came back speaking only in error codes.",
	"One Flagon Amber, coming up. It's brewed in the cellar, and I promise every bug in that barrel was a feature.",
]


func _ready() -> void:
	var out := "user://"
	var live := OS.get_cmdline_user_args().has("--live")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var demo: Control = load("res://demo/demo.tscn").instantiate()
	var saved := FileAccess.get_file_as_bytes(demo.SETTINGS)   # The demo saves its fields; put them back after.
	if not live:
		var server := MockServer.new()
		add_child(server)
		server.start()
		var scripted := []
		for reply in REPLIES:
			scripted.append({"status": 200, "chunks": _stream(reply), "gap": 2})
		server.reset(scripted)
		add_child(demo)
		demo._url.text = server.url("/v1")
		demo._model.text = "qwen3-8b"
		demo._rebuild_provider()   # Setting text from code sends no text_changed.
		demo._url.text = demo.SERVERS[0].url   # Show LM Studio's address; requests still go to the mock.
	else:
		add_child(demo)
		demo._server.selected = 0
		demo._apply_server(true)
	await get_tree().create_timer(0.5).timeout
	for line in ["Any rooms free tonight?", "Heard any rumours lately?"]:
		demo._entry.text = line
		demo._say()
		var r: LlmResult = await demo._task.wait()
		if not r.ok:
			print("capture stopped: ", r.error)   # e.g. LM Studio has no model loaded
			_restore_settings(demo.SETTINGS, saved)
			get_tree().quit(1)
			return
		await get_tree().create_timer(0.3).timeout
	demo._entry.text = "What's in the ale?"
	demo._say()
	while demo._task.text.length() < 40 and not demo._task.is_done():   # mid-reply, to show the streaming cursor
		await get_tree().process_frame
	await _shot(out.path_join("demo_talk%s.png" % ("_live" if live else "")))
	await demo._task.wait()
	_restore_settings(demo.SETTINGS, saved)
	get_tree().quit()


## An OpenAI-style stream of `text`, a word at a time, as LM Studio sends it.
func _stream(text: String) -> Array:
	var chunks := []
	var words := text.split(" ")
	for i in words.size():
		var piece := (" " if i > 0 else "") + words[i]
		chunks.append("data: %s\n\n" % JSON.stringify({"model": "qwen3-8b", "choices": [{"index": 0, "delta": {"content": piece}, "finish_reason": null}]}))
	chunks.append("data: %s\n\n" % JSON.stringify({"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}))
	chunks.append("data: %s\n\n" % JSON.stringify({"choices": [], "usage": {"prompt_tokens": 96, "completion_tokens": words.size() * 4 / 3}}))
	chunks.append("data: [DONE]\n\n")
	return chunks


func _restore_settings(path: String, saved: PackedByteArray) -> void:
	if saved.is_empty():
		DirAccess.remove_absolute(path)
	else:
		FileAccess.open(path, FileAccess.WRITE).store_buffer(saved)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
