#!/usr/bin/env python3
"""Parse an ollama.com model page into a stable attribute line.

Reads page HTML on stdin, prints:

    usage|context|size|tags|updated|downloads|age_days

Prints "?|?|?|?|?|?|?" on empty or unparseable input rather than an empty or partial line.
ollama-watch diffs this string against a stored copy, so an empty result would compare
unequal to a populated one and fire a false "changed" alert on every network hiccup. An
all-unknown line compares equal to the next all-unknown line, so a run of failures stays
quiet.

TWO BUGS THIS FILE EXISTS BECAUSE OF, both found 2026-08-26:

1. SCRIPTS MUST BE STRIPPED BEFORE TEXT EXTRACTION. Ollama's pages carry inline
   JavaScript ahead of the content. Flattening tags without removing <script> first
   leaves several kilobytes of code in the text, which pushed the real content past the
   window an earlier version looked at, and — worse — let words like "tools" match
   inside JavaScript and produce capability tags for models that have none.

2. MULTI-SIZE PAGES HAVE NO USAGE BLOCK. A cloud model like kimi-k3 renders
   "Usage extra high / Context 1M tokens / Size 2.81T parameters". A locally-pullable
   family like qwen3.8 renders size variants (27b, 8b) and no usage block at all. The
   first version returned all-unknown for those and a caller then classified them as
   uninteresting. qwen3.8 was updated ONE WEEK ago with 829K downloads; treating it as
   noise was wrong. Hence `updated` and `downloads`, which every page carries, and which
   are the fields that actually answer "is this worth telling him about".
"""
import sys
import re
import html

USAGE_WORDS = ("extra high", "very high", "high", "medium", "low")
CAPABILITY_TAGS = ("vision", "tools", "thinking", "cloud", "embedding")
UNKNOWN = "?|?|?|?|?|?|?"


def flatten(raw: str) -> str:
    """HTML to plain text, with script and style content removed first."""
    t = re.sub(r"(?is)<script.*?</script>", " ", raw)
    t = re.sub(r"(?is)<style.*?</style>", " ", t)
    t = re.sub(r"(?is)<noscript.*?</noscript>", " ", t)
    t = re.sub(r"<[^>]+>", " ", t)
    t = html.unescape(t)
    return re.sub(r"\s+", " ", t).strip()


def parse(raw: str) -> str:
    if not raw or not raw.strip():
        return UNKNOWN
    text = flatten(raw)
    if not text:
        return UNKNOWN

    usage = "?"
    for word in USAGE_WORDS:
        if re.search(r"Usage\s+" + word + r"\b", text, re.I):
            usage = word
            break

    m = re.search(r"Context\s+([\d.]+\s*[KMG]?)\s*tokens", text, re.I)
    context = re.sub(r"\s+", "", m.group(1)) if m else "?"

    m = re.search(r"Size\s+([\d.]+\s*[KMGTB]+)\s*parameters", text, re.I)
    size = re.sub(r"\s+", "", m.group(1)) if m else "?"

    # Locally-pullable families advertise variants instead: "27b", "8b", "70b".
    if size == "?":
        variants = re.findall(r"\b(\d+(?:\.\d+)?[bB])\b", text[:1200])
        seen = []
        for v in variants:
            v = v.lower()
            if v not in seen:
                seen.append(v)
        if seen:
            size = ",".join(seen[:4])

    tags = [t for t in CAPABILITY_TAGS if re.search(r"\b" + t + r"\b", text, re.I)]

    m = re.search(r"Updated\s+(.{1,20}?\bago)\b", text, re.I)
    updated = re.sub(r"\s+", " ", m.group(1)).strip() if m else "?"

    m = re.search(r"([\d.]+[KMB]?)\s+Downloads", text, re.I)
    downloads = m.group(1) if m else "?"

    # Age as a plain integer so a shell caller can compare it without parsing English.
    # "is this recent" is the question that decides whether a model is worth a message,
    # and making the caller regex "1 week ago" out of a display string is how that check
    # ends up subtly wrong in two places.
    age_days = age_in_days(updated)

    if usage == "?" and context == "?" and size == "?" and updated == "?" and downloads == "?":
        return UNKNOWN

    return "%s|%s|%s|%s|%s|%s|%s" % (
        usage, context, size, ",".join(tags) or "-", updated, downloads, age_days,
    )


def age_in_days(updated: str) -> str:
    """'9 hours ago' -> '0'; '1 week ago' -> '7'; '2 years ago' -> '730'. '?' if unknown."""
    if not updated or updated == "?":
        return "?"
    m = re.match(r"(?:about\s+)?(\d+)\s+(hour|day|week|month|year)s?\s+ago", updated, re.I)
    if not m:
        # "yesterday", "a day ago" and similar all mean recent.
        return "1" if re.search(r"hour|yesterday|today|minute", updated, re.I) else "?"
    n, unit = int(m.group(1)), m.group(2).lower()
    return str(n * {"hour": 0, "day": 1, "week": 7, "month": 30, "year": 365}[unit])


if __name__ == "__main__":
    print(parse(sys.stdin.read()))
