extends Node
## A scripted HTTP/1.1 server for the tests, on 127.0.0.1. Each request takes the next response from
## `responses`:
##   {status, headers: {}, body: String}                       a plain response
##   {status, chunks: [String or PackedByteArray], gap: frames}  a chunked (streamed) response
##   {hang_s: seconds}                                         accept the request, never answer
##   {chunks: [...], drop: true}                               stream, then cut the connection
## Every request is recorded in `requests` as {method, path, headers (lower-case keys), body, json}.

var port := 0
var responses: Array = []
var requests: Array[Dictionary] = []
var _server := TCPServer.new()
var _conns: Array = []


func start() -> int:
	for p in range(18911, 19011):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			return p
	push_error("mock server: no free port")
	return 0


func url(path: String = "") -> String:
	return "http://127.0.0.1:%d%s" % [port, path]


func reset(new_responses: Array) -> void:
	responses = new_responses
	requests.clear()


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		_conns.append({"peer": _server.take_connection(), "buf": PackedByteArray(), "busy": false})
	for c in _conns.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.erase(c)
			continue
		if c.busy:
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got := peer.get_data(n)
			if got[0] == OK:
				var grown: PackedByteArray = c.buf
				grown.append_array(got[1])
				c.buf = grown
		var req := _parse(c.buf)
		if req.is_empty():
			continue
		c.busy = true
		requests.append(req)
		var spec: Dictionary = responses.pop_front() if not responses.is_empty() else {"status": 500, "body": "{\"error\": \"no scripted response\"}"}
		_respond(c, spec)


func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var end := text.find("\r\n\r\n")
	if end < 0:
		return {}
	var lines := text.left(end).split("\r\n")
	var first := lines[0].split(" ")
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].left(colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var head_bytes := text.left(end + 4).to_utf8_buffer().size()
	var length := int(headers.get("content-length", "0"))
	if buf.size() < head_bytes + length:
		return {}
	var body := buf.slice(head_bytes, head_bytes + length).get_string_from_utf8()
	var j := JSON.new()
	return {"method": first[0], "path": first[1] if first.size() > 1 else "/", "headers": headers, "body": body, "json": j.data if j.parse(body) == OK else null}


func _respond(c: Dictionary, spec: Dictionary) -> void:
	var peer: StreamPeerTCP = c.peer
	if spec.has("hang_s"):
		await get_tree().create_timer(float(spec.hang_s)).timeout
		peer.disconnect_from_host()
		_conns.erase(c)
		return
	var status := int(spec.get("status", 200))
	var head := "HTTP/1.1 %d %s\r\n" % [status, "OK" if status < 300 else "Error"]
	var headers: Dictionary = spec.get("headers", {})
	if not headers.has("Content-Type"):
		head += "Content-Type: %s\r\n" % ("text/event-stream" if spec.has("chunks") else "application/json")
	for k in headers:
		head += "%s: %s\r\n" % [k, headers[k]]
	if spec.has("chunks"):
		head += "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
		peer.put_data(head.to_utf8_buffer())
		for chunk in spec.chunks:
			for i in int(spec.get("gap", 1)):
				await get_tree().process_frame
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_conns.erase(c)
				return
			var bytes: PackedByteArray = chunk if chunk is PackedByteArray else str(chunk).to_utf8_buffer()
			var framed := ("%x\r\n" % bytes.size()).to_utf8_buffer()
			framed.append_array(bytes)
			framed.append_array("\r\n".to_utf8_buffer())
			peer.put_data(framed)
		await get_tree().process_frame
		if not spec.get("drop", false):
			peer.put_data("0\r\n\r\n".to_utf8_buffer())
		await get_tree().process_frame
		peer.disconnect_from_host()
	else:
		var body := str(spec.get("body", "")).to_utf8_buffer()
		head += "Content-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
		var out := head.to_utf8_buffer()
		out.append_array(body)
		peer.put_data(out)
		await get_tree().process_frame
		peer.disconnect_from_host()
	_conns.erase(c)
