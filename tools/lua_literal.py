# DUPLICATE-lua_literal: a copy of NAGHelperElectron sidecar/helper/lua_literal.py at a384e8fe (the NAG app runs the same
# check on the same bytes before it writes Data/NAGDeathData.lua). Keep the two the same.
"""Is a downloaded Lua file nothing but data? (NAG-Mastermind 2026-10-20)

The app drops server files into addon folders (the Death Radar's NAGDeathData.lua, the immunity seed) and the game
runs them on every client. A sha256 that matches meta.json proves only that two reads of the same public route
agree, not what the file does, so before a write the body must parse as ONE assignment of a table literal:

    file   := Name("global") "=" table
    table  := "{" [field {"," field} [","]] "}"          at most MAX_DEPTH deep
    field  := "[" (number | string) "]" "=" value | Name "=" value | value
    value  := number | string | "true" | "false" | table
    number := -?[0-9]+(.[0-9]+)?
    string := "..." of at most MAX_STRING bytes, no backslash, quote or line break inside

Whitespace between tokens and nothing else: no comment, call, parenthesis, operator, "..", long string, bare name
as a value or second statement. A pure function: callers keep their own prefix and size checks.
"""
import re

MAX_DEPTH = 8
MAX_STRING = 64

_TOKEN = re.compile(rb'[ \t\r\n]*(?:(?P<name>[A-Za-z_][A-Za-z0-9_]*)|(?P<num>-?[0-9]+(?:\.[0-9]+)?)'
                    rb'|"(?P<str>[^"\\\r\n]*)"|(?P<punct>[][{}=,]))')
_KEYWORDS = {b"and", b"break", b"do", b"else", b"elseif", b"end", b"false", b"for", b"function", b"if", b"in",
             b"local", b"nil", b"not", b"or", b"repeat", b"return", b"then", b"true", b"until", b"while"}
_END = (None, None)


def _tokens(body):
    """[(kind, bytes)], or None when anything but a token or whitespace is in the body."""
    out, pos = [], 0
    while True:
        m = _TOKEN.match(body, pos)
        if m is None:
            return out if not body[pos:].strip(b" \t\r\n") else None
        kind = m.lastgroup
        if kind == "str" and len(m.group("str")) > MAX_STRING:
            return None
        out.append((kind, m.group(kind)))
        pos = m.end()


def lua_table_literal_ok(body: bytes, global_name: str) -> bool:
    """True when `body` is `<global_name> = {...}` under the grammar above, and nothing else."""
    tokens = _tokens(body)
    if tokens is None:
        return False
    i = 0

    def tok(k=0):
        return tokens[i + k] if i + k < len(tokens) else _END

    def value(depth):
        nonlocal i
        kind, text = tok()
        if kind in ("num", "str") or (kind == "name" and text in (b"true", b"false")):
            i += 1
            return True
        return table(depth + 1)

    def field(depth):
        nonlocal i
        if tok() == ("punct", b"["):
            if tok(1)[0] not in ("num", "str") or tok(2) != ("punct", b"]") or tok(3) != ("punct", b"="):
                return False
            i += 4
        elif tok()[0] == "name" and tok(1) == ("punct", b"="):
            if tok()[1] in _KEYWORDS:
                return False
            i += 2
        return value(depth)

    def table(depth):
        nonlocal i
        if depth > MAX_DEPTH or tok() != ("punct", b"{"):
            return False
        i += 1
        while tok() != ("punct", b"}"):
            if not field(depth):
                return False
            if tok() == ("punct", b","):
                i += 1
            elif tok() != ("punct", b"}"):
                return False
        i += 1
        return True

    if tok() != ("name", global_name.encode()) or tok(1) != ("punct", b"="):
        return False
    i = 2
    return table(1) and i == len(tokens)
