# Localization Super-Prompt — iOS/macOS (SwiftUI) in-app strings

> Reusable prompt for localizing a SwiftUI app's **user-facing strings** into the App Store
> locales, correctly and *verifiably*.

## Objective
Make every user-facing string localizable, translate it into the project's App Store locale set
with natural/native quality, **review** it per-locale for context errors, and **prove it builds
and renders** — never trust "it compiles" or a single build.

## Prerequisites
Not *true* prerequisites, but things will go much more smoothly if you have these things installed and set up:
- Claude Code CLI with plenty of Opus usage available (or Fable) -- the workhorse. Also used for validating and verifying work
- OpenAI "codex" and Google's Antigravity "agy" CLIs -- used for verifying and validating work
- Drew's Xcode MCP Server [https://github.com/drewster99/drews-xcode-mcp](https://github.com/drewster99/drews-xcode-mcp). While there are many MCP servers to build Xcode projects, this one works particularly well because it drives Xcode rather than using 'xcodebuild'.
- Export the most up-to-date version of agent skills provided by Xcode. In Xcode 27.0, you can run `xcrun agent skills export ~/Downloads/xcode-agent-skills` to export the skills to the `~/Downloads/xcode-agent-skills` folder. Inside the subfolder `swiftui-specialist/references`, you will find `localization.md`. These are Apple's SwiftUI-specific best practices for localization. You should reference this file directly `@~/Downloads/xcode-agent-skills/swiftui-specialist/references/localization.md`. As a work-around, the localization.md from Xcode 27.0 developer beta 2 is included at the end of this document.
- If these prerequisites aren't installed and accessible, STOP. Encourage the user to install them and then start again. If they really want to proceed, then do your best.

## The App Store localizations (authoritative list)
Full set from Apple's [App Store localizations reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)
— **50 languages/locales**. English variants `en-AU, en-CA, en-GB, en-US` fall back to `en`; the
rest are the non-English targets:

| Language | Code | | Language | Code |
|---|---|---|---|---|
| Arabic | `ar` | | Kannada | `kn` |
| Bangla | `bn` | | Korean | `ko` |
| Catalan | `ca` | | Malay | `ms` |
| Chinese (Simplified) | `zh-Hans` | | Malayalam | `ml` |
| Chinese (Traditional) | `zh-Hant` | | Marathi | `mr` |
| Croatian | `hr` | | Norwegian | `no` |
| Czech | `cs` | | Odia | `or` |
| Danish | `da` | | Polish | `pl` |
| Dutch | `nl` | | Portuguese (Brazil) | `pt-BR` |
| English (Australia) | `en-AU` | | Portuguese (Portugal) | `pt-PT` |
| English (Canada) | `en-CA` | | Punjabi | `pa` |
| English (U.K.) | `en-GB` | | Romanian | `ro` |
| English (U.S.) | `en-US` | | Russian | `ru` |
| Finnish | `fi` | | Slovak | `sk` |
| French | `fr` | | Slovenian | `sl` |
| French (Canada) | `fr-CA` | | Spanish (Mexico) | `es-MX` |
| German | `de` | | Spanish (Spain) | `es-ES` |
| Greek | `el` | | Swedish | `sv` |
| Gujarati | `gu` | | Tamil | `ta` |
| Hebrew | `he` | | Telugu | `te` |
| Hindi | `hi` | | Thai | `th` |
| Hungarian | `hu` | | Turkish | `tr` |
| Indonesian | `id` | | Ukrainian | `uk` |
| Italian | `it` | | Urdu | `ur` |
| Japanese | `ja` | | Vietnamese | `vi` |

- **App Store Connect metadata codes differ from Xcode's in-app identifiers** for a few locales —
  ASC uses `es-ES`/`no`, Xcode's `.xcstrings` typically use `es`/`nb`; App Store metadata also has
  no `en` "source", each English variant is its own entry. Map between the two; don't assume they're
  identical.
- **For in-app strings, always derive the exact target set from the app's existing
  `Localizable.xcstrings` and match it** — don't invent a list. Use the table above (and the linked
  doc) as the authoritative superset when deciding which locales the app *could* add or when doing
  App Store metadata localization.

---

## Phase 0 — Recon (find ALL user-facing strings)
Sweep, don't assume. The misses are always in the same places:
- **SPM packages bundled in the app** (paywall, onboarding, monetization, etc.) — their literals
  resolve against the *app's* bundle, so they silently render English even when the app is localized.
- **App extensions**: widget, share, action, AppIntents/Shortcuts, notification content.
- **Info.plist strings** — permission usage descriptions (`NSMicrophoneUsageDescription`, etc.),
  `CFBundleDisplayName`, background-mode strings. These render in *system* alerts — the most
  visible strings in the app. They localize via a separate **`InfoPlist.xcstrings`** per target
  (including each extension), NOT `Localizable.xcstrings`.
- **Accessibility**: `Text` in `.accessibilityLabel` / `.accessibilityAction(named:)`.
- **Accessibility VALUES, not just labels** — closures/computed properties returning `String` that
  feed `accessibilityValue`/status text render verbatim (spoken English). Fix pattern: return
  `Text("…")` so the interpolation compiles to `LocalizedStringKey`.
- **Config-object data passed into packages** — display strings (feature bullets, titles) in a
  config struct handed to a package initializer are invisible to any `Text()`-oriented sweep and
  ship English in every locale. Grep for structs/arrays of display strings passed to package inits.
- **Homemade localization layers that don't work** — if the codebase has its own
  `LocalizedString`-ish type, read its implementation AND confirm views call the localized accessor
  (one had a stub `localizedValue` returning English while all 17 views read `.defaultValue`
  anyway). Verify end-to-end on screen, not by reading the type.
- **Strings that double as logic keys** — "Today"/"Yesterday"/"This Week" used as both display
  headers and comparison/sort keys. Localize at render only; keep English internally. (This bit
  twice.)
- **Loading/progress/status messages** — rotating message arrays, model-enum states, export/import
  errors. Counter-rule: confirm an enum's `.description` is actually *displayed* before localizing
  it — skipping undisplayed ones avoids catalog pollution.
