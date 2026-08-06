litellm

https://github.com/BerriAI/litellm

https://docs.litellm.ai/docs/tutorials/litellm\_qwen\_code\_cli

@ghost research litellm

@astra when finished w/ research

***GhOST reply, 2026-08-06 11:27:***

*LiteLLM (github.com/BerriAI/litellm) — real, active project. It's a unified LLM gateway: a proxy server + Python SDK giving OpenAI-compatible access to 100+ providers (Anthropic, Bedrock, Azure, VertexAI, vLLM, NVIDIA NIM, etc.), with spend tracking, budget controls, load balancing across providers, and an admin dashboard. Open-source core, self-hostable; paid Enterprise tier adds SSO/SAML, audit logs, custom SLAs. The Qwen Code CLI tutorial you linked: point Qwen Code's OPENAI\_BASE\_URL/OPENAI\_API\_KEY/OPENAI\_MODEL env vars at a local LiteLLM Proxy instance, and it transparently routes to whatever backend you configure (including Claude via Anthropic) — no per-provider API key juggling in the CLI itself, plus centralized cost tracking. Relevant to the Fable+Sol rebuild: this is exactly the kind of layer that lets multiple CLI tools (Codex, Qwen, whatever) share one proxy with unified spend visibility instead of each holding its own provider credentials.*