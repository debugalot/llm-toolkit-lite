class_name LlmResult
extends RefCounted
## What a finished request produced. Check `ok` first: when it is false, `error` says why, and `text`
## still holds whatever arrived before the failure.

## True when the request succeeded.
var ok := false
## The reply.
var text := ""
var error: LlmError = null
## The model that answered, as the server reported it.
var model := ""
## Why generation stopped, as the server reported it ("stop", "length", ...).
var stop_reason := ""
## Token counts: `input_tokens` and `output_tokens`, when the server reports them.
var usage := {}
## Wall-clock time from the request to the result.
var seconds := 0.0


## Output tokens per second, when the server reported a token count.
func tokens_per_second() -> float:
	var out := int(usage.get("output_tokens", 0))
	return out / seconds if out > 0 and seconds > 0.0 else 0.0


func _to_string() -> String:
	if ok:
		return "LlmResult(ok, %d chars, %.1f s)" % [text.length(), seconds]
	return "LlmResult(failed: %s)" % error
