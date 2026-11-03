extends Node
## Headless checks for LLM Toolkit Lite, against a scripted HTTP server in this process (no model
## needed). Run:
##   godot --headless --path . res://tests/test_lite.tscn
## tools/check_upgrade.py (in the repository) runs the same checks with the full LLM Toolkit's addon
## in place of Lite's, to show code written for Lite runs unchanged after an upgrade; Lite-only
## checks are skipped there.

const MockServer := preload("res://tests/mock_server.gd")

var failures := 0
var checks := 0
var server: MockServer
var full := false   # The full LLM Toolkit is installed in place of Lite.


func _ready() -> void:
	full = Llm.new().has_method("json")
	print("Testing the %s addon" % ("FULL" if full else "Lite"))
	var started := Time.get_ticks_msec()
	server = MockServer.new()
	add_child(server)
	server.start()
	await _test_streaming()
	await _test_inputs()
	await _test_errors()
	await _test_cancel_and_lifetime()
	print("\n%d checks, %d failed (%.1f s)" % [checks, failures, (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(1 if failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("ok    ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func _sse(pieces: Array, finish: String = "stop", done: bool = true) -> Array:
	var chunks := []
	for p in pieces:
		var delta: Dictionary = p if p is Dictionary else {"content": p}
		chunks.append("data: %s\n\n" % JSON.stringify({"model": "test-model", "choices": [{"index": 0, "delta": delta, "finish_reason": null}]}))
	if finish != "":
		chunks.append("data: %s\n\n" % JSON.stringify({"choices": [{"index": 0, "delta": {}, "finish_reason": finish}]}))
		chunks.append("data: %s\n\n" % JSON.stringify({"choices": [], "usage": {"prompt_tokens": 12, "completion_tokens": 7}}))
	if done:
		chunks.append("data: [DONE]\n\n")
	return chunks


func _llm() -> Llm:
	var llm := Llm.new(LlmProvider.lm_studio("", server.url("/v1")))
	if "retries" in llm:
		llm.set("retries", 0)   # The full toolkit retries by itself; these checks want one attempt.
	return llm


func _test_streaming() -> void:
	var event := "data: %s\n\n" % JSON.stringify({"choices": [{"index": 0, "delta": {"content": " Bienvenue ✓ — "}}]})
	var bytes := event.to_utf8_buffer()
	var cut := bytes.find(0xE2) + 1
	var chunks := [_sse([{"reasoning_content": "Thinking about rooms."}], "", false)[0], bytes.slice(0, cut), bytes.slice(cut)]
	chunks.append_array(_sse(["chambres à deux pièces."]))
	server.reset([{"status": 200, "chunks": chunks}])
	var llm := _llm()
	llm.system_prompt = "You keep the inn."
	var task := llm.chat("Bonjour")
	var pieces: Array[String] = []
	task.text_delta.connect(func(s): pieces.append(s))
	var r := await task.wait()
	ok(r.ok, "stream: ok (%s)" % r.error)
	ok(r.text == "Bienvenue ✓ — chambres à deux pièces.", "stream: UTF-8 split across packets, reasoning kept out, leading space trimmed (%s)" % r.text)
	ok("".join(pieces).strip_edges() == r.text and pieces.size() >= 2, "stream: text arrives in pieces")
	ok(r.model == "test-model" and int(r.usage.get("input_tokens", 0)) == 12 and int(r.usage.get("output_tokens", 0)) == 7, "stream: model and usage")
	ok(r.stop_reason == "stop" and r.seconds > 0.0, "stream: stop reason and timing")
	var sent: Dictionary = server.requests[0].json
	ok(server.requests[0].path == "/v1/chat/completions", "request: endpoint")
	ok(sent.stream == true and not sent.has("model"), "request: streams; no model field when none is set")
	ok(sent.messages[0] == {"role": "system", "content": "You keep the inn."} and sent.messages[1] == {"role": "user", "content": "Bonjour"}, "request: system prompt and message")
	ok(int(sent.max_tokens) == 4096, "request: max_tokens")
	ok(await task.wait() == r, "wait(): returns at once after completion")

	# A server that ignores "stream": true and sends pretty-printed JSON.
	server.reset([{"status": 200, "body": JSON.stringify({"model": "m", "choices": [{"message": {"content": "Plain reply."}, "finish_reason": "stop"}]}, "  ")}])
	var r2 := await _llm().ask("hi")
	ok(r2.ok and r2.text == "Plain reply.", "stream: a non-streamed answer still works (%s)" % r2.error)


func _test_inputs() -> void:
	server.reset([{"status": 200, "chunks": _sse(["ok"])}])
	var llm := _llm()
	llm.provider.model = "qwen3-8b"
	await llm.ask([{"role": "system", "content": "Be brief."}, {"role": "user", "content": "One"}, {"role": "assistant", "content": "Two"}, {"role": "user", "content": "Three"}], {"max_tokens": 64})
	var sent: Dictionary = server.requests[0].json
	ok(sent.model == "qwen3-8b" and int(sent.max_tokens) == 64, "inputs: model and max_tokens options")
	ok(sent.messages.size() == 4 and sent.messages[0].role == "system" and sent.messages[2].role == "assistant", "inputs: a message list with a system message")
	server.reset([{"status": 200, "chunks": _sse(["ok"])}])
	await llm.ask("Hi", {"system": "Override.", "model": "other"})
	ok(server.requests[0].json.messages[0].content == "Override." and server.requests[0].json.model == "other", "inputs: system and model options")
	var bad := await llm.ask([])
	ok(not bad.ok and bad.error.kind == LlmError.CONFIG, "inputs: nothing to send -> config error")


func _test_errors() -> void:
	var llm := _llm()
	server.reset([{"status": 400, "body": JSON.stringify({"error": {"message": "No models loaded. Please load a model.", "type": "invalid_request_error"}})}])
	var r := await llm.ask("hi")
	ok(not r.ok and r.error.kind == LlmError.CONFIG and r.error.message.begins_with("No models loaded") and r.error.http_status == 400, "errors: the server's message comes through (%s)" % r.error)
	server.reset([{"status": 401, "body": "{\"error\": \"Unauthorized\"}"}])
	var a := await llm.ask("hi")
	ok(not a.ok and a.error.kind == LlmError.AUTH, "errors: 401 -> auth")
	if not full:
		ok(a.error.message.contains("full LLM Toolkit"), "errors (Lite): says keys need the full version")
	server.reset([{"status": 500, "body": "<html>oops</html>"}, {"status": 500, "body": "<html>oops</html>"}, {"status": 500, "body": "<html>oops</html>"}])
	var s := await llm.ask("hi")
	ok(not s.ok and s.error.kind == LlmError.SERVER and s.error.is_transient(), "errors: 500 -> server, worth retrying")
	server.reset([{"status": 200, "chunks": _sse(["A long sto"], "length")}])
	var t := await llm.ask("story")
	ok(not t.ok and t.error.kind == LlmError.TRUNCATED and t.text == "A long sto", "errors: max_tokens -> truncated, partial text kept")
	server.reset([{"status": 200, "chunks": _sse(["Half a ", "reply"], "", false), "drop": true}])
	var d := await llm.ask("hi")
	ok(not d.ok and d.error.kind == LlmError.SERVER and d.text == "Half a reply", "errors: a dropped stream is an error, not a short reply")
	server.reset([{"status": 200, "chunks": _sse([""])}])
	ok((await llm.ask("hi")).error.kind == LlmError.EMPTY, "errors: no text -> empty")
	server.reset([{"hang_s": 3.0}])
	llm.idle_timeout_s = 0.5
	var started := Time.get_ticks_msec()
	var h := await llm.ask("hi")
	ok(not h.ok and h.error.kind == LlmError.TIMEOUT and Time.get_ticks_msec() - started < 2500, "errors: a silent server times out")
	var nobody := Llm.new(LlmProvider.lm_studio("", "http://127.0.0.1:1/v1"))
	if "retries" in nobody:
		nobody.set("retries", 0)
	started = Time.get_ticks_msec()
	var n := await nobody.ask("hi")
	ok(not n.ok and n.error.kind == LlmError.NETWORK and Time.get_ticks_msec() - started < 5000, "errors: nothing listening -> network error, quickly (%s)" % n.error)
	var u := await Llm.new(LlmProvider.lm_studio("", "not a url")).ask("hi")
	ok(not u.ok and u.error.kind == LlmError.CONFIG, "errors: a bad URL is a config error")


func _test_cancel_and_lifetime() -> void:
	var long := []
	for i in 40:
		long.append("word%d " % i)
	server.reset([{"status": 200, "chunks": _sse(long), "gap": 3}])
	var llm := _llm()
	var task := llm.chat("hi")
	await task.text_delta
	ok(llm.running() == 1, "cancel: one request running")
	task.cancel()
	var r := await task.wait()
	ok(not r.ok and r.error.kind == LlmError.CANCELLED and r.text.begins_with("word0"), "cancel: cancelled mid-stream, partial text kept")
	ok(llm.running() == 0, "cancel: nothing running after")

	server.reset([{"status": 200, "chunks": _sse(["Still here."])}])
	var one_liner := Llm.new(LlmProvider.lm_studio("", server.url("/v1"))).chat("hi")
	var r2 := await one_liner.wait()
	ok(r2.ok and r2.text == "Still here.", "lifetime: Llm.new(p).chat() finishes although nothing holds the Llm")

	server.reset([{"status": 200, "chunks": _sse(["a"])}, {"status": 200, "chunks": _sse(["b"])}])
	var both := _llm()
	var t1 := both.chat("1")
	var t2 := both.chat("2")
	both.cancel_all()
	ok((await t1.wait()).error.kind == LlmError.CANCELLED and (await t2.wait()).error.kind == LlmError.CANCELLED, "cancel_all: both cancelled")
	if not full:
		ok((Llm as GDScript).get("_noted") == true, "notice (Lite): the one-line note about the full version was printed")
