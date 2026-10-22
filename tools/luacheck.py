#!/usr/bin/env python
"""Syntax-check Lua resource files without launching the game.

The game's own validator (deploy.ps1 -Validate) is the authority, but it costs a
process launch, needs the game closed, and has proved flaky. This compiles each
file with a real Lua front end instead, which catches the whole class of error
that otherwise shows up in-game as "my constructions are missing from the menu".

It only checks that the file *parses*, plus two things a parse cannot see: a
bare name that is never a local in the file, and a name used **above** the
`local` that declares it. Both compile and then read a nil global in the game -
the second one cost a deploy-and-restart cycle on 2026-10-13, when a constant
moved below the function that reads it.

It knows nothing about the game's globals, so it cannot tell you a resource name
is wrong or that `log.message` exists - it is a syntax gate, not a validator.

    python tools/luacheck.py <file-or-dir> [...]

Requires `lupa` (pip install lupa).
"""
import os
import re
import sys

try:
    import lupa
except ImportError:
    sys.exit("lupa not installed - run: python -m pip install lupa")

# lupa exposes whichever Lua it was built against; any of them will parse the
# 5.x syntax the game uses.
LuaRuntime = lupa.LuaRuntime


def iter_lua(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                for f in sorted(files):
                    if f.endswith(".lua"):
                        yield os.path.join(root, f)
        else:
            yield p


#: Globals the game provides to a resource script. Anything called that is
#: neither one of these nor a local defined earlier in the file is almost
#: certainly a typo or a deleted definition.
GAME_GLOBALS = {
    "require", "ug_require", "addModifier", "resolve", "data", "pcall", "type",
    "tostring", "tonumber", "ipairs", "pairs", "table", "string", "math", "os",
    "log", "api", "game", "print", "assert", "error", "select", "next",
    "setmetatable", "getmetatable", "rawget", "rawset", "unpack", "_",
    # Collaborators the engine passes *as arguments* to a callback rather than
    # as globals: a module's updateFn signature is
    # (captureParams, result, transform, tag, slotId, addModel, constrParams).
    # PARAMS_RE below is meant to pick these up from the signature, but listing
    # the known ones is deterministic and costs nothing.
    "addModel", "addModelFn", "addModelLocal",
}

DEF_RE = re.compile(r"\blocal\s+function\s+([A-Za-z_]\w*)|\blocal\s+([A-Za-z_]\w*)\s*=")
CALL_RE = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\s*\(")
PARAMS_RE = re.compile(r"\bfunction\s*(?:[A-Za-z_][\w.:]*)?\s*\(([^)]*)\)")
#: SCREAMING_CASE identifiers read as values, e.g. `{ id = DECK }`.
CONST_RE = re.compile(r"(?<![\w.:])([A-Z][A-Z0-9_]{2,})(?!\s*=[^=])(?![\w(])")
LUA_KEYWORDS = frozenset((
    "function", "if", "while", "for", "return", "and", "or", "not", "end",
    "then", "do", "elseif", "else", "in", "local", "nil", "true", "false",
    "break", "repeat", "until", "goto",
))


def check_calls(path, src):
    """Flag calls to bare names that are never defined as a local in the file.

    A Lua chunk compiles happily with a call to a nil global; it only fails at
    runtime, inside the game, as "attempt to call a nil value". That is exactly
    the breakage an editing slip produces when it removes a `local function`
    while leaving its callers behind - and the compiler above cannot see it.
    """
    stripped = re.sub(r"--\[\[.*?\]\]", " ", src, flags=re.S)
    stripped = re.sub(r"--[^\n]*", " ", stripped)
    stripped = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', stripped)
    stripped = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", stripped)

    # Where each name is first declared, not just whether it is. A local is
    # only an upvalue for code *below* it: a function that reads a constant
    # declared further down the file compiles fine and reads a nil global at
    # runtime, which is a broken rebuild in the game and nothing here.
    defined = {}

    def declare(name, pos):
        line = stripped[:pos].count("\n") + 1
        if name not in defined or line < defined[name]:
            defined[name] = line

    for m in DEF_RE.finditer(stripped):
        declare(m.group(1) or m.group(2), m.start())

    # Function parameters count as definitions too. Callbacks handed to the
    # engine take their collaborators as arguments - a module's updateFn is
    # given `addModel` - and without this every such call reads as undefined.
    for m in PARAMS_RE.finditer(stripped):
        for part in m.group(1).split(","):
            part = part.strip()
            if re.match(r"^[A-Za-z_]\w*$", part):
                declare(part, m.start())

    missing = {}

    def use(name, pos, how):
        if name in GAME_GLOBALS or name in LUA_KEYWORDS:
            return
        line = stripped[:pos].count("\n") + 1
        if name not in defined:
            missing.setdefault(name, (line, how, None))
        elif defined[name] > line:
            missing.setdefault(name, (line, how, defined[name]))

    for m in CALL_RE.finditer(stripped):
        use(m.group(1), m.start(), "calls")

    # SCREAMING_CASE names read as values, not calls. A deleted `local DECK =`
    # leaves `{ id = DECK }` compiling fine and then failing in the game as
    # "Required key not found: key='id'" - a nil that travels. Only this naming
    # convention is checked, because a lowercase bare name has too many
    # legitimate reasons to be a global.
    for m in CONST_RE.finditer(stripped):
        use(m.group(1), m.start(), "reads")

    for name, (line, how, declared) in sorted(missing.items(),
                                              key=lambda kv: kv[1][0]):
        if declared is None:
            print("WARN %s:%d %s '%s', which is not a local in this file"
                  % (path, line, how, name))
        else:
            print("WARN %s:%d %s '%s' before its local, declared at line %d"
                  % (path, line, how, name, declared))
    return not missing


def main(argv):
    if not argv:
        sys.exit(__doc__)

    lua = LuaRuntime()
    # Do the load inside Lua and return only the error, so there is no
    # multiple-return-value unpacking to get wrong on the Python side.
    compile_err = lua.eval("""
        function(src, name)
            local fn, err = load(src, name)
            if fn then return nil end
            return err or "unknown error"
        end
    """)

    failed = 0
    checked = 0
    for path in iter_lua(argv):
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        checked += 1
        err = compile_err(src, "@" + path)
        if err is not None:
            failed += 1
            print("FAIL %s\n     %s" % (path, err))
        elif not check_calls(path, src):
            failed += 1
        else:
            print("ok   %s" % path)

    print("\n%d checked, %d failed" % (checked, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
