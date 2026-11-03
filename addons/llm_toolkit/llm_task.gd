class_name LlmTask
extends RefCounted
## A request in flight, returned by Llm.chat(). Connect text_delta to show the reply as it streams
## in, or just wait for the result:
##   var task := llm.chat("Any rooms free tonight?")
##   task.text_delta.connect(func(piece): label.text += piece)
##   var result := await task.wait()

## A piece of the reply, as it arrives.
signal text_delta(text: String)
## The request finished, succeeded or not.
signal completed(result: LlmResult)

## The reply so far.
var text := ""
## Set when the request has finished.
var result: LlmResult = null

var _cancelled := false
var _started_msec := Time.get_ticks_msec()


## Stops the request. The result arrives right after, with an error of kind LlmError.CANCELLED
## and whatever text had arrived.
func cancel() -> void:
	_cancelled = true


func is_cancelled() -> bool:
	return _cancelled


func is_done() -> bool:
	return result != null


## Seconds since the request was made.
func elapsed() -> float:
	return (Time.get_ticks_msec() - _started_msec) / 1000.0


## The result, waiting for it if needed. Safe to call before or after the request finishes.
func wait() -> LlmResult:
	if result != null:
		return result
	return await completed


func _emit_text(piece: String) -> void:
	if piece != "":
		text += piece
		text_delta.emit(piece)


func _finish(r: LlmResult) -> void:
	r.seconds = elapsed()
	result = r
	completed.emit(r)
