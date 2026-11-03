@tool
class_name LlmProvider
extends Resource
## A local model server. Make one with a factory:
##   LlmProvider.lm_studio()   LlmProvider.ollama("llama3.2")   LlmProvider.llama_cpp()
## Lite talks to servers on the player's machine, which need no API key. The full LLM Toolkit adds
## OpenAI, Claude and any keyed server: https://debugalot.itch.io/llm-toolkit

## The server's OpenAI-style API, e.g. "http://127.0.0.1:1234/v1".
@export var base_url := "http://127.0.0.1:1234/v1"
## The model to use. For LM Studio, leave it empty to use the model that is loaded.
@export var model := ""


static func lm_studio(model_: String = "", url: String = "http://127.0.0.1:1234/v1") -> LlmProvider:
	return _make(model_, url)


static func ollama(model_: String = "", url: String = "http://127.0.0.1:11434/v1") -> LlmProvider:
	return _make(model_, url)


static func llama_cpp(url: String = "http://127.0.0.1:8080/v1") -> LlmProvider:
	return _make("", url)


static func _make(model_: String, url: String) -> LlmProvider:
	var p := LlmProvider.new()
	p.base_url = url
	p.model = model_
	return p


## A short readable name, e.g. "LM Studio (qwen3-8b)".
func describe() -> String:
	var name := base_url
	if base_url.contains(":1234"):
		name = "LM Studio"
	elif base_url.contains(":11434"):
		name = "Ollama"
	elif base_url.contains(":8080"):
		name = "llama.cpp"
	return name + (" (%s)" % model if model != "" else "")
