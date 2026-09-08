#!/usr/bin/env python3
"""Decode a single literal Bash word without evaluating shell code.

The safety hooks need to recognize a command spelling such as k$'\\151'll as
``kill``.  This deliberately supports only literal quoting and escaping.  Any
parameter, command, arithmetic, or process expansion is rejected so callers
can fail closed instead of accidentally evaluating command text.
"""

import sys


def ansi_escape(text: str, index: int) -> tuple[str, int]:
    if index >= len(text):
        raise ValueError("trailing ANSI-C escape")
    char = text[index]
    simple = {
        "a": "\a", "b": "\b", "e": "\x1b", "f": "\f", "n": "\n",
        "r": "\r", "t": "\t", "v": "\v", "\\": "\\", "'": "'",
        '"': '"', "?": "?",
    }
    if char in simple:
        return simple[char], index + 1
    if char in "01234567":
        end = index
        while end < len(text) and end < index + 3 and text[end] in "01234567":
            end += 1
        return chr(int(text[index:end], 8)), end
    if char == "x":
        end = index + 1
        while end < len(text) and end < index + 3 and text[end] in "0123456789abcdefABCDEF":
            end += 1
        if end == index + 1:
            raise ValueError("empty hex escape")
        return chr(int(text[index + 1:end], 16)), end
    raise ValueError("unsupported ANSI-C escape")


def literal_word(word: str) -> str:
    output: list[str] = []
    index = 0
    while index < len(word):
        char = word[index]
        if char == "\\":
            if index + 1 >= len(word):
                raise ValueError("trailing backslash")
            output.append(word[index + 1])
            index += 2
        elif char == "'":
            end = word.find("'", index + 1)
            if end < 0:
                raise ValueError("unterminated single quote")
            output.append(word[index + 1:end])
            index = end + 1
        elif char == '"':
            end = word.find('"', index + 1)
            if end < 0:
                raise ValueError("unterminated double quote")
            quoted = word[index + 1:end]
            if "$" in quoted or "`" in quoted:
                raise ValueError("dynamic double-quoted expansion")
            output.append(quoted.replace("\\\"", '"').replace("\\\\", "\\"))
            index = end + 1
        elif char == "$":
            if index + 1 < len(word) and word[index + 1] == "'":
                index += 2
                while index < len(word):
                    if word[index] == "'":
                        index += 1
                        break
                    if word[index] == "\\":
                        decoded, index = ansi_escape(word, index + 1)
                        output.append(decoded)
                    else:
                        output.append(word[index])
                        index += 1
                else:
                    raise ValueError("unterminated ANSI-C quote")
            elif index + 1 < len(word) and word[index + 1] == '"':
                end = word.find('"', index + 2)
                if end < 0:
                    raise ValueError("unterminated locale quote")
                output.append(word[index + 2:end])
                index = end + 1
            else:
                raise ValueError("dynamic expansion")
        elif char == "`" or (char in "<>" and index + 1 < len(word) and word[index + 1] == "("):
            raise ValueError("command or process substitution")
        else:
            output.append(char)
            index += 1
    return "".join(output)


try:
    print(literal_word(sys.argv[1]))
except (IndexError, ValueError) as error:
    print(f"shell_word_literal: {error}", file=sys.stderr)
    raise SystemExit(2)
