# Design toolchain (Figma + code CLIs) — plan

Started per the Apple-design-skill `@ghost` note: "I need a design toolchain. Figma + my code CLIs? Both for print (HOA postcard) and UI (HOA, Maharam, kicker apps) — get started on this in a folder and branch in @astra." This is the scaffold + plan; concrete build waits on the scope questions at the bottom.

## Two output paths
- **Print** (HOA postcard, mailers) — needs exact dimensions, bleed, crop marks, CMYK. Figma designs it; export to print-ready PDF. For templated/text-heavy or data-merged print, a **code path** (`md2pdf` in `tools/pdf-sidecars` — HTML+CSS → PDF; `@page` controls size/bleed/margins) avoids Figma round-trips.
- **UI** (HOA site, Maharam, kicker apps) — Figma designs it, then Figma → code. The **apple-design skill** (emilkowalski; spring-based, velocity-aware motion) governs how the *implementation* feels.

## Figma ↔ code CLIs — the integration (the actual "toolchain")
- **Figma Dev Mode MCP server** — lets the code CLIs (Claude/Codex) pull frames, components, variables/tokens, and generated code straight from Figma. The cleanest "Figma + code CLIs" bridge. *[verify current: enable in Figma Dev Mode; confirm the MCP endpoint/auth — web check pending, budget was spent.]*
- **Figma REST API** — scripted export of frames/assets/tokens (token → `GET /files`, `/images`). For pipelines that don't need live MCP.
- **Design tokens** (Tokens Studio / figma-export) — Figma variables → CSS custom properties (web) **and** a Swift tokens file (Maharam/kicker). One source, two targets.
- **apple-design skill** — motion/interaction rules for the UI build.

## Print path candidates
- Figma design → export PDF w/ bleed (or a print plugin).
- `md2pdf` for templated print (HOA letters / postcard back) — CSS-driven.
- **HOA postcard specifically** ties to TODO #18 (per-address QR): a **data-merge** (template + address CSV → per-address PDFs w/ embedded QR) is more code-CLI than Figma — likely the right call for that piece.

## First cuts (once scope is confirmed)
1. Stand up Figma Dev Mode MCP against one real file (a Maharam or kicker UI); prove agents can pull tokens/frames.
2. Token pipeline: Figma variables → CSS vars (web) + Swift tokens (Maharam/kicker).
3. Postcard: pick Figma-export vs code data-merge (the per-address QR leans code-merge).

## Open — needs JS
- Figma-first (design → generate code) or code-first (tokens drive Figma)?
- Postcard: Figma design vs code data-merge (given per-address QR)?
- Which app first — HOA site, Maharam, or kicker?
