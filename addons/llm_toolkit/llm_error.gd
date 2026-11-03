class_name LlmError
extends RefCounted
## Why a request failed. `kind` is one of the constants below; `message` is readable as-is.

const NETWORK := &"network"        ## The server could not be reached. Is it running?
const AUTH := &"auth"              ## The server wants an API key. (Keys need the full LLM Toolkit.)
const CONFIG := &"config"          ## A bad URL, an unknown model, or a request the server rejects.
const SERVER := &"server"          ## The server failed, or the connection dropped mid-reply.
const TIMEOUT := &"timeout"        ## No answer in time.
const TRUNCATED := &"truncated"    ## The reply hit max_tokens. The partial text is in the result.
const EMPTY := &"empty"            ## The model returned no text.
const CANCELLED := &"cancelled"    ## LlmTask.cancel() was called.

var kind: StringName = CONFIG
var message := ""
## The HTTP status code, when the server answered with an error. 0 otherwise.
var http_status := 0


static func make(kind_: StringName, message_: String, http_status_: int = 0) -> LlmError:
	var e := LlmError.new()
	e.kind = kind_
	e.message = message_
	e.http_status = http_status_
	return e


## Worth sending the same request again after a short wait. (The full LLM Toolkit retries these by
## itself, with backoff.)
func is_transient() -> bool:
	return kind in [SERVER, TIMEOUT]


func _to_string() -> String:
	return "%s: %s" % [kind, message] + (" (HTTP %d)" % http_status if http_status > 0 else "")
