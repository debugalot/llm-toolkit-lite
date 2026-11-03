extends RefCounted
## LLM Toolkit Lite's one request: POST /chat/completions with "stream": true on Godot's HTTPClient,
## polled once per frame so the game never stops. Server-sent events are split into lines on bytes,
## so a character cut between two network packets comes out whole.


## Returns {ok, error, text, model, stop_reason, usage}.
static func send(base_url: String, body: Dictionary, task: LlmTask, timeout_s: float, idle_timeout_s: float) -> Dictionary:
	var out := {"ok": false, "error": null, "text": "", "model": "", "stop_reason": "", "usage": {}}
	var url := base_url.strip_edges().trim_suffix("/") + "/chat/completions"
	var m := RegEx.create_from_string("^(https?)://([^/:?#]+)(?::(\\d+))?(/[^#]*)?").search(url)
	if m == null:
		return _fail(out, LlmError.CONFIG, "Not a valid http(s) URL: \"%s\"" % base_url)
	var tls := m.get_string(1) == "https"
	var host := m.get_string(2)
	var port := m.get_string(3).to_int() if m.get_string(3) != "" else (443 if tls else 80)
	var path := m.get_string(4)
	if host == "localhost":
		host = "127.0.0.1"   # Godot tries ::1 first; local servers listen on IPv4.
	var tree := Engine.get_main_loop() as SceneTree
	var http := HTTPClient.new()
	if http.connect_to_host(host, port, TLSOptions.client() if tls else null) != OK:
		return _fail(out, LlmError.NETWORK, "Could not start a connection to %s" % host)
	var start := Time.get_ticks_msec()
	var connect_ms := 3000 if host.begins_with("127.") else 15000

	while http.get_status() != HTTPClient.STATUS_CONNECTED:
		http.poll()
		var st := http.get_status()
		if st in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR, HTTPClient.STATUS_DISCONNECTED] \
				or Time.get_ticks_msec() - start > connect_ms:
			http.close()
			return _fail(out, LlmError.NETWORK, "Cannot connect to %s:%d. Is the server running?" % [host, port])
		if task.is_cancelled():
			http.close()
			return _fail(out, LlmError.CANCELLED, "Cancelled")
		if st != HTTPClient.STATUS_CONNECTED:
			await tree.process_frame

	if http.request(HTTPClient.METHOD_POST, path, PackedStringArray(["Content-Type: application/json", "Accept: text/event-stream"]), JSON.stringify(body)) != OK:
		http.close()
		return _fail(out, LlmError.NETWORK, "The request could not be sent")
	var last := Time.get_ticks_msec()
	var status := 0
	var buf := PackedByteArray()
	var raw := PackedByteArray()   # Kept until the first event, for servers that ignore streaming.
	var error_body := PackedByteArray()
	var finished := false
	var saw_event := false

	while true:
		http.poll()
		var st := http.get_status()
		if st == HTTPClient.STATUS_BODY:
			if status == 0:
				status = http.get_response_code()
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				last = Time.get_ticks_msec()
				if status >= 300:
					error_body.append_array(chunk)
				else:
					if not saw_event and raw.size() < 4 * 1024 * 1024:
						raw.append_array(chunk)
					buf.append_array(chunk)
					var nl := buf.find(10)
					while nl >= 0:
						var line := buf.slice(0, nl).get_string_from_utf8().strip_edges()
						buf = buf.slice(nl + 1)
						if line.begins_with("data:"):
							saw_event = true
							finished = _event(line.substr(5).strip_edges(), out, task) or finished
						nl = buf.find(10)
				continue
		elif st != HTTPClient.STATUS_REQUESTING:
			if status == 0 and http.has_response():
				status = http.get_response_code()
			break
		var now := Time.get_ticks_msec()
		if task.is_cancelled():
			http.close()
			return _fail(out, LlmError.CANCELLED, "Cancelled")
		if now - last > idle_timeout_s * 1000.0:
			http.close()
			return _fail(out, LlmError.TIMEOUT, "The server did not answer for %d s" % int(idle_timeout_s))
		if now - start > timeout_s * 1000.0:
			http.close()
			return _fail(out, LlmError.TIMEOUT, "The reply took longer than %d s" % int(timeout_s))
		await tree.process_frame
	http.close()
	var tail := buf.get_string_from_utf8().strip_edges()
	if tail.begins_with("data:"):
		saw_event = true
		finished = _event(tail.substr(5).strip_edges(), out, task) or finished
	if not saw_event and status > 0 and status < 300 and raw.size() > 0:
		_event(raw.get_string_from_utf8(), out, task)   # A server that ignored "stream": true.
		finished = true

	if status == 0:
		return _fail(out, LlmError.NETWORK, "The connection closed without a response")
	if status >= 300:
		var j := JSON.new()
		var message := error_body.get_string_from_utf8().strip_edges().left(300)
		if j.parse(message) == OK and j.data is Dictionary:
			var err: Variant = j.data.get("error")
			message = str(err.get("message", message)) if err is Dictionary else (str(err) if err != null else message)
		var kind := LlmError.SERVER if status >= 500 else (LlmError.AUTH if status in [401, 403] else LlmError.CONFIG)
		if kind == LlmError.AUTH:
			message += " (This server wants an API key. Keys need the full LLM Toolkit.)"
		return _fail(out, kind, message, status)
	if out.stop_reason == "length":
		return _fail(out, LlmError.TRUNCATED, "The reply hit the token limit (max_tokens)")
	if not finished:
		return _fail(out, LlmError.SERVER, "The connection dropped before the reply finished")
	if out.text.strip_edges() == "":
		return _fail(out, LlmError.EMPTY, "The model returned no text")
	out.text = out.text.strip_edges()
	out.ok = true
	return out


## One "data:" payload. Returns true when it ends the reply.
static func _event(payload: String, out: Dictionary, task: LlmTask) -> bool:
	if payload == "[DONE]":
		return true
	var j := JSON.new()
	if j.parse(payload) != OK or not (j.data is Dictionary):
		return false
	var data: Dictionary = j.data
	if data.get("model") is String:
		out.model = data.model
	if data.get("usage") is Dictionary:
		out.usage = {"input_tokens": int(data.usage.get("prompt_tokens", 0)), "output_tokens": int(data.usage.get("completion_tokens", 0))}
	var choices: Variant = data.get("choices")
	if not (choices is Array) or choices.is_empty():
		return false
	var delta: Variant = choices[0].get("delta", choices[0].get("message", {}))
	if delta is Dictionary and delta.get("content") is String:
		var piece: String = delta.content
		if out.text == "":
			piece = piece.strip_edges(true, false)
		out.text += piece
		task._emit_text(piece)
	if choices[0].get("finish_reason") is String:
		out.stop_reason = choices[0].finish_reason
		return true
	return false


static func _fail(out: Dictionary, kind: StringName, message: String, status: int = 0) -> Dictionary:
	out.ok = false
	out.error = LlmError.make(kind, message, status)
	return out
