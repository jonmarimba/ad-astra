#!/usr/bin/env python3
"""Decide whether a candidate model is a real upgrade over what a host already has.

Usage:
    version_gate.py <candidate-term> < list-of-models-on-host

Prints one of:
    new        — nothing in this family is on the host
    upgrade X  — the host has version X and the candidate is numerically newer
    redundant X— the host already has version X, equal or newer

Exit status is always 0. The caller reads the word.

WHY THIS EXISTS. Ambrosio's redundancy check compared only the leading alphabetic prefix of
a family name. On 2026-08-26 the trending scan found GLM-5.3-Flash, saw that "glm" was already
on the M5, and skipped it — what the M5 actually held was glm-4.7-flash. A jump of two major
versions was reported as "not obviously new". The prefix check was right to exist (it caught
Nemotron-3-Nano being dead weight beside Nemotron-3.5-Lightning on 2026-08-14) and wrong to
stop at the prefix.

The comparison is deliberately numeric and shallow. It reads the first version number that
follows the family prefix and compares component by component, so 5.3 beats 4.7 and 3.10 beats
3.9. It does not understand names like "flash", "pro" or "preview", and it should not pretend
to: a model that carries no version number at all reads as unknown, and unknown never suppresses.
Suppressing on a guess is the failure this file was written to end.
"""
import sys


def family_prefix(term):
    """Leading letters of a family term. 'GLM-5.3-Flash' -> 'glm'."""
    letters = []
    for ch in term.lower():
        if not ch.isalpha():
            break
        letters.append(ch)
    return "".join(letters)


def version_after_prefix(name, prefix):
    """First version number following the prefix, as a tuple. None when there isn't one.

    'glm-4.7-flash' with prefix 'glm' -> (4, 7).  'qwen3.8' -> (3, 8).
    A trailing size like '35b' is not a version and must not be read as one, which is why
    scanning starts only after the prefix and stops at the first non-version character.
    """
    low = name.lower()
    at = low.find(prefix)
    if at < 0:
        return None
    i = at + len(prefix)
    while i < len(low) and not low[i].isdigit():
        # Skip one separator only. Letters beyond a separator mean a different family
        # member ('glm-air'), not a version.
        if low[i] in "-_. /:":
            i += 1
            continue
        return None
    digits = []
    while i < len(low) and (low[i].isdigit() or low[i] == "."):
        digits.append(low[i])
        i += 1
    if i < len(low) and low[i].isalpha() and not digits:
        return None
    text = "".join(digits).strip(".")
    if not text:
        return None
    parts = []
    for chunk in text.split("."):
        if chunk.isdigit():
            parts.append(int(chunk))
    return tuple(parts) or None


def decide(term, host_models):
    prefix = family_prefix(term)
    if not prefix:
        return "new"
    candidate = version_after_prefix(term, prefix)
    best = None
    best_name = ""
    seen_family = False
    for name in host_models:
        if prefix not in name.lower():
            continue
        seen_family = True
        have = version_after_prefix(name, prefix)
        if have is None:
            continue
        if best is None or have > best:
            best, best_name = have, name.strip()
    if not seen_family:
        return "new"
    if candidate is None or best is None:
        # Family is present but one side carries no version. Unknown never suppresses.
        return "upgrade %s" % (best_name or "unversioned")
    if candidate > best:
        return "upgrade %s" % best_name
    return "redundant %s" % best_name


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("usage: version_gate.py <candidate-term> < models-on-host\n")
        sys.exit(64)
    print(decide(sys.argv[1], sys.stdin.read().splitlines()))
