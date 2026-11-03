class_name Llm
extends RefCounted
## LLM Toolkit Lite: chat with a local model (LM Studio, Ollama or llama.cpp) from GDScript. Replies
## stream in without blocking the game.
##
##   var llm := Llm.new(LlmProvider.lm_studio())
##   var task := llm.chat("You are the innkeeper. Greet a tired traveller.")
##   task.text_delta.connect(func(piece): label.text += piece)
##   var result := await task.wait()
##
## The full LLM Toolkit runs the same code and adds JSON with schemas (repaired, adjusted and
## validated), OpenAI, Claude and keyed servers, conversations, retries and queueing, settings for
## thinking models, and a mock provider for tests: https://debugalot.itch.io/llm-toolkit

const VERSION := "1.0.0"
const _UPGRADE_URL := "https://debugalot.itch.io/llm-toolkit"

const Stream := preload("res://addons/llm_toolkit/internal/llm_lite_stream.gd")

## Where requests go.
var provider: LlmProvider
## The system prompt for requests that do not bring their own (the "system" option).
var system_prompt := ""
## The most tokens a reply may use.
var max_tokens := 4096
## The longest a whole request may take, in seconds.
var timeout_s := 600.0
## The longest the server may stay silent, in seconds, including while it loads a model.
var idle_timeout_s := 120.0

var _running: Array[LlmTask] = []
static var _alive := {}
static var _noted := false


func _init(provider_: LlmProvider = null) -> void:
	provider = provider_ if provider_ != null else LlmProvider.lm_studio()


## Starts a request and returns its task. `input` is a prompt String, or an Array of
## {"role", "content"} messages ("system", "user" or "assistant"). Options for one request: system,
## model, max_tokens.
func chat(input: Variant, options: Dictionary = {}) -> LlmTask:
	var task := LlmTask.new()
	_running.append(task)
	_alive[get_instance_id()] = self   # Keeps `Llm.new(p).chat(...)` alive until it finishes.
	_run(task, input, options)
	return task


## chat(), waiting for the result.
func ask(input: Variant, options: Dictionary = {}) -> LlmResult:
	return await chat(input, options).wait()


## Cancels every request this object started that has not finished.
func cancel_all() -> void:
	for t in _running:
		t.cancel()


## Requests in flight.
func running() -> int:
	return _running.size()


func _run(task: LlmTask, input: Variant, options: Dictionary) -> void:
	# One frame first, so signals connected right after chat() returns never miss anything.
	await (Engine.get_main_loop() as SceneTree).process_frame
	if not _noted:
		_noted = true
		print("LLM Toolkit Lite %s: local models, plain text. The full LLM Toolkit adds JSON with schemas, OpenAI and Claude, conversations and retries: %s" % [VERSION, _UPGRADE_URL])
	var r := LlmResult.new()
	var messages := []
	var system := str(options.get("system", system_prompt))
	if input is String or input is StringName:
		messages.append({"role": "user", "content": str(input)})
	elif input is Array:
		for m in input:
			if m is Dictionary and m.has("content"):
				var role := str(m.get("role", "user"))
				if role == "system":
					if not options.has("system"):
						system = str(m.content)
				else:
					messages.append({"role": "assistant" if role == "assistant" else "user", "content": str(m.content)})
			elif m is String:
				messages.append({"role": "user", "content": m})
	if messages.is_empty():
		r.error = LlmError.make(LlmError.CONFIG, "There is nothing to send: give chat() a prompt or a list of messages")
	elif provider == null:
		r.error = LlmError.make(LlmError.CONFIG, "No provider set")
	else:
		if system != "":
			messages.push_front({"role": "system", "content": system})
		var body := {"messages": messages, "stream": true, "max_tokens": int(options.get("max_tokens", max_tokens))}
		var model := str(options.get("model", provider.model))
		if model != "":
			body["model"] = model
		var out: Dictionary = await Stream.send(provider.base_url, body, task, timeout_s, idle_timeout_s)
		r.ok = out.ok
		r.error = out.error
		r.text = out.text
		r.model = out.model if out.model != "" else model
		r.stop_reason = out.stop_reason
		r.usage = out.usage
	_running.erase(task)
	if _running.is_empty():
		_alive.erase(get_instance_id())
	task._finish(r)