- **Error/alert messages**, progress overlays, empty states.
- Strings **computed in models** (e.g. "Year"/"Monthly"/"3 Days Free") not just in views.
- **Text as DATA** — user-facing strings living in *data*, not code, invisible to every
  code-oriented sweep: bundled JSON/plist/CSV content, seed databases, sample/demo content,
  server-delivered strings. Push notifications: the payload should use
  `title-loc-key`/`loc-args` so the *device* localizes at display time. And the migration trap:
  display strings **persisted in user data** (UserDefaults, the database) stay English forever
  after you localize the app — persist stable identifiers, localize at render.
- **Exclusions**: `#Preview` blocks don't ship. Filter non-translatables (pure
  punctuation/format-specifier/emoji/unit keys) before dispatching to translators, and **record the
  skip list** so the decision is auditable.
- **`Text(verbatim:)` bypasses localization entirely** — it renders its String as-is. Find every
  one. Localize at the *source of the value*: if it comes from a (package) model property, route
  that property through `String(localized:…, bundle: .module)`; then `Text(verbatim:)` shows the
  already-localized string and the call site needs no change.
Locate ALL existing String Catalogs and their locale set; that set is your target. Strings live in
**three distinct catalog types**, each in its owning target (app, each extension, each package):
`Localizable.xcstrings` (in-app strings), `InfoPlist.xcstrings` (system-surface strings), and
`AppShortcuts.xcstrings` (App Shortcut trigger phrases). A pass that only touches
`Localizable.xcstrings` is incomplete — enumerate every catalog in every target up front.
**Audit every target with a checklist** — app, widget, share, action, intents: literal-grep + its
own catalog — and **never conclude "no strings" from a skim**: a share extension declared
string-free turned out to have 4 user-facing strings and no String Catalog at all. (A synchronized
folder group auto-includes a dropped-in catalog.)

## Phase 1 — Make strings localizable
- `Text("literal")` is auto-localizable; for non-literal/model code use `String(localized:)`.
- **Fix-pattern menu — pick by call-site shape:**
  - static-only `String` parameter → change the type to `LocalizedStringKey` (the resulting build
    failure then *proves* every call site is a literal);
  - mixed static/dynamic parameter → `String(localized:)` at the static call sites only;
  - computed model property → `String(localized:)` inside the property;
  - display-plus-logic string → localize at render, keep English internally (Phase 0).
  Watch for interpolated literals (`title: "\(x)"`) — the one shape that compiles fine but stays
  dynamic and never localizes.
- **Don't alter user-visible text while localizing.** "Improving" `...` to `…` changes the key,
  breaks the lookup, and is scope creep. Localize what's there; propose copy edits separately.
- **Escaping:** catalog keys must contain REAL newlines matching the runtime string — an extraction
  once produced a literal `\n` in the key and every lookup would have missed.
- Add a `Localizable.xcstrings` per target/module; source language `en`.
- **SPM PACKAGE GOTCHA (the #1 silent bug):** SwiftUI `Text("x")` / `Button("x")` resolve
  `LocalizedStringKey` against the **consuming app's main bundle, not the package**. In a package:
  1. add `defaultLocalization: "en"` to `Package.swift`;
  2. add `Localizable.xcstrings` under the target's `Resources` (`.process`);
  3. pass `bundle: .module` on **every** `Text`/`Button`, and use
     `String(localized: "x", bundle: .module)` in non-View code;
  4. convert `Button("x") { … }` → `Button(action: { … }, label: { Text("x", bundle: .module) })`.
- **Never make a key out of pure format specifiers / punctuation** (`"%@, %@"`, `"%@ - %@"`).
  Xcode can't derive a Swift symbol from it → **String Catalog BUILD FAILURE** ("Unable to derive
  a symbol name from this key"). Use an explicit stable identifier key + `defaultValue:`:
  `String(localized: "a11y.dialSelection", defaultValue: "\(a), \(b)", comment: …)` — the symbol
  comes from the identifier, the format lives in the value. (These are two different initializers
  with two different rules: the `defaultValue:` overload's `localized:` key is a `StaticString` —
  no interpolation in the key itself — while plain `String(localized: "\(n) Months")` takes a
  `String.LocalizationValue`, where interpolation *is* the mechanism and becomes the format
  specifier. Don't "fix" one to match the other.)
- **Counts need plural variations, not `"%lld Months"`.** A fixed `%lld Months` is grammatically
  wrong in Arabic/Polish/Russian/Ukrainian/etc. Make those keys String Catalog **plural variations**
  (`variations.plural.{zero,one,two,few,many,other}`, correct CLDR categories per language: ar uses
  all six; pl/ru/uk/cs/sk use one/few/many/other; CJK/Thai/Indonesian are `other`-only; Turkish is
  `one`/`other` — its nouns stay singular after numerals so the two values often coincide, but the
  catalog still needs both categories). **No code
  change needed** — `String(localized: "\(n) Months")` auto-selects the category at runtime once the
  catalog has the variations. It compiles to a `.stringsdict`.
- **Compound counts need `%#@name@` substitutions**, not just plural variations — two counts in one
  key ("%lld of %lld photos processed") require one named substitution per count, each with its own
  plural variations. `xcstringstool compile` validates them (Phase 7).
- **Casing must be locale-aware.** `.uppercased()` / `.capitalized` are locale-insensitive `String`
  methods (break Turkish dotless-i; force title-case onto non-English names like "voz de chipmunk").
  Use the SwiftUI **`.textCase(.uppercase)`** modifier (honors the environment locale). Don't
  hand-join localized fragments with hardcoded `", "` + `.capitalized` — make the whole sentence a
  localizable format.
- **One concept = one term across EVERY surface.** A name (effect/feature/tier) appears in: the
  primary label, the widget's composed `"Record · X"` labels, AppIntents/Shortcuts descriptions
  ("Applies … (Chipmunk, Giant, Cyborg)"), the paywall perk list, and bare accessibility keys.
  Changing one and not the others is the most common consistency bug. Establish a canonical value
  per (concept, locale) and propagate it to all of them.
- **Spoken commands (Voice Control / Siri / Shortcuts) are special — localize them, but differently
  from read-aloud labels.** A VoiceOver `.accessibilityLabel` is *read aloud*, so just translate it
  naturally. But a **Voice Control "named" action** (`.accessibilityAction(named: Text("Reverse"))`)
  and a **Siri/Shortcuts trigger phrase** (`"${applicationName} record"`, `"Reverse Audio"`) are
  words the user must *say* to invoke the action — so:
  1. the localized command MUST match the **visible on-screen label** for that control (the user
     says what they see) — keep the named action and its dial/button label the *same* localized term;
  2. use natural, easily-**pronounced** native words — machine-literal phrases can be awkward to
     speak and can break Voice Control / Siri matching;
  3. keep the app-name token (`${applicationName}`) as the brand, untranslated;
  4. don't `.uppercased()`/title-case the *value* — casing doesn't change speech, but store the
     plain localized word so the visible-label match holds;
  5. App Shortcut trigger phrases do NOT live in `Localizable.xcstrings` — they go in a dedicated
     **`AppShortcuts.xcstrings`** in the target that declares the `AppShortcutsProvider`, and every
     phrase must contain the `${applicationName}` token. Intent titles/descriptions/parameter names
     use `LocalizedStringResource` (not `LocalizedStringKey`). **These phrases do NOT auto-extract**
     — add and translate them manually, preserving `${applicationName}` in every locale.
  Flag every spoken command for native-speaker review (Phase 5).
- **Layout: avoid `.fixedSize()` on translatable text** — it forces single-line ideal width, so
  long translations overflow the card/button. Use `.fixedSize(horizontal: false, vertical: true)`
  (wrap) or `.lineLimit(1).minimumScaleFactor(…)` (shrink).
- **Restructure interpolated sentences into format keys** so translators can reorder:
  `"\(price) per \(period)"` → key `"%@ per %@"`. Keep currency/number formatting native (StoreKit
  already localizes prices).
- **Comment every key**: what it is, what each `%@`/`%lld` is, length limits, where it shows,
  whether it's uppercased, and the part of speech for ambiguous short words (see Phase 5). The
  translator (human or LLM) is only as good as the comment.

## Phase 2 — Locale-correct BEHAVIOR (not just strings)
A whole class of shipped bugs is locale *behavior* — invisible to any string sweep:
- **Numeric INPUT parsing.** `Double(string)` rejects `,` while `.decimalPad` produces it across
  most of Europe — German users typing `12,5` silently saved 0-kcal entries. Parse locale-aware.
  Beware over-fixing (a first fix stripped ordinary spaces as "grouping separators"). Verify with a
  small harness across locales.
- **Hardcoded weekday/month label arrays** — wrong in every Monday-first locale. Rotate by
  `calendar.firstWeekday`; harness-verify against `de_DE`.
- **Fixed `dateFormat` strings** — replace with localized templates / `FormatStyle`.
- **Untranslatable sentence construction** — word-order-dependent concatenation. Test every
  composed string with: *"could a translator reorder this?"* If not, restructure into a format key
  (Phase 1).

## Phase 3 — Glossary (terminology canon — gated)
If ~5+ concepts (effect/feature/tier/badge names, proper nouns) recur across 3+ surfaces, build
`LocalizationGlossary.json` next to the catalogs, committed. Otherwise the Phase 4 policy bullets
suffice. One entry per concept:
```json
"effect.chipmunk": {
  "english": "Chipmunk",
  "policy": "native-word",
  "keys": ["Chipmunk", "Record · %@", "intent.applyEffect.description"],
  "terms": { "es": "Ardilla", "sk": "Veverička", "de": "Chipmunk" }
}
```
`policy` is one of `native-word` | `loanword` | `brand-do-not-translate`. `keys` is derived by
grepping the English values for the term.
- **The prompt holds the rules; the glossary holds the decisions.** The app name is a glossary
  entry with `policy: "brand-do-not-translate"` (plus `shouldTranslate: false` on pure-brand keys —
  Phase 4). Loanword-vs-native gets decided once per concept *here*, as data — not re-decided by
  each translation agent mid-sentence (sk "Čipmank" vs "Veverička" happened exactly that way).
- **Translate the glossary FIRST**: one small agent wave over just the concept terms, then a native
  review of only those. It's the highest-leverage review in the whole job — these words repeat on
  every surface.
- The filled glossary is **binding input** to every Phase 4/5 agent; pure-concept keys are applied
  mechanically in Phase 6; Phase 7 lints the catalog against it.
- The glossary never becomes a strings file — `.xcstrings` stays the single source of truth. It is
  a forward-flowing constraint plus lint reference, reused on later passes (which is what prevents
  drift when a new surface is added).

## Phase 4 — Translate (parallel agents)
- Fan out agents grouped ~5 locales each; persona "professional iOS app localizer"; return **STRICT
  JSON** `{ "<locale>": { "<EnglishKey>": "<translation>", … }, … }`, no prose/fences, exact keys.
- **Each agent's input payload must include, per key: the key, the English value, and the catalog
  `comment`** (what it is, what each specifier means, where it shows, length limits, part of
  speech) — plus the filled glossary (Phase 3) as **binding terminology**. The comments were
  written for the translator (Phase 1) — a translation pass that receives bare key/value pairs
  throws that context away and reintroduces exactly the wrong-sense/homonym bugs Phase 5 exists to
  catch.
- **Hardcode absolute scratch paths in agent prompts** — workflow args once failed to propagate and
  agents wrote to `<repo>/undefined/`.
- **Validate ONE group's JSON early** (format, key count, specifier preservation) before the fleet
  finishes — a format bug caught late wastes 20 agents.
- **Plan for the slow group.** Complex-script groups (the Dravidian set) finish long after the
  rest; state the policy up front: merge the completed groups and re-run only the straggler rather
  than blocking everything.
- Rules every agent must obey:
  - **Preserve format specifiers exactly** (`%@`, `%lld`, `%1$@`…). May reorder positional
    specifiers for grammar; if reordering, use positional for ALL of them.
  - Natural/native, not literal; match UI tone; keep button/badge labels short.
  - Regional variants reflect real norms (es vs es-MX, pt-BR vs pt-PT, zh-Hans vs zh-Hant; he/ar RTL).
- **App name / brand rule:** *"This is the app name `<X>`. Do NOT translate it as the product name
  (e.g. the title). DO translate it when used descriptively in a sentence."* Additionally mark keys
  that are *purely* the brand name with **`shouldTranslate: false`** in the catalog, so the rule is
  enforced mechanically, not just by translator instruction. (Keys using the name descriptively
  inside a sentence still get translated — don't mark those.)
- **Proper-noun / loanword policy:** decide up front — *native word everywhere it has one* vs *keep
  the loanword* — then apply it **consistently across locales AND duplicate keys**. When the native
  word genuinely *is* the loanword (de "Cyborg", es "Robot"), that's correct; don't force a worse
  translation. For badges (PRO/MAX/BASIC) the loanword is usually right and length-constrained.

## Phase 5 — REVIEW (native per-locale — a SEPARATE pass from translation)
A translation pass (human or LLM) produces real errors that only a native re-read catches. Fan out
one reviewer per locale (or ~5/agent), give each the full key set (English + comment + that locale's
value) plus the glossary (Phase 3) so cross-surface consistency is checked against a stated
canon, not inferred. Have them flag ONLY problems as strict JSON.
**EVERY batch gets its review pass — including late drips.** The initial 249-key batch got
translate + review, but follow-on batches (loading messages, status enums, plurals, substitutions,
a11y values) went translate-only and had to be confessed as a quality caveat three separate times.
Rule: **no batch merges without its review pass**; keep a per-batch reviewed/unreviewed ledger. Real bug classes this catches:
- **Wrong-sense / part-of-speech homonyms** — short UI words hide these: "Record" (verb vs noun),
  "Reverse" / "Clear" / "Format" / "Manage" / "Original" (verb vs noun vs adjective). Good comments
  prevent it; review confirms it.
- **Copy-paste / wrong-string mistranslations** — e.g. "Review the app" rendered as "Reverse" in
  several locales: grammatical, but the wrong string entirely.
- **Typos / accents** — e.g. Hebrew "כששתפים"→"כשמשתפים", Spanish "Repróducelo"→"Reprodúcelo".
- **Cross-surface / cross-variant inconsistency** — es vs es-MX disagree; dial says one word, widget
  another; an AppIntents description still lists the English name.
- **Loanword-vs-native mistakes** — sometimes the loanword is native (es "Robot"); sometimes a
  transliteration is worse than an existing native word (sk "Čipmank" vs the better "Veverička"
  already used elsewhere — prefer the term other surfaces already use).
- **Unspeakable / mismatched spoken commands** — flag Voice Control named actions and Siri/Shortcuts
  trigger phrases that a native speaker wouldn't naturally *say*, that are hard to pronounce, or that
  don't match the visible on-screen label for the same control (see Phase 1).
- **Overflow / length** — flag values much longer than the English for a tight slot.
Verify each flag against the catalog before applying (reviewers occasionally misread). Fix values
AND, when the cause was ambiguity, **improve the comment so it can't recur**.

## Phase 6 — Apply to the catalog
- Write each cell as `stringUnit { "state": "translated", "value": … }`. **Preserve** key-level
  `comment` / `extractionState` and all untouched locales.
- **Never rely on build-time extraction to add keys** — insert them explicitly (`extractionState:
  manual` where Xcode might drop them), and let the Phase 7.1 code-vs-catalog key diff be the
  source of truth for completeness.
- **Whenever ANY build rewrites the catalog** (it happens — once as a 132k-line re-serialization),
  run a loss-check script before committing: 0 lost string units, 0 changed values, exactly the N
  expected added keys.
- Keys that are *purely* a glossary concept (Phase 3): write the value mechanically from the
  glossary — no agent involved, no drift possible.
- **Don't touch `knownRegions`** — the compiled `.lproj` directories alone make iOS offer the
  languages; planned pbxproj edits proved unnecessary.
- **Round-trip check:** before editing, test whether
  `json.dumps(json.load(file), ensure_ascii=False, indent=2)+"\n"` reproduces the file
  byte-identically. It usually **won't** on an Xcode-written catalog (Xcode uses `" : "`
  separators, Python uses `": "`). If it round-trips, scripted value-only edits give a minimal
  diff. If it doesn't, either (a) do targeted string-level edits on the raw text, or (b) accept a
  one-time whole-file reformat, then verify the change is value-only by comparing `json.load` of
  old vs new (identical except the intended values) — and expect Xcode to reformat it back on the
  next key-extraction build.
- A **build rewrites the `.xcstrings` when extraction detects a key delta** (Xcode's `" : "` style
  vs `json.dump`'s `":"`); value-only edits don't trigger it. Expect a one-time reformat when you
  add/rename keys. Keep scripted edits minimal-diff; rebuild from `HEAD` + your delta if needed.
- **Never touch** the source language or English variants (`en-AU/CA/GB` fall back to `en`).

## Phase 7 — VERIFY — and BUILD (the part everyone skips)
0. **BUILD it — and re-build the FINAL committed state.** Non-negotiable. A String Catalog build can
   *pass on the build that extracts a new key and FAIL on the very next build* (symbol generation,
   the all-specifier-key trap). So: build; if the build modified the catalog, **build again**
   (ideally `clean` then build) and confirm the on-disk state you're committing is green. One
   post-edit build is not enough. **Build with `build_project` (drewster99/drews-xcode-mcp); use
   Bash only to inspect DerivedData output afterward.** Most MCP servers and raw `xcodebuild` don't
   run string extraction the way an Xcode build does — don't fall back to `xcodebuild` "just this
   once".
1. **Key match:** every key the *code* generates must exist in the catalog or it silently shows
   English. Derive code keys, diff against catalog keys programmatically.
2. **Specifier safety (crash risk):** every translation's format-specifier count must equal the
   source's — more specifiers than args garbles/crashes at runtime. Check every cell programmatically.
3. **`xcrun xcstringstool compile --output-directory /tmp/out Localizable.xcstrings`** — the same
   compiler Xcode uses; errors on specifier mismatches, validates plural variations (→ `.stringsdict`).
4. **Inspect the COMPILED bundle, not the source.** `swift build` copies catalogs *raw* — only the
   Xcode app build compiles them. After building, confirm `<locale>.lproj/Localizable.strings`
   (and `.stringsdict`) exist with the real translated values (for a package, inside its `*.bundle`
   in the `.app`); `plutil -p` and verify it's the translation, not English.
5. Spot-check a few locales actually render translated (run, or read the compiled `.strings`).
   To run in a locale: set the scheme's **App Language**, or pass `-AppleLanguages (xx)` as a
   launch argument. `.environment(\.locale, Locale(identifier: "xx"))` in previews affects
   SwiftUI formatting only — a true bundle-language test needs the scheme/launch-argument route.
6. **Pseudolocalization sweep:** launch with `-NSDoubleLocalizedStrings YES` and walk every
   top-level screen — doubled text = localized, single = gap. This caught "Yesterday" and
   "Manual"/"Auto" that code sweeps missed. Note: `en-XA` does NOT work at runtime (it needs
   build-time generation) — don't lose a cycle discovering that.
7. **Mandatory RTL runtime spot-check** (Arabic or Hebrew) in addition to one LTR locale — the
   Arabic pass caught a `Text(String)` gap the Japanese pass didn't, and validates mirroring,
   Arabic-Indic numerals, and calendar rendering in one shot.
8. **Verify each gated surface in a real locale** using the app's debug flags (e.g.
   `--onboarding-only`, `--debug-paywall`) — an onboarding stub bug was only caught *on screen*,
   after all catalog work was "done."
9. **Argument-order check** for keys with multiple same-type specifiers (`%lld of %lld`, `%lld
   remaining`): every translation must preserve source order or use positional specifiers
   throughout — otherwise numbers silently swap at runtime.
10. **Glossary lint** (if Phase 3 ran): for each (concept, locale), every key listed in the
    glossary should contain that locale's canonical term. **Flag, don't hard-fail** — inflected
    languages legitimately decline the term mid-sentence; flags go back through review.

## After EVERY phase — cross-LLM review, recheck, then COMMIT
**ALL of these reviews are absolutely necessary** — this process is critical to success, and
**different reviewers find different bugs** (agy found the `accessibilityValue` closure returning
spoken-English `String`, the day-cell status literals, and 4 missing keys; codex found the
hardcoded final onboarding screen). After each phase:
1. Have another LLM code-review the phase's work — `codex` and/or `agy` (Gemini). If neither is
   available, shell out to a **fresh `claude` session** (Opus or better). Whichever reviewer runs,
   brief it properly: state the **goal of the phase**, paste a **verbatim copy of that phase's text
   from this document**, and instruct it to code-review the changes *with respect to that phase*.
   Scope the review to the code and localization *mechanics*; **exclude the multi-thousand-line
   translation JSON** from the diff under review.
2. Operational recipe: `codex exec review --base <sha> -s read-only`, run in the **background** (a
   30-commit diff exceeds a 10-minute foreground cap) and **with stdin closed** — codex hangs
   otherwise. agy runs similarly; a fresh claude gets the same scoped briefing.
3. **Verify every finding against the actual code before fixing it.** Phase 5's rule — "reviewers
   occasionally misread" — applies to code reviewers too.
4. Then perform your own recheck, verbatim:
   > # /recheck - Check your work
   > Think hard, very carefully, step by step, and please check your work.
   > Check your assumptions. Make sure they are correct. Think about how they could be wrong and
   > try to validate them.
   > Then think step by step through the logic of your changes and make sure they are all correct
   > also.
   > Make sure your changes couldn't have inadvertently messed up anything else. NO UNINTENDED
   > CONSEQUENCES.
5. **Commit the phase.** One commit per phase makes it easy to see what changed between phases —
   and gives the next phase's reviewer a clean `--base <sha>`.

### Final gate — after the last phase, before shipping
- **TWO independent LLMs code-review the whole change set** (codex AND agy; substitute a fresh
  `claude` session, Opus or better, for any that's unavailable) — same briefing rules as above, but
  the scope is the entire localization effort, base = the pre-localization commit.
- Verify their findings, fix, then run your own recheck again (verbatim above) — AND the
  stupid-check, verbatim:
  > # /stupid - Investigate the project to find stupid things and propose fixes
  > 1. Investigate this project to gain a general understanding of it
  > 2. Going file by file, deep dive into all the code and analyze it
  >   - Check for anything in the code that might be:
  >       - stupid
  >       - unsafe
  >       - crash-prone
  >       - generally poor practices
  >   - Create a task list to investigate each one of these.
  > 3. Think step by step to organize and/or group this list of items/issues to possibly address.
  >   - These issues should be numbered for later reference and presentation.
  > 4. For each item/issue on the list, launch a subagent using the Agent tool
  >   - We will call these Analyzer agents.
  >   - Subagents should all be launched in parallel
  >   - For each issue, launch a subagent to analyze that specific item and propose a solution to
  >     that issue.
  >   - The solution should follow best practices
  >   - The Analyzer agent must be given a summary of the overall project, a summary of the
  >     problem/issue, the assigned index number of the issue, and instructions
  >   - Each Analyzer subagent should be told to think of ways its solution might not be correct
  >     and resolve them or consider better options
  > 5. For each subagent response that completes, launch another subagent
  >   - We will call these Reviewer agents.
  >   - Again, these should be launched in parallel whenever possible
  >   - Each agent in this round must review the original issue/problem item and the Analyzer
  >     agent's proposed solution
  >      - Review for completeness
  >      - Reviewer agent should think step by step through the proposed solution. For each step,
  >        it should compare the proposed solution with the original issue and make sure it solves
  >        the problem.
  >      - Solutions should not affect any code unrelated to the issue
  >      - Solutions must be syntactically correct and not break semantic meaning of the original
  >        code (unless of course the semantics were wrong in the original code)
  >      - Each Reviewer agent should be given a summary of the overall project, a summary of the
  >        problem/issue, the details of the Analyzer agent's proposed solution, and the assigned
  >        index number of the issue, and instructions
  >      - Each Reviewer agent should assess whether the solution is full and complete, bug free,
  >        fully addresses the original issue, does so without harming any other code or breaking
  >        something else, and follows best practices.
  >      - The Reviewer agent then should return the proposed solution, with any changes or
  >        concerns. After review, the solution should be perfect.
  > 6. Take all the responses from the Reviewer agents and summarize the issues and proposed
  >    solutions from high priority to least
  > 7. Ask the user how they'd like to proceed.
  > 8. Do not write any code or modify any files without permission.

## Phase 8 — Test coverage
- Extend the localization UI sweep beyond onboarding/paywall to the **main UI and Settings** (+
  scrolled Settings for subscription/tier rows). Add a **horizontal-overflow assertion** (a label
  whose frame extends past the screen edge is clipped) on every captured screen — a real automatable
  clipping proxy. Navigate locale-independently: accessibility **identifiers** (not localized
  labels) + coordinate fallbacks.
- **Right-to-left (RTL) locales (`ar`, `he`, `ur`): verify mirrored layout, not just strings.** Run
  the sweep at least once under an RTL locale and check: leading/trailing used instead of
  `.left`/`.right`, directional icons (chevrons, arrows, progress) mirror correctly, and text
  alignment follows `layoutDirection`. RTL screenshots go into the same visual review.
- **VoiceOver proxy:** an XCUITest asserting accessibility labels per locale is an automatable
  stand-in for VoiceOver output — in a localized run, assert the labels are the translated values,
  not English.
- **The home-screen widget and Share/Action extensions run out-of-process** — the app's UI-test
  target can't launch or drive them; review their localized layouts in their own host contexts.
- Limit to state honestly: frame-overflow is detectable; pixel-level ellipsis truncation *within* a
  frame still needs the screenshots for visual review.

## Phase 9 — Translation-quality validation (structure validated ≠ quality validated)
Everything above proves the *mechanics*; none of it proves the translations are *good*. Tiered,
cheapest first — each tier narrows what the next (more expensive) tier must look at:
1. **Automated linters** — glossary/term consistency across surfaces, placeholder/brand
   preservation, identical-to-English detection, length ratios.
2. **Cross-engine diff** (DeepL/Google) as triage — large divergence from machine translation means
   look closer, not that either is right.
3. **Independent LLM-as-judge** with a rubric, using a *different model* than the translator.
4. **In-context screenshot QA** per locale (the Phase 8 sweep artifacts).
5. **Targeted native human review** of everything flagged, plus high-stakes surfaces regardless
   (paywall, onboarding, tab names, errors) — prioritized by risk × market: morphologically rich
   locales (ru/uk/pl/cs/ar/he) and low-resource Indic locales first; human dollars on
   revenue-leading markets.

## Phase 10 — Ship
- **Localized package consumed remotely:** commit → tag a new version → push → bump the app's SPM
  dependency (`pbxproj` requirement + `Package.resolved`) → rebuild + re-verify (Phase 7.0).
- **App Store metadata is a SEPARATE effort** (sight-words): app info, version "What's New",
  keywords, IAP/subscription display names & descriptions — may require creating a new app version
  first. Automating via App Store Connect: serial ASC queue, ~500ms pre-call delay, honor `429`
  `Retry-After`, validate completeness before committing.

## Other considerations
Surfaces and behaviors not (yet) baked into the phases above — check whichever apply to the app:
- **Font/script rendering for the Indic set** — custom fonts usually lack Devanagari/Tamil/etc.
  glyphs, so those locales silently render in system-font fallback; tall scripts (Thai stacked
  diacritics, Devanagari) can clip in tight `lineLimit(1)` slots even when the text fits
  horizontally.
- **Bidirectional text composition** — an LTR brand name or number inside an Arabic/Hebrew sentence
  needs bidi isolation or punctuation visually scrambles; naive string interpolation is the usual
  culprit.
- **Measurement units** — metric vs imperial is a *region* choice, not a language one
  (`Measurement.FormatStyle`); 12/24-hour time follows the same trap.
- **Locale-aware collation and search** — sorting with `<` or filtering with plain `contains`
  breaks for diacritics and non-Latin scripts; use `localizedStandardCompare` and
  diacritic-insensitive predicates.
- **Language/region mismatch and fallback** — test device language `de` with region US (and vice
  versa); confirm catalog fallback behavior (`zh-HK` → `zh-Hant`; `pt` → which Portuguese?).
- **Speech synthesis** — if the app speaks, `AVSpeechSynthesizer` voice/language selection must
  follow locale, and TTS output of localized strings is its own review surface.
- **URLs and web content** — help/support/privacy links pointing at English-only pages; in-app
  HTML; share-sheet composed text and mailto subject lines.
- **Scheduled local notifications** — content is frozen at scheduling time, so notifications
  scheduled before a language change (or before localization shipped) fire in the old language
  until rescheduled; kin to the persisted-data trap (Phase 0).
- **Accessibility hints** — `.accessibilityHint` is a third channel alongside labels and values
  (Phase 0), with the same failure mode.

## Standing rules (this user)
- No force-unwrap, no `try?` (without explicit justification); no multiple trailing closures;
  `@Observable`/`@StateObject`; central colors/fonts.
- Build **only** via `drews-xcode-mcp` (never `xcodebuild`/`swift build` for Xcode projects; a bare SPM package may use `swift build` only as a compile check — it won't compile resources/catalogs).
- **Always build after changes and verify the final committed state builds** (Phase 7.0).
- Commit messages: **no** LLM credit / co-author lines; comments explain WHY not WHAT.

## One-line kickoff
> "Localize this app's user-facing strings into our App Store locale set per
> `LocalizationSuperPrompt.md`: recon every surface (SPM packages, extensions, config structs,
> `Text(verbatim:)`, models, a11y labels AND values) with a per-target catalog audit
> (`Localizable`/`InfoPlist`/`AppShortcuts` `.xcstrings` per target); fix locale *behavior* too
> (number input parsing, weekday arrays, `dateFormat`); make strings localizable (`bundle: .module`,
> plural variations + `%#@name@` compound counts, `.textCase` for casing, no all-specifier keys);
> build + translate the GLOSSARY first (one term per concept, app name = do-not-translate), then
> bulk-translate via parallel agents with a separate native per-locale REVIEW of EVERY batch (keep
> the reviewed/unreviewed ledger); apply minimal-diff with loss-checks; VERIFY key-match +
> specifier-safety + xcstringstool + the compiled bundle + pseudoloc (`-NSDoubleLocalizedStrings
> YES`) + an RTL runtime spot-check — and BUILD the final committed state via drews-xcode-mcp
> (clean + rebuild). After every phase: cross-LLM review (codex/agy; fresh claude fallback) briefed
> with the verbatim phase text, verify findings, recheck, then COMMIT the phase. At the end: TWO
> independent LLM reviews of the whole change set + recheck + stupid-check."

# Localization.md
Whenever possible, fetch the latest localization.md from the agent skills that can be exported from the currently-installed Xcode version by running "xcrun agent skills export ~/Downloads/xcode-agent-skills" and find the localization.md file within that hierarchy, currently the subpath is `swiftui-specialist/references/localization.md`.

The version that follows is from Xcode 27.0 developer beta 2.
# String Catalogs

Most projects localize through String Catalogs (`.xcstrings`). Each build syncs new strings from code into the catalog, but the catalog file must already exist — Xcode does not create one automatically. If a project already uses `.strings` or `.stringsdict` files, add new strings to the existing files rather than asking the user to migrate.

A project can use multiple String Catalogs and route strings to a specific one with the `tableName` parameter — useful when it makes sense to keep groups of strings separate (e.g., per feature or module).

```swift
Text("Explore", tableName: "Navigation",
     comment: "Tab bar item title for the Explore screen.")
```

# Bundle for Swift Packages and Frameworks

Apps, app extensions, and XPC services are their own main bundle, so the `bundle` parameter can be omitted. Frameworks and Swift packages need an explicit `bundle`; without one, SwiftUI looks up strings from `Bundle.main` and the lookup fails silently — the string appears unlocalized at runtime.

```swift
// AVOID: Inside a framework or Swift package, this searches the app's catalog.
Text("Save to Favorites")
```

```swift
// PREFER: #bundle resolves to the current target's bundle.
Text("Save to Favorites", bundle: #bundle,
     comment: "Button to bookmark a recipe.")
```

`#bundle` is the preferred form; `Bundle.module` and `Bundle(for: MyClass.self)` work but are older patterns.

# SwiftUI Views Localize String Literals Automatically

SwiftUI initializers that accept `LocalizedStringKey` (e.g., `Text`, `Button`, `.navigationTitle`) automatically treat string literals as localization keys. Do not wrap literals in `NSLocalizedString`, `String(localized:)`, or `LocalizedStringResource`.

```swift
// AVOID: Text already treats literals as LocalizedStringKey; wrapping
// also resolves the string eagerly, ignoring \.locale overrides.
Text(NSLocalizedString("start_workout", comment: ""))
Text(String(localized: "start_workout"))
```

```swift
// PREFER: Pass the string literal directly.
Text("start_workout")
```

Both opaque keys (`"start_workout"`) and natural-language strings (`"Start Workout"`) work as `LocalizedStringKey` values. Choose whichever convention the project uses consistently — with opaque keys, the source-language text is set in the String Catalog directly, not at the call site.

Use `Text(verbatim:)` to opt out of localization for a string literal — most often a debug label that interpolates a runtime value (e.g., `Text(verbatim: "Session: \(sessionID)")`), where the literal would otherwise be treated as a localization key. When the argument is already a `String` variable, `Text(value)` calls the `StringProtocol` overload and skips localization on its own — no `verbatim:` needed.

# Localizing Variables and Custom Types

When a `String` variable is passed to `Text`, the `StringProtocol` overload runs and the string is NOT localized. Wrapping the variable in `LocalizedStringKey(_:)` at the call site does not help either — Xcode cannot extract a literal from a runtime value, so the entry never lands in the catalog. To localize a value chosen from a known set of keys, model the set with a type that exposes `LocalizedStringResource`:

```swift
enum Category {
    case appetizers, mains, desserts
    var name: LocalizedStringResource {
        switch self {
        case .appetizers: "Appetizers"
        case .mains: "Mains"
        case .desserts: "Desserts"
        }
    }
}

Text(category.name)
```

When a view or view model exposes user-facing text, type the property as `LocalizedStringKey` or `LocalizedStringResource` instead of `String`. Every SwiftUI view that takes localized text accepts both, so deferring resolution costs nothing at the display site and preserves locale and bundle context end-to-end.

```swift
// AVOID: String properties lose localization context.
struct SectionHeader {
    let title: String
}
```

```swift
// PREFER: LocalizedStringResource keeps the string localizable.
struct SectionHeader {
    let title: LocalizedStringResource
}
```

# String Interpolation vs Concatenation

String interpolation preserves `LocalizedStringKey` and produces a format string in the catalog (e.g., `"Welcome, %@"`). Concatenation with `+` produces a `String` — the result is not localized.

```swift
// AVOID: + produces String, not LocalizedStringKey. Not localized.
Text("Error: " + statusMessage)
```

```swift
// PREFER: Interpolation preserves LocalizedStringKey.
Text("Error: \(statusMessage)")
```

Never glue separately localized fragments to form a sentence — word order varies across languages.

```swift
// AVOID: Sentence assembly breaks in languages with different word order.
Text(String(localized: "Created by")) + Text(" ") + Text(authorName)
```

```swift
// PREFER: A single string lets translators rearrange the structure.
Text("Created by \(authorName)")
```

# Casing

Bake the desired case into the string itself rather than transforming case at runtime via `.textCase(_:)`, `.localizedUppercase`, or `.localizedCapitalized`. A runtime transform forces the same casing decision across all translations, leaving translators no way to adjust per language.

```swift
// AVOID: forces the same casing on every translation.
Text("Section Header").textCase(.uppercase)

// PREFER: provide the desired case in the string itself.
Text("SECTION HEADER")
```

This applies to localized strings. Strings the user typed in should display as-is; you don't know what casing they intended. If a transform is unavoidable, prefer `.localizedUppercase` / `.localizedCapitalized`, which honor the user's locale (Turkish dotted/dotless I, German ß, etc.).

# Formatting Dates, Numbers, and Currencies

Use `Text`'s `format` parameter or `.formatted()` instead of `DateFormatter` or `NumberFormatter` with hardcoded format strings. Format styles adapt to the user's locale; hardcoded format strings do not. These overloads localize through the format style — they're not a bypass of localization, and the value itself doesn't produce a catalog entry. When the value is interpolated into a localized literal (e.g., `"Total: \(price, format: ...)"`), the surrounding literal still accepts a `comment:` as usual.

```swift
// AVOID: Hardcoded format does not adapt to locale.
let formatter = DateFormatter()
formatter.dateFormat = "MM/dd/yyyy"
Text(formatter.string(from: workout.date))
```

```swift
// PREFER: Format styles adapt to the user's locale automatically.
Text(workout.date, format: .dateTime.month().day().year())
```

Date field components (`.month()`, `.day()`, `.year()`) enable which fields appear; the locale determines output order — the chain order doesn't lock layout.

```swift
// AVOID: Hardcoded currency formatting.
Text("$\(product.price, specifier: "%.2f")")
```

```swift
// PREFER
Text(product.price, format: .currency(code: store.currencyCode))
```

For lists of strings, `Array.formatted()` inserts locale-correct separators and conjunctions instead of a hardcoded `joined(separator: ", ")`.

```swift
// AVOID
Text("Order: \(items.joined(separator: ", "))")
```

```swift
// PREFER
Text("Order: \(items.formatted())")
```

When `DateFormatter` is genuinely unavoidable, use `setLocalizedDateFormatFromTemplate(_:)` rather than assigning `dateFormat` directly — the template reorders fields per locale.

# Layout for Localization

Use `.leading` and `.trailing` instead of `.left` and `.right` — they flip for right-to-left locales; `.left` and `.right` don't.

```swift
// AVOID: .left does not flip for RTL languages.
Text(recipe.title)
    .frame(maxWidth: .infinity, alignment: .left)
```

```swift
// PREFER: .leading flips to the trailing edge in RTL locales.
Text(recipe.title)
    .frame(maxWidth: .infinity, alignment: .leading)
```

Do not hardcode frame widths or heights for text — translations vary in length and scripts vary in height. Use `ViewThatFits` when a layout might not fit longer translations.

```swift
// PREFER: ViewThatFits picks the first layout that fits.
ViewThatFits {
    HStack { actionButtons }
    VStack { actionButtons }
}
```

Use SwiftUI's text styles instead of fixed point sizes. Text styles let line height adapt per script; fixed point sizes can clip glyphs in tall scripts.

```swift
// AVOID: fixed point size locks line height.
Text("Welcome").font(.system(size: 17))

// PREFER: text styles let line height adapt per script.
Text("Welcome").font(.body)
```

# Reading the Current Locale

Use `@Environment(\.locale)` instead of `Locale.current` for locale-dependent logic in views — the environment respects preview overrides and per-view injection; `Locale.current` does not.

# String(localized:) Outside SwiftUI Views

When you need a localized `String` outside of SwiftUI views, use `String(localized:)`, not `NSLocalizedString`.

```swift
// AVOID
let title = NSLocalizedString("activity_summary", comment: "Dashboard header")
```

```swift
// PREFER
let title = String(localized: "activity_summary", comment: "Dashboard header")
```

Do not interpolate inside `NSLocalizedString` — Xcode extracts keys from literal strings at build time and cannot extract interpolated values. Use `String(localized:)` with interpolation instead; Xcode extracts the format string (e.g., `"reminder_body %@"`) and treats interpolated values as runtime arguments.

Prefer `String(localized:)` over `String(format:)` and `String.localizedStringWithFormat`. `String(format:)` always renders digits as 0–9 regardless of locale and is unsuitable for user-facing text; `String.localizedStringWithFormat` works when paired with `NSLocalizedString`, but `String(localized:)` is the modern API and the right default.

# LocalizedStringResource for Non-View Types

When a non-view type carries a user-facing string — a model object, a tip, a queued notification — use `LocalizedStringResource` instead of `String`. The string is resolved at display time, not creation time, so it honors the locale active when the value actually renders. Whenever a `String` would otherwise be passed between view models, modules, or into a view, `LocalizedStringResource` is the right type. Apply this when designing new types or changing user-facing text — don't sweep through existing `String` properties as part of unrelated edits.

```swift
// AVOID: Resolving at creation time loses the ability to display
// in a different locale later.
struct Tip {
    let headline: String
}
let tip = Tip(headline: String(localized: "Tip of the Day"))
```

```swift
// PREFER: LocalizedStringResource defers resolution to display time.
struct Tip {
    let headline: LocalizedStringResource
}
let tip = Tip(headline: "Tip of the Day")
```

# Comments for Translators

Add a `comment` describing the UI element and its purpose, especially for ambiguous strings. For interpolated strings, describe each placeholder by position — translators don't see Swift variable names.

```swift
// AVOID: "Edit" could be a noun or a verb — different translations.
Text("Edit")
```

```swift
// PREFER
Text("Edit", comment: "Toolbar button that enters editing mode for the list.")
```

```swift
// PREFER: refer to placeholders by position, not by Swift name.
Text("Completed \(count) of \(total)",
     comment: "Progress label — the first variable is finished items, the second is the total.")
```

Comments can also live in the String Catalog (per-string Comment field), equivalent to passing `comment:` at the call site — keep one source of truth per string.
