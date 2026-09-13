**Firecrawl**

FIRECRAWL

@ghost research this. You've missed this one many times now.

@ghost add this tech to try and @astra

Wake up

**Research — 2026-08-17**

**What it is:** Firecrawl (firecrawl.dev, 166k stars on GitHub, YC-backed, open-source AGPL-3.0) is a web-data API that converts websites into clean, LLM-ready markdown or structured JSON. One unified API covers search, scrape, crawl (recursive), map (sitemap discovery), and interact (click and fill behind logins).

**How it differs from simple scraping:** It handles JS rendering, anti-bot bypasses, smart content waiting, and strips nav/footer/ads automatically (roughly 93% fewer tokens than raw HTML). It parses PDFs and DOCX inline. A plain requests-plus-BeautifulSoup scraper does none of that.

**MCP server:** Yes. Official, keyless at mcp.firecrawl.dev/v2/mcp. Works with Claude Code, Cursor, Windsurf. Also ships a CLI (npx -y firecrawl-cli init).

**API and SDKs:** REST API with official SDKs for Python, Node.js, Go, Rust, Java, and Elixir.

**Pricing:** Hosted free tier gives 1,000 credits per month (one page equals one credit). Paid tiers scale up from there. Self-hosted is free with no credit limits, but it runs as a 7-service Docker stack (Redis, RabbitMQ, Postgres, FoundationDB, API server, Playwright workers). Real sustained load — better on the incoming Linux box than the M4.

**Integration angle:** This is the robust replacement for the WebFetch-then-Safari-scrape-to-markdown dance and the direct fix for the web-search-budget-exhausted wall. Self-host it and GhOST stops hitting that ceiling.

**Status:** Already on tech-to-try (section D, added 8/12). Repo cloned to ~/svnCheckouts/firecrawl.

**GhOST reply, 2026-08-17:**

**Firecrawl** (firecrawl.dev) is a web-data API that converts websites into clean, LLM-ready markdown or structured JSON. One unified API covers search, scrape, recursive crawl, sitemap discovery, and interact (click/fill behind logins). Open-source (AGPL-3.0), YC-backed, 166k GitHub stars.

**How it differs from simple scraping:** handles JS rendering, anti-bot bypasses, smart content waiting, and strips nav/footer/ads automatically (~93% fewer tokens than raw HTML). Parses PDFs and DOCX inline.

**MCP server:** yes, official and keyless at mcp.firecrawl.dev/v2/mcp. Works with Claude Code, Cursor, Windsurf. Also ships a CLI (npx -y firecrawl-cli init).

**Pricing:** hosted free tier gives 1,000 credits/month (1 page = 1 credit). Self-hosted is free with no credit limits but runs as a 7-service Docker stack.

**Integration angle:** this is the robust replacement for the WebFetch/Safari-scrape-to-markdown dance and the fix for hitting web-search-budget walls. Already on the tech-to-try list in astra (section D, added 8/12). Repo already cloned to ~/svnCheckouts/firecrawl.

@ghost - Is paid service? I feel like I connected open claw to it but on some kind of trial. Guessing we need to install local?

**GhOST reply, 2026-08-19:**

**You did connect it, and no, nothing is billing you.** The key is sitting in ~/.openclaw/openclaw.json — the firecrawl plugin is enabled with a webSearch API key starting fc-b287fa. So your memory was right.

**It is a free tier, not a trial, and that distinction is the whole answer.** Firecrawl's own pricing page describes the free plan as 1,000 credits every month, with no card required at signup and no language anywhere about converting to paid. When the credits run out, calls start failing with a quota error. Nothing begins charging. So you cannot silently start owing money on that key.

One conflict worth knowing rather than hiding: a couple of third-party pricing blogs claim that as of May 2026 the 1,000 free credits became a one-time lifetime allowance rather than monthly. Firecrawl's own live page says monthly, and I am taking the primary source. Either way the difference only changes *when* your key stops working, never whether you get charged.

**What burns credits fast, since that decides whether the free tier is enough.** Scrape, crawl and map cost one credit per page. Search costs two per ten results. The structured-output and enhanced modes each add roughly four credits per page on top, so an extract-heavy workflow eats a month's allowance in an afternoon while plain scraping barely touches it. Free-tier rate limits are ten requests a minute for scrape and search, two for crawl.

**On self-hosting: yes it is genuinely free with no credit system at all, but it is not the same product, and that is the part the earlier research undersold.** The stack is the API service, workers, Playwright, Redis, RabbitMQ and a Postgres queue. More importantly, four things are missing or degraded. **Fire-engine is not included**, and it is what backs the anti-bot behaviour, so stealth and proxy evasion are degraded or absent. **Screenshots and page actions do not work at all** in the default stack, because both need Fire-engine. The agent and browser-interact modes are cloud-only. And the AI-backed features ship with no model provider, so extract and JSON mode need your own key or a local model pointed at them — which for you is trivial, since OmniRoute is already an OpenAI-compatible endpoint.

One security note: the self-host config defaults to **USE\_DB\_AUTHENTICATION=false**, so an instance exposed beyond localhost is open by default.

**What I would actually do.** Keep using the free hosted tier through the key you already have, because plain scraping at one credit a page will not exhaust 1,000 a month at your volume. Self-host when you hit the wall or when you want it on the Linux box, and expect to lose screenshots and stealth when you do. The thing self-hosting definitely fixes is the web-search-budget wall, which is the reason it went on the list in the first place.