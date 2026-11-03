# LLM Toolkit Lite for Godot

[![ExcaliBug](https://img.shields.io/badge/Website-ExcaliBug.com-F4B544?style=flat-square)](https://excalibug.com/addons/llm-toolkit/)
[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478CBF?style=flat-square&logo=godotengine&logoColor=white)](https://godotengine.org)
[![LLM Toolkit](https://img.shields.io/badge/itch.io-LLM%20Toolkit%20(full)-FA5C5C?style=flat-square&logo=itch.io&logoColor=white)](https://debugalot.itch.io/llm-toolkit)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?style=flat-square&logo=kofi&logoColor=white)](https://ko-fi.com/debugalot)
[![License: free](https://img.shields.io/badge/License-Free%2C%20commercial%20OK-43D1C6?style=flat-square)](LICENSE)

Talk to a language model running on the player's machine (LM Studio, Ollama or llama.cpp) from
GDScript, without freezing your game. Replies stream in as they are written. Pure GDScript, no
plugins or binaries. This is the free edition of
**[LLM Toolkit](https://debugalot.itch.io/llm-toolkit)**, with the same API.

```gdscript
var llm := Llm.new(LlmProvider.lm_studio())
llm.system_prompt = "You are the innkeeper. Greet tired travellers warmly."
var task := llm.chat("Any rooms free tonight?")
task.text_delta.connect(func(piece): $Speech.text += piece)
var result := await task.wait()
if not result.ok:
	print(result.error.message)   # "Cannot connect to 127.0.0.1:1234. Is the server running?"
```

- **Never blocks.** Requests poll once per frame, with no threads. A character split across network
  packets comes out whole.
- **Streams.** Text arrives piece by piece, for speech bubbles that write themselves.
- **Fails clearly.** Cancel at any time; a server that goes silent times out; errors say what went
  wrong ("No models loaded", "Is the server running?") and keep whatever text had arrived.

## Lite or LLM Toolkit?

| | LLM Toolkit Lite (free) | [LLM Toolkit](https://debugalot.itch.io/llm-toolkit) ($5) |
|---|---|---|
| Streamed text, cancel, timeouts, clear errors | Yes | Yes |
| LM Studio, Ollama, llama.cpp | Yes | Yes |
| OpenAI, Claude, and any server with an API key | | Yes |
| JSON with schemas: repaired, adjusted toward the schema, validated, asked again when wrong | | Yes |
| Conversations that trim themselves and save with your game | | Yes |
| Retries with backoff, `Retry-After`, a queue per server | | Yes |
| Thinking models: reasoning kept out of the reply, `effort` to switch it off | | Yes |
| Model lists, a mock provider for testing without a model | | Yes |

**Upgrading** is replacing `addons/llm_toolkit/` with the full version's folder: code written for
Lite keeps working. `tools/check_upgrade.py` proves it by running this repository's tests and demo
on the full version. Don't then update Lite from the Asset Library, which would put Lite back.

## Requirements

Godot 4.7, tested on 4.7.2. And a local model server: [LM Studio](https://lmstudio.ai),
[Ollama](https://ollama.com) or llama.cpp's `llama-server`, with a model loaded.

## Install

From the editor's **AssetLib** tab, search for *LLM Toolkit Lite*. Or copy `addons/llm_toolkit/`
into your project's `addons/` folder. There is no plugin to enable: `Llm` and `LlmProvider` are
available everywhere.

## Servers

| | Server |
|---|---|
| `LlmProvider.lm_studio(model := "", url := ...)` | LM Studio, `http://127.0.0.1:1234/v1`. An empty model means the model LM Studio has loaded. |
| `LlmProvider.ollama(model := "", url := ...)` | Ollama, `http://127.0.0.1:11434/v1`. Ollama needs a model name, e.g. `"llama3.2"`. |
| `LlmProvider.llama_cpp(url := ...)` | llama.cpp's `llama-server`, `http://127.0.0.1:8080/v1`. |

A provider is a `Resource` with two settings, `base_url` and `model`, so you can also make one in
the inspector and save it. Any server with an OpenAI-style `/chat/completions` that needs no API key
works.

## Chatting

| `Llm` | |
|---|---|
| `chat(input, options := {}) -> LlmTask` | Starts a request and returns at once. |
| `ask(input, options := {}) -> LlmResult` | `chat()`, waiting for the result. |
| `cancel_all()`, `running()` | |
| `provider`, `system_prompt`, `max_tokens` (4096) | |
| `timeout_s` (600), `idle_timeout_s` (120) | The longest a whole reply may take, and the longest the server may stay silent (loading a model counts). |

`input` is a prompt `String`, or an `Array` of `{"role", "content"}` messages (`"system"`, `"user"`
or `"assistant"`), which is how you send a conversation: keep the messages in an array and send it
with each request, as the demo does. **Options** for one request: `system`, `model`, `max_tokens`.

**`LlmTask`**: the signals `text_delta(text)` and `completed(result)`; `text` (the reply so far);
`cancel()`, `is_cancelled()`, `is_done()`, `elapsed()`; and `wait()`, which returns the result
whether the request has finished or not.

**`LlmResult`**: `ok`, `text`, `error`, `model`, `stop_reason`, `usage` (`input_tokens`,
`output_tokens`), `seconds`, and `tokens_per_second()`. When `ok` is false, `text` still holds what
arrived before the failure.

**`LlmError`**: `kind`, `message` (readable as it is) and `http_status`. The kinds are `NETWORK`
(the server isn't running), `AUTH` (it wants an API key), `CONFIG` (a bad URL, no model loaded, a
request the server rejects), `SERVER` (it failed, or the connection dropped mid-reply), `TIMEOUT`,
`TRUNCATED` (the reply hit `max_tokens`), `EMPTY` and `CANCELLED`. `is_transient()` is true for
`SERVER` and `TIMEOUT`, which are worth trying again.

## Good to know

- **Thinking models** (Qwen3, DeepSeek R1...): LM Studio and Ollama usually send the reasoning separately,
  and Lite leaves it out of the reply. A server that writes `<think>…</think>` into the text itself
  passes it through; the full version removes it and can switch thinking off.
- **The player needs the server.** Local models run in LM Studio, Ollama or llama.cpp on the player's
  machine; Lite doesn't start or download one. Show `result.error.message` when it isn't running.
- Lite prints one line in the output panel the first time it sends a request, saying it is Lite.

## Demo

`demo/demo.tscn` (the main scene): talk to the innkeeper of the Rusty Flagon. Pick LM Studio, Ollama
or llama.cpp, load a model in it, and say hello. The demo remembers the conversation by sending the
last 20 messages with each request.

The Godot Asset Library download and GitHub's *Download ZIP* contain only `addons/llm_toolkit/`.
For the demo and the tests, clone [the repository](https://github.com/debugalot/llm-toolkit-lite).

## Tests

```
godot --headless --path . res://tests/test_lite.tscn
```

31 checks against a scripted HTTP server in the same process, so no model is needed: streaming, a
character split across packets, reasoning kept out, a server that ignores streaming, the request
sent, a list of messages, options, errors (the server's own message, 401, 500, cut off at
`max_tokens`, a dropped stream, an empty reply, a silent server, nothing listening, a bad URL),
cancelling, and `Llm.new(p).chat()` finishing although nothing holds the `Llm`. The exit code is 0
when everything passes.

`python tools/check_upgrade.py <godot> <full addons/llm_toolkit>` runs the same tests and the demo on
the full version.

## License

Free to use in any number of your own projects, commercial ones included. Don't redistribute the
add-on itself. The full terms are in [LICENSE](LICENSE).

## Support

If LLM Toolkit Lite saved you time, consider [buying me a coffee on Ko-fi](https://ko-fi.com/debugalot),
getting [LLM Toolkit](https://debugalot.itch.io/llm-toolkit), or checking out more Godot tools on
[ExcaliBug](https://excalibug.com).

## Credits

- **Font:** Nunito by Vernon Adams, Cyreal and Jacques Le Bailly (SIL Open Font License).
- **The innkeeper:** the Sir Debugalot knight, rendered from the KayKit Adventurers knight by Kay
  Lousberg (CC0).
