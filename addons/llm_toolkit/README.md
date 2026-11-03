# LLM Toolkit Lite for Godot

Talk to a model running on the player's machine (LM Studio, Ollama or llama.cpp) from GDScript.
Replies stream in without freezing the game.

```gdscript
var llm := Llm.new(LlmProvider.lm_studio())
llm.system_prompt = "You are the innkeeper. Greet tired travellers warmly."
var task := llm.chat("Any rooms free tonight?")
task.text_delta.connect(func(piece): $Speech.text += piece)
var result := await task.wait()
if not result.ok:
	print(result.error.message)
```

The full documentation, the demo and the tests: https://github.com/debugalot/llm-toolkit-lite

The full LLM Toolkit has the same API and adds OpenAI, Claude and keyed servers, JSON with schemas
(repaired, adjusted and validated), conversations, retries and queueing, settings for thinking
models, and a mock provider for tests. Upgrading is replacing this folder:
https://debugalot.itch.io/llm-toolkit

Free to use in your own projects, commercial ones included; see LICENSE.txt.
