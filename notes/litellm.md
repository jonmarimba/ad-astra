**litellm**

https://github.com/BerriAI/litellm

https://docs.litellm.ai/docs/tutorials/litellm\_qwen\_code\_cli

@ghost research litellm

@astra when finished w/ research

**GhOST reply, 2026-08-06 11:27:**

LiteLLM (github.com/BerriAI/litellm) — real, active project. It's a unified LLM gateway: a proxy server + Python SDK giving OpenAI-compatible access to 100+ providers (Anthropic, Bedrock, Azure, VertexAI, vLLM, NVIDIA NIM, etc.), with spend tracking, budget controls, load balancing across providers, and an admin dashboard. Open-source core, self-hostable;

paid Enterprise tier adds SSO/SAML, audit logs, custom SLAs. The Qwen Code CLI tutorial you linked:

point Qwen Code's OPENAI\_BASE\_URL/OPENAI\_API\_KEY/OPENAI\_MODEL env vars at a local LiteLLM Proxy instance, and it transparently routes to whatever backend you configure (including Claude via Anthropic) — no per-provider API key juggling in the CLI itself, plus centralized cost tracking. Relevant to the Fable+Sol rebuild:

this is exactly the kind of layer that lets multiple CLI tools (Codex, Qwen, whatever) share one proxy with unified spend visibility instead of each holding its own provider credentials.

@ghost I also have the router thing setup. Would this conflict or integrate with that well? I like the router thing so far. It's setup in open code at the moment and I've trialed it there.

@ghost I need some kind of ability to sync open code and qwen model availability via the router thing and ultimately ollama. I'd like to be able to automatically add interesting (read: anything approaching frontier quality like GLM 5.1 or Kimi k) new models on ollama automatically. I'd also like to be notified when ollama adds such a model so I know to try it

**GhOST reply, 2026-08-18:**

Researched, and the verdict is in the canonical tech-to-try list in @astra, symlinked into Obsidian as *tech-to-try.md*. Replying here because the work landed but the note was never marked answered.

**litellm** — unified LLM gateway and proxy, OpenAI-compatible across 100+ providers, with spend tracking.

Answering your actual question about the router thing you already run in OpenCode: they overlap rather than conflict, and the honest answer is that you should not run both as gateways. Your setup already resolved this in practice — OmniRoute is the hub now, at localhost:20128, and every model host is a provider node it discovers and ranks, generating client configs for Codex, OpenCode and the rest. litellm would be a replacement for that role, not an addition to it. Since you like the router thing and it is working, the reason to move would be litellm's spend tracking, and nothing else.