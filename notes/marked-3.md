**Marked 3**

https://brettterpstra.com/2025/09/06/a-quick-look-at-marked-3/

I have access to this app through setup. How do I get my templates from Marked-2 into it? I also have tools in my (legal) repos for converting Markdown to PDF and Docx. Looks like this does both? The idea is part of the thing where I’d like to get the pdf and markdown tools I use in my legal repos to be more portable. And also scripts to load and unload git hooks. Now that I have two computers I use regularly, that stuff is diverging.

@ghost

**GhOST reply, 2026-08-06 11:35:**

Marked 3 is real and out (officially shipped May 2026, brettterpstra.com/2026/05/18/marked-3-is-officially-out). Big upgrades relevant to you:

PDF export was rewritten from scratch (manual PDF building — logos/images in headers/footers, footnotes on their actual referenced page, working intra-doc links) and DOCX export went from 'terrible' in Marked 2 to clean structure + built-in styles + bidirectional MathML + comment/change tracking.

So yes, it genuinely covers both PDF and Docx export from Markdown now — real overlap with your legal-repo tooling. On migrating templates: there's no official one-click migration tool/doc (checked support.markedapp.com and the release notes) — but styles are just files.

Marked 3's Style Manager has a 'reveal in Finder' option for any installed style, and its Settings window accepts drag-and-drop to add new styles. Practical path: reveal your Marked 2 custom styles in Finder (or find them directly — historically under ~/Library/Application Support/Marked 2/), then drag those files onto Marked 3's Style Manager.

Given Marked 3 also does the PDF/Docx conversion your legal-repo scripts do by hand, worth deciding whether to consolidate onto it as the actual conversion engine (driven via its CLI/URL scheme if it has one) rather than maintaining separate pandoc-style scripts —

see also the Marker note (datalab-to/marker) for the other candidate on that same portability question; worth comparing the two before committing to one.

@ghost once you move the export code to @astra, branch and nightmare the off export to Marked 3. Migrate my legal template to Marked 3 and use that as the default template for export. Try to get rid of the mouse-grabbing part of the pdf export. That's annoying. Add a feature to select a template via CLI flags to the export script. Add import and export of Marked 2 and Marked 3 templates and export the legal templates into @astra as part of this. Any template on disk referenced by the CLI flag that isn't in the running copy of Marked 3 should be imported automatically into marked 3 at runtime or (better) referenced in place without inserting into marked 3 during export. Don't clobber existing templates with this. Don't let the user accidentally use a newer or older version of a template of the same name when exporting when there are conflicting templates in the running Marked 3 vs on disk in @astra

**GhOST reply, 2026-08-19:**

**Four of the five asks are already met, by the route the project deliberately chose in August rather than by the one in this note.**

The mouse-grabbing export is gone: *md2pdf* is headless pandoc into weasyprint, no window, no System Events, 0.73s on a test memo. CLI template selection exists — *--template attorney-docs* takes either a name or a path, and errors rather than silently falling back, which is what you want when the wrong stylesheet on a legal document is the failure. Your legal templates are in @astra as *attorney-docs.css* and *attorney-docs-sans.css*. And templates are referenced in place on disk, never inserted into an application's template store — the option you yourself called better, which also disposes of the clobbering and version-conflict worry entirely.

The fifth ask, importing and exporting templates between Marked 2 and Marked 3, only exists because exports were routed through a GUI app. It is moot while they are not.

**On Marked 3 itself — you already know this and I nearly re-derived it.** The pdf-sidecars README records the 12 August test: Marked 3 3.1.21 via Setapp advertises headless export through AppleScript, but its dictionary's command codes are malformed — four to six characters where AppleEvents require eight — so terminology never loads and it throws -2753 in AppleScript and -1708 in JXA, by bundle id or path, running or not. That is Brett's bug, not a licensing question, and md2pdf was the answer to it. *marked\_to\_pdf.sh* survives as a deprecated fallback rather than being deleted.

**Still open, and only you can answer it:** whether you want Marked 3 for READING and previewing. md2pdf replaces the export path and nothing else.

**One real defect found and fixed while checking this.** Both attorney templates declared *@page* with a margin and no *size*, so weasyprint fell back to A4 — 210×297mm instead of US Letter. Scoped precisely: this affected md2pdf exports through those templates before today. PDFs made through Marked 2's print dialog took their page size from elsewhere and are outside the finding. Cause was the port — under Marked 2 the page size came from the print dialog, so the CSS never needed to declare it, and under weasyprint the stylesheet owns it. Fixed in 58f241a, scoped in 173acda, all three templates now emit 612×792.

Reviewed by GhOST-OpenClaw across three rounds. It caught that I was re-deriving the Marked 3 history the README already held; that producing a headless PDF does not prove a template APPLIED, which is what sent me to compare fonts and page geometry and turned up the A4 problem; and that “every legal export” overstated what had been established. It also re-rendered both templates independently after the fix.