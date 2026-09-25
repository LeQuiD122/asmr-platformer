"""Structural checks for the Luau sources. Plain Python, no Blender, no interpreter.

    python blender/check_lua.py

There is no Luau available here and nothing syncs to Studio, so a mistake in these files
is invisible until it is pasted in and played. Two kinds have actually happened on this
project, both silent, and both are cheap to catch textually:

1. A FILE-SCOPE `local function` referenced above its own declaration. Lua resolves that
   to a GLOBAL of the same name, which is nil -- it compiles clean and fails only when
   the line runs. It bit `remember` in DeformationRenderer, and again when `attachShell`
   was moved above the mesh helpers in ChunkBuilder. Position in the file is the whole
   bug, so a textual check is exactly the right tool: a closure written above the
   declaration captures the nil global no matter how late it is called.

2. Unbalanced blocks. An `end` too few or too many shifts everything after it into the
   wrong scope, and the error Studio reports points at the end of the file rather than
   at the edit that caused it.
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto",
    "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
    "until", "while", "continue", "export", "type", "self",
}



# A type annotation on a DOTTED name, e.g. `Module.field: {string} = {}`.
#
# Luau allows type annotations only on `local` declarations. On an assignment to a table
# field the parser reads `Module.field:` as the start of a method definition and dies on
# whatever follows -- and it is a COMPILE error, so the module fails to load entirely and
# takes every requirer down with it. That is exactly the kind of failure this file exists to
# catch without a Studio round trip, and it slipped through once already.
ANNOTATED_FIELD = re.compile(r"^\s*[A-Za-z_][\w.]*\.[A-Za-z_]\w*\s*:\s*[^=]*=")


def check_annotated_fields(path, lines):
    problems = []
    for number, raw in enumerate(lines, 1):
        line = raw.split("--")[0]
        if line.lstrip().startswith(("local ", "function ")):
            continue
        if ANNOTATED_FIELD.match(line):
            problems.append(
                f"{path.name}:{number}  type annotation on a dotted name -- Luau only allows "
                f"one on a `local`. Declare it local, then assign."
            )
    return problems

def strip_noise(text):
    """Blank out comments and string bodies, preserving line structure."""
    out = []
    i, n = 0, len(text)
    while i < n:
        two = text[i:i + 2]
        if two == "--":
            block = re.match(r"--\[(=*)\[", text[i:])
            if block:
                closer = "]" + "=" * len(block.group(1)) + "]"
                end = text.find(closer, i)
                end = n if end < 0 else end + len(closer)
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
            continue
        if text[i] in "\"'":
            quote = text[i]
            j = i + 1
            while j < n and text[j] != quote:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
            continue
        block = re.match(r"\[(=*)\[", text[i:])
        if block:
            closer = "]" + "=" * len(block.group(1)) + "]"
            end = text.find(closer, i)
            end = n if end < 0 else end + len(closer)
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


# A STRING LEFT OPEN AT THE END OF A LINE.
#
# Lua has no multi-line quoted string: a double quote that is not closed before the newline
# is a compile error, and the symptom in Studio is the module failing to load with "Malformed
# string" followed by a second, useless error from whatever required it.
#
# It is a GENERATED-CODE failure rather than a typed one. Every Luau file here is written by a
# Python patch script, and a newline escape that survives one layer of quoting too few arrives
# in the file as a real line break in the middle of a string literal. That has happened twice,
# and neither the block counter nor the declaration checker noticed either time: the braces
# still balance and every name is still declared.
def check_comment_continuations(path, lines):
    """A comment paragraph whose later lines lost their `--`.

    THIS IS A SYNTAX ERROR THAT LOOKS LIKE A COMMENT. A four-line explanation where only the
    first line is marked leaves three lines of English sitting in the middle of a table, and
    Luau reports it far from the cause -- the real message was "Expected '}' to close '{' at
    line 419, got 'not'", pointing at a table that was perfectly fine.

    Nothing else here catches it. Block balancing counts keywords and finds them balanced;
    use-before-declaration sees no declarations. The file simply does not compile, and the
    first thing that knows is Studio.

    The rule is narrow on purpose: a line is suspect only if the line ABOVE it is a comment,
    it is not itself a comment, it has no `=` or `(` to make it a statement, and it reads as
    prose -- starting with a lowercase word. Anything looser starts flagging real code.
    """
    problems = []
    for index, line in enumerate(lines):
        if index == 0:
            continue
        body = line.strip()
        above = lines[index - 1].strip()
        if not body or not above.startswith("--"):
            continue
        if body.startswith("--") or body.startswith("]]"):
            continue
        # A statement has one of these; a sentence very rarely does before its first space.
        head = body.split(" ")[0]
        if "=" in body or "(" in body or ")" in body or body.endswith(",") or body.endswith("{"):
            continue
        # KEYWORDS THAT CAN BEGIN A STATEMENT, and only those.
        #
        # The first list here included `not`, `and`, `or`, `then` and `nil` as well -- and the
        # broken line that had just reached Studio began with `not`, so the check passed on the
        # exact bug it was written for. Those words are operators and values: they appear
        # inside expressions and can never open a statement, so a line starting with one is
        # prose every time.
        if head in ("if", "end", "return", "local", "for", "while", "do", "else", "elseif",
                "repeat", "break", "continue", "function", "type", "export"):
            continue
        if head[:1].islower() and head.isalpha():
            problems.append(
                "  %s:%d  '%s...' follows a comment but is not one -- a comment paragraph "
                "lost its '--' here, which Luau reports as a syntax error somewhere else"
                % (path.name, index + 1, body[:44]))
    return problems


def check_unterminated_strings(path, lines):
    problems = []
    for number, line in enumerate(lines, start=1):
        if line.lstrip().startswith("--"):
            continue
        count, escaped = 0, False
        for char in line:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                count += 1
        if count % 2:
            problems.append(
                f"{path.name}:{number}  a double-quoted string is still open at the end of "
                f"this line. Lua strings cannot span lines, so this file will not compile: "
                f"{line.strip()[:70]}")
    return problems


def check_use_before_declaration(path, clean):
    """File-scope `local` NAME -- function or variable -- used on an earlier line.

    VARIABLES COUNT, and for a long time this only checked functions. That gap hid four
    live bugs at once: HubService declared `inRun` and `modeNotifier` a thousand lines
    below the code that read them, and UIService did the same with `chillBoardEnabled`
    and `tabTag`.

    Luau resolves a name where it is written. A read above the `local` does not see it
    and compiles to a GLOBAL instead, so the read yields nil and a write creates a global
    the real local never sees. Nothing warns about any of it: `if ... and modeNotifier
    then` is valid code that is simply always false, which is why the mode readout in the
    corner sat on Chill for four rounds. A function is only the case that fails loudly.
    """
    problems = []
    declared = {}
    for m in re.finditer(r"^local function ([A-Za-z_]\w*)", clean, re.M):
        declared.setdefault(m.group(1), clean.count("\n", 0, m.start()) + 1)
    # Plain file-scope variables: `local a`, `local a, b = ...`, `local a: T = ...`.
    for m in re.finditer(r"^local (?!function\b)([^\n=]+?)\s*(?:=|$)", clean, re.M):
        line = clean.count("\n", 0, m.start()) + 1
        # CUT AT THE FIRST COLON, then split. Splitting on commas first tore the TYPE
        # apart instead of the name list: `local f: ((a: number, mode: string) -> ())?`
        # yielded "mode" and "count" as though they were declarations of their own, and
        # the checker then reported every ordinary use of those words in the file.
        # Everything left of the first colon is names; everything right of it is a type.
        for part in m.group(1).split(":")[0].split(","):
            name = part.strip()
            if re.fullmatch(r"[A-Za-z_]\w*", name):
                declared.setdefault(name, line)

    # EVERY local of that name, at any indentation. A use above the file-scope `local` is
    # perfectly fine when an inner scope declared its own -- ChunkProps has a `local
    # assets` inside a function and another at file scope, and the inner one is a
    # different variable that shadows nothing. Only a use with NO local of that name
    # anywhere before it is reading a global.
    anywhere = {}
    for m in re.finditer(r"^[ \t]*local (?:function )?([A-Za-z_]\w*)", clean, re.M):
        anywhere.setdefault(m.group(1), []).append(clean.count("\n", 0, m.start()) + 1)
    # A plain `local NAME` before the function is a deliberate forward declaration and
    # makes the name visible from that point on, so it moves the line that counts.
    for name in list(declared):
        for m in re.finditer(rf"^local {name}\b(?!\s*function)", clean, re.M):
            declared[name] = min(declared[name], clean.count("\n", 0, m.start()) + 1)

    for name, decl_line in declared.items():
        for m in re.finditer(rf"(?<![\w.:]){name}\b", clean):
            line = clean.count("\n", 0, m.start()) + 1
            if line < decl_line and not any(
                    d <= line for d in anywhere.get(name, [])):
                problems.append(
                    f"  {path.name}:{line}  '{name}' used before its declaration on "
                    f"line {decl_line} -- this resolves to a nil GLOBAL"
                )
                break
    return problems


def check_block_balance(path, clean):
    """Openers against `end`, tracking the constructs that do not take one.

    The subtlety is Luau's if-then-else EXPRESSION (`local x = if a then b else c`),
    which this codebase uses constantly and which takes no `end`. Counting those as
    openers reports every file as unbalanced.

    Neither the `if`'s position on its line nor its own line's ending separates the two,
    and both were tried. A long if-expression WRAPS, so its `if` can begin a line just
    like a statement's; and a statement's condition can wrap too, putting its `then` on
    a later line. What actually distinguishes them is what follows the MATCHING `then`:
    a statement ends the line there (or closes on it with `end`), while an expression
    carries its value on past it.
    """
    tokens = [(m.start(), m.group()) for m in re.finditer(r"\b[a-z]+\b", clean)]

    def statement_if(then_pos):
        """True when the `then` at `then_pos` ends its line, or closes on it."""
        eol = clean.find("\n", then_pos)
        rest = clean[then_pos + 4:eol if eol >= 0 else len(clean)]
        return not rest.strip() or re.search(r"\bend\b", rest) is not None

    depth = 0
    expect_do = 0  # `for`/`while` already counted; their `do` must not count again
    for index, (pos, word) in enumerate(tokens):
        if word == "if":
            # `elseif` never matches: there is no word boundary inside it.
            nxt = next((p for p, w in tokens[index + 1:] if w == "then"), None)
            if nxt is not None and statement_if(nxt):
                depth += 1
        elif word == "function":
            depth += 1
        elif word in ("for", "while"):
            depth += 1
            expect_do += 1
        elif word == "repeat":
            depth += 1
        elif word == "do":
            if expect_do > 0:
                expect_do -= 1
            else:
                depth += 1
        elif word in ("end", "until"):
            depth -= 1
            if depth < 0:
                line = clean.count("\n", 0, pos) + 1
                return [f"  {path.name}:{line}  one '{word}' too many"]
    if depth != 0:
        return [f"  {path.name}  ends the file {depth} block(s) open"]
    return []


# Luau allows at most 200 locals LIVE AT ONCE in one function, and a module's MAIN CHUNK is a
# function like any other. Past that it fails at COMPILE time -- "Out of local registers when
# trying to allocate x: exceeded limit 200" -- which takes the whole module and everything
# requiring it down at once, and the error names whichever local happened to be the straw.
#
# DeformationRenderer hit this twice while the creamy keyboard was being added, and a third time
# with the keypads' capacitor and spring.
#
# LIVE, NOT DECLARED AT THE TOP. A local inside a `do`, `if`, `for`, `while` or `repeat` block
# counts for as long as the block runs, on top of every local of its function already in scope,
# and so do a `for` loop's variables and a function's parameters. This check used to count only
# `local` at indentation zero. That passed DeformationRenderer at 188 while Studio refused it: the
# keypad section was a bare do-block, 205 locals were live inside it, and the module failed to
# load at `for _, found in ...`. Counted as below, the check names that line and that `_`.
#
# Only a FUNCTION body starts a new 200. See the note above the creamy keyboard in
# DeformationRenderer for how that file's sections are written because of it.
REGISTER_LIMIT = 200
REGISTER_WARN = 178

LOCALS_TOKEN = re.compile(
    r"[A-Za-z_]\w*|\d[\w.]*|\.\.\.|\.\.=|//=|\.\.|==|~=|<=|>=|\+=|-=|\*=|/=|%=|\^=|//|->|::|\S")
# Tokens an `if` can follow only as an EXPRESSION: `local x = if a then b else c` has no `end`, and
# taking it for a statement would close a block early.
IF_EXPRESSION_AFTER = {
    "=", "(", "[", "{", ",", "return", "and", "or", "not", "..", "+", "-", "*", "/", "//", "%", "^",
    "#", "==", "~=", "<", ">", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "^=", "..=", "//=", "in",
    "until",
}


def code_with_strings_kept(text):
    """Comments blanked and each string literal replaced by one placeholder word, newlines kept.

    strip_noise blanks strings to nothing, which suits the checks above and not this one: after
    `local texture = "..."` an `if` on the next line would read as `local texture = if ...`.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("--", i):
            block = re.match(r"--\[(=*)\[", text[i:])
            if block:
                closer = "]" + "=" * len(block.group(1)) + "]"
                end = text.find(closer, i)
                end = n if end < 0 else end + len(closer)
            else:
                end = text.find("\n", i)
                end = n if end < 0 else end
            out.append(re.sub(r"[^\n]", " ", text[i:end]))
            i = end
            continue
        if text[i] in "\"'`":
            quote = text[i]
            j = i + 1
            while j < n and text[j] != quote and not (quote != "`" and text[j] == "\n"):
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(" __str__ " + re.sub(r"[^\n]", "", text[i:j]))
            i = j
            continue
        block = re.match(r"\[(=*)\[", text[i:])
        if block:
            closer = "]" + "=" * len(block.group(1)) + "]"
            end = text.find(closer, i)
            end = n if end < 0 else end + len(closer)
            out.append(" __str__ " + re.sub(r"[^\n]", "", text[i:end]))
            i = end
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def peak_live_locals(text):
    """The most locals live at once in any one function of a file, where that happens, and the first
    local that would be allocated with REGISTER_LIMIT already live, as (line, name), or None.
    Returns (peak, peak_line, over, lost) where `lost` is the line the block structure stopped
    making sense at, or None."""
    tokens = []
    for number, line in enumerate(code_with_strings_kept(text).split("\n"), 1):
        for match in LOCALS_TOKEN.finditer(line):
            tokens.append((match.group(0), number))

    def new_frame():
        # scopes[0] is the function's own; every open block adds one, with the keyword that opened it.
        return {"scopes": [["function", 0]], "loop": None, "ifexpr": []}

    frames = [new_frame()]
    peak, peak_line, over = 0, 0, None
    previous, consumed = None, False

    def allocate(names, line):
        nonlocal peak, peak_line, over
        scopes = frames[-1]["scopes"]
        for name in names:
            live = sum(scope[1] for scope in scopes)
            if live >= REGISTER_LIMIT and over is None:
                over = (line, name)
            scopes[-1][1] += 1
            if live + 1 > peak:
                peak, peak_line = live + 1, line

    def parameters(start):
        """Names in the parameter list of the function whose `function` keyword is at `start`."""
        cursor = start + 1
        method = False
        while cursor < len(tokens) and tokens[cursor][0] != "(":
            method = method or tokens[cursor][0] == ":"
            cursor += 1
        names = ["self"] if method else []
        depth = 0
        while cursor < len(tokens):
            piece = tokens[cursor][0]
            if piece in "({[":
                depth += 1
            elif piece in ")}]":
                depth -= 1
                if depth == 0:
                    break
            elif depth == 1 and re.match(r"[A-Za-z_]\w*$", piece) and tokens[cursor - 1][0] in ("(", ","):
                names.append(piece)
            cursor += 1
        return names

    index = 0
    while index < len(tokens):
        word, line = tokens[index]
        if not frames:
            return peak, peak_line, over, line
        frame = frames[-1]
        was_consumed, consumed = consumed, False

        if word == "local":
            if index + 2 < len(tokens) and tokens[index + 1][0] == "function":
                allocate([tokens[index + 2][0]], line)
                frames.append(new_frame())
                allocate(parameters(index + 1), line)
                previous = "function"
                index += 2
                continue
            names = []
            cursor = index + 1
            while cursor < len(tokens):
                names.append(tokens[cursor][0])
                name_line = tokens[cursor][1]
                cursor += 1
                if cursor < len(tokens) and tokens[cursor][0] == ":":
                    depth = 0
                    cursor += 1
                    while cursor < len(tokens):
                        piece, piece_line = tokens[cursor]
                        if piece in "({[<":
                            depth += 1
                        elif piece in ")}]>":
                            depth -= 1
                        elif depth == 0 and (piece in (",", "=") or piece_line != name_line):
                            break
                        cursor += 1
                if cursor < len(tokens) and tokens[cursor][0] == "," and tokens[cursor][1] == line:
                    cursor += 1
                    continue
                break
            allocate(names, line)
            previous = tokens[cursor - 1][0]
            index = cursor
            continue

        if word == "function":
            frames.append(new_frame())
            allocate(parameters(index), line)
        elif word == "for":
            names = []
            cursor = index + 1
            while cursor < len(tokens) and tokens[cursor][0] not in ("=", "in"):
                if re.match(r"[A-Za-z_]\w*$", tokens[cursor][0]) and tokens[cursor - 1][0] in ("for", ","):
                    names.append(tokens[cursor][0])
                cursor += 1
            frame["loop"] = names
        elif word == "while":
            frame["loop"] = []
        elif word == "do":
            names, frame["loop"] = frame["loop"], None
            frame["scopes"].append(["do", 0])
            if names:
                allocate(names, line)
        elif word == "repeat":
            frame["scopes"].append(["repeat", 0])
        elif word == "until":
            if len(frame["scopes"]) < 2:
                return peak, peak_line, over, line
            frame["scopes"].pop()
        elif word == "if":
            if previous in IF_EXPRESSION_AFTER or (previous in ("then", "else") and was_consumed):
                frame["ifexpr"].append("then")
            else:
                frame["scopes"].append(["if", 0])
        elif word == "then":
            if frame["ifexpr"] and frame["ifexpr"][-1] == "then":
                frame["ifexpr"][-1] = "else"
                consumed = True
        elif word in ("elseif", "else"):
            if frame["ifexpr"] and frame["ifexpr"][-1] == "else":
                if word == "else":
                    frame["ifexpr"].pop()
                    consumed = True
                else:
                    frame["ifexpr"][-1] = "then"
            elif len(frame["scopes"]) > 1:
                # A new branch is a new scope: the last branch's locals are gone.
                frame["scopes"][-1][1] = 0
            else:
                return peak, peak_line, over, line
        elif word == "end":
            if len(frame["scopes"]) > 1:
                frame["scopes"].pop()
            else:
                frames.pop()
        previous = word
        index += 1

    lost = None if len(frames) == 1 and len(frames[0]["scopes"]) == 1 else (tokens[-1][1] if tokens else 0)
    return peak, peak_line, over, lost


# A CONSTANT THAT IS USED AND NEVER DECLARED.
#
# Luau resolves an unknown name to a nil GLOBAL instead of failing to compile, so deleting a
# constant leaves a file that loads perfectly and then throws the first time the line runs.
# Bootstrap lost CHILL_SETBACK_STUDS to a careless block replacement and threw
# "attempt to perform arithmetic (mul) on Vector3 and nil" on every frame a player was below
# the kill plane -- and because the throw came before the teleport, chill-mode fall recovery
# silently stopped working. Nothing caught it: it is not a use-before-declaration, because
# there is no declaration anywhere.
#
# SCREAMING_SNAKE names only. That is the convention for constants across this project, it
# is the thing block edits delete by accident, and restricting the check to it keeps the
# rule free of guesses about locals, parameters and globals.
CONST_NAME = re.compile(r"(?<![.:\w])([A-Z][A-Z0-9_]{2,})\b")
CONST_DECL = re.compile(r"^\s*local\s+(?:function\s+)?([A-Z][A-Z0-9_]{2,})\b")
CONST_DECL_MULTI = re.compile(r"^\s*local\s+([A-Z][A-Z0-9_,\s]+?)\s*(?:=|$)")
# `NAME = value` at the start of a line is a table KEY or an assignment, not a use. Without
# this the check fires on every constants table in the project -- Constants, the keyboard's
# Keys, every material block -- which is the fastest way to get a checker ignored.
CONST_KEY = re.compile(r"^\s*([A-Z][A-Z0-9_]{2,})\s*=(?!=)")

# Names that are legitimately global or provided by the engine.
CONST_ALLOWED = {"UDim", "UDim2", "CFrame"}


def check_undeclared_constants(path, clean):
    declared = set()
    for line in clean.splitlines():
        match = CONST_DECL.match(line)
        if match:
            declared.add(match.group(1))
        multi = CONST_DECL_MULTI.match(line)
        if multi:
            for piece in multi.group(1).split(","):
                piece = piece.strip()
                if piece:
                    declared.add(piece)
        key = CONST_KEY.match(line)
        if key:
            declared.add(key.group(1))

    problems = []
    seen = set()
    for number, line in enumerate(clean.splitlines(), start=1):
        for name in CONST_NAME.findall(line):
            if name in declared or name in CONST_ALLOWED or name in seen:
                continue
            seen.add(name)
            problems.append(
                f"{path.name}:{number}  '{name}' is used but never declared in this file -- "
                "Luau reads that as a nil global, so it throws only when the line runs."
            )
    return problems


# CALLING A FUNCTION THAT DOES NOT EXIST IN THE MODULE YOU REQUIRED.
#
# Bootstrap called DeformationService.restoreAll() for a while after a block replacement in
# DeformationService deleted the function. Nothing complained: Luau indexes the module table,
# finds nil, and throws "attempt to call a nil value" only when the line runs -- which for a
# hardcore restart means the first time a player falls, not at load.
#
# Both halves are visible from here, so the check is cheap: collect `function Module.name`
# from each file, then look for `Local.name(` where Local was bound by a require of that
# file. Anything called and not defined is reported.
REQUIRE_BIND = re.compile(r"^local\s+([A-Z]\w*)\s*=\s*require\(.*?[\"']?([A-Z]\w*)[\"']?\)", re.M)
MODULE_DEF = re.compile(r"^function\s+([A-Z]\w*)\.(\w+)", re.M)
MODULE_CALL = re.compile(r"\b([A-Z]\w*)\.(\w+)\s*\(")


def collect_module_exports(files):
    """{module name: {function names}} for every module that defines any."""
    exports = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        for module, name in MODULE_DEF.findall(text):
            exports.setdefault(module, set()).add(name)
        # A table assembled and returned, e.g. `Module.thing = function(...)`.
        for module, name in re.findall(r"^([A-Z]\w*)\.(\w+)\s*=", text, re.M):
            exports.setdefault(module, set()).add(name)
    return exports


def check_cross_module_calls(path, clean, exports):
    problems = []
    seen = set()
    for number, line in enumerate(clean.splitlines(), start=1):
        for module, name in MODULE_CALL.findall(line):
            known = exports.get(module)
            # Only modules this project actually defines. Anything else is an engine
            # service, a required third party, or a local table, and not our business.
            if not known or name in known or (module, name) in seen:
                continue
            seen.add((module, name))
            problems.append(
                f"{path.name}:{number}  calls {module}.{name}(), which {module} does not "
                "define -- that is a nil index, and it throws only when the line runs."
            )
    return problems


# A MATERIAL THAT FAILS IN STAGES MUST HAVE ONE FEWER STAGE THAN IT HAS STEPS.
#
# The last step is the one that collapses the cell, and the server sends the collapse in the
# same breath as the step that caused it. So a material with three steps and three stages
# shows its final stage for a frame and then replaces it with the hole -- which means the
# stage that exists to say "the next one will not hold" can never be acted on. Chocolate
# shipped that way for exactly one commit.
#
# The convention this checks: a material with `stepsToCollapse = N` in MaterialConfig, whose
# constants table in DeformationRenderer carries a `stages` or `lift` array, must have N - 1
# entries in it. Materials with no such array are not staged and are skipped.
STEPS_RE = re.compile(r"^	(\w+) = \{(.*?)^	\},", re.S | re.M)


def _balanced(text, open_at):
    """The contents of the table that opens at `open_at`, matched by counting braces.

    Written out rather than done with a regex because a regex cannot count. The first
    attempt used a non-greedy match to the next `},` and it stopped at the end of the FIRST
    entry in the table, so every staged material reported exactly one stage and the check
    fired on materials that were correct.
    """
    depth = 0
    for i in range(open_at, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_at + 1:i]
    return ""


def check_stage_counts(files):
    config = next((f for f in files if f.name == "MaterialConfig.lua"), None)
    renderer = next((f for f in files if f.name == "DeformationRenderer.lua"), None)
    if not (config and renderer):
        return []

    steps = {}
    for name, body in STEPS_RE.findall(config.read_text(encoding="utf-8")):
        found = re.search(r"stepsToCollapse = (\d+)", body)
        if found:
            steps[name] = int(found.group(1))

    text = renderer.read_text(encoding="utf-8")
    problems = []
    for material, count in sorted(steps.items()):
        #  matters: without a word boundary "Lego" also matches inside
        # "LegoStuds" and similar, and the anchor silently lands on the wrong table.
        opened = re.search(r"\b" + material + r" = \{", text)
        if not opened:
            continue
        body = _balanced(text, opened.end() - 1)
        listed = re.search(r"(?:stages|lift) = \{", body)
        if not listed:
            continue  # not a staged material; its look does not change between steps
        inner = _balanced(body, listed.end() - 1)
        shown = inner.count("{") if "{" in inner else len([x for x in inner.split(",") if x.strip()])
        if shown != count - 1:
            problems.append(
                f"{material} has stepsToCollapse = {count} but {shown} visible stage(s). "
                f"The last step collapses the cell, so only {count - 1} stages can ever be "
                f"seen -- with {shown} the final one flashes for a frame or never renders."
            )
    return problems


# A MATERIAL THAT FAILS IN STAGES MUST ACTUALLY READ WHICH STAGE IT IS ON.
#
# The sibling of the check above, and the one that would have caught the older bug. That one
# verifies a staged material has the right NUMBER of stages defined; this verifies its effect
# ever looks at them. Kinetic sand had three steps and three distinct looks available to it
# from the day it was written, and its effect never read `ctx.stepCount` once -- so every
# footfall pressed the same bowl and the floor then vanished on the third with no warning
# the player could have seen. Defining the stages and using them are separate mistakes.
#
# Only materials with three or more steps are checked. At two there is exactly one step
# before the collapse, `stepCount` can only ever be 1, and reading it would be noise.
ALIAS_RE = re.compile(r"^Effects\.(\w+) = Effects\.(\w+)$", re.M)


def check_staged_reads_count(files):
    config = next((f for f in files if f.name == "MaterialConfig.lua"), None)
    renderer = next((f for f in files if f.name == "DeformationRenderer.lua"), None)
    if not (config and renderer):
        return []

    text = renderer.read_text(encoding="utf-8")
    # Some materials share one effect function -- jello is driven by slime's rig. Follow the
    # alias, or the shared pair reports as missing an effect it plainly has.
    alias = dict(ALIAS_RE.findall(text))

    problems = []
    for name, body in STEPS_RE.findall(config.read_text(encoding="utf-8")):
        found = re.search(r"stepsToCollapse = (\d+)", body)
        if not found or int(found.group(1)) < 3:
            continue
        target = alias.get(name, name)
        effect = re.search(
            r"^Effects\." + target + r" = function.*?(?=^Effects\.\w+ = |^local function |\Z)",
            text, re.S | re.M)
        if not effect:
            continue  # no effect at all is a different problem, and not this check's to report
        if "stepCount" not in effect.group(0):
            problems.append(
                f"{name} takes {found.group(1)} steps to collapse but Effects.{target} never "
                f"reads ctx.stepCount, so every step looks identical and the collapse arrives "
                f"with no warning. Scale the deformation by the step, the way ice does."
            )
    return problems


# THE SAME NAME DECLARED TWICE AT THE TOP LEVEL OF ONE FUNCTION.
#
# Lua allows it: the second `local x` shadows the first for the rest of the scope, silently,
# and every line after it that meant the first one now means the second. A blanket rename in
# soapDust collapsed a carrier Part and its emitter onto the name `dust`, and the line
# `dust.Parent = host` became `dust.Parent = dust` -- an emitter parented to itself, with the
# part orphaned. It compiles, it runs, and nothing appears on screen.
#
# Only ONE indent deep, which is the function's own scope. Deeper repeats are separate blocks
# (two loops each with their own `local index`) and are perfectly ordinary.
FUNC_HEAD = re.compile(r"^(?:local function (\w+)|function ([\w.:]+)|([\w.]+) = function)")


def check_shadowed_locals(path, clean):
    lines = clean.splitlines()
    problems = []
    for number, line in enumerate(lines):
        head = FUNC_HEAD.match(line)
        if not head:
            continue
        # The body runs to the first `end` at column 0. Every top-level function in this
        # project closes that way, and taking "the next function header" as the boundary
        # instead swallows whole neighbourhoods of unrelated code -- which reported eleven
        # functions as shadowing names they declare exactly once.
        stop = next((i for i in range(number + 1, len(lines)) if lines[i] == "end"), len(lines))
        where = head.group(1) or head.group(2) or head.group(3)
        seen = {}
        for offset in range(number + 1, stop):
            found = re.match(r"^\tlocal (\w+)\s*[:=]", lines[offset])
            if not found:
                continue
            local = found.group(1)
            if local in seen:
                problems.append(
                    f"{path.name}:{offset + 1}  '{local}' is declared twice in the same "
                    f"scope in {where} (first at line {seen[local]}). The second shadows "
                    "the first for everything below it, silently."
                )
            else:
                seen[local] = offset + 1
    return problems


# A FIELD READ OFF A CONSTANTS TABLE THAT THE TABLE DOES NOT HAVE.
#
# `NEW_MATS.Snow.powder` where the field is called `puff` reads as nil, and `Emit(nil)` throws
# only when a player steps on snow. The whole table is right there in the same file, so there
# is no reason for this to be a runtime discovery.
#
# Applies only to two-level tables of constants -- `local NAME = { Key = { field = ... } }` --
# where every top-level entry is itself a table. Anything else is a lookup keyed at runtime
# and cannot be checked from here.
TWO_LEVEL = re.compile(r"^local ([A-Z][A-Z_0-9]*[A-Z0-9])(?:: [^=]+)? = \{", re.M)


def _fields(body):
    """Top-level `name =` keys of a table body, ignoring anything nested inside it."""
    names, depth = [], 0
    for piece in re.finditer(r"[{}]|\b(\w+)\s*=", body):
        if piece.group(0) in "{}":
            depth += 1 if piece.group(0) == "{" else -1
        elif depth == 0 and piece.group(1):
            names.append(piece.group(1))
    return names


def check_constant_fields(path, clean):
    problems = []
    for table in TWO_LEVEL.finditer(clean):
        body = _balanced(clean, clean.index("{", table.start()))
        keys = {}
        for entry in re.finditer(r"^\t(\w+) = \{", body, re.M):
            keys[entry.group(1)] = set(_fields(_balanced(body, entry.end() - 1)))
        if not keys or len(keys) < 2:
            continue

        name = table.group(1)
        seen = set()
        for number, line in enumerate(clean.splitlines(), start=1):
            for key, field in re.findall(r"\b" + name + r"\.(\w+)\.(\w+)", line):
                if key not in keys or field in keys[key] or (key, field) in seen:
                    continue
                seen.add((key, field))
                problems.append(
                    f"{path.name}:{number}  {name}.{key}.{field} does not exist -- "
                    f"{name}.{key} has {', '.join(sorted(keys[key])) or 'no fields'}. "
                    "Luau reads a missing field as nil and throws only when the line runs."
                )
    return problems


# EVERY MATERIAL NEEDS A SCREEN LOOK, or it feels the same to stand on as to stand beside.
#
# This is the quietest kind of omission there is. A material with no entry in ScreenEffects
# does not error, warn or look broken -- it just never touches the camera, so it is missing
# one of its four feedback channels and nothing says so. The same class of gap left the
# creamy keyboard with no audio row for a while, and that took a bug report to find.
def check_screen_looks(files):
    config = next((f for f in files if f.name == "MaterialConfig.lua"), None)
    effects = next((f for f in files if f.name == "ScreenEffects.lua"), None)
    if not (config and effects):
        return []

    materials = set(re.findall(r"^	(\w+) = \{", config.read_text(encoding="utf-8"), re.M))
    text = effects.read_text(encoding="utf-8")
    start = text.find("local LOOKS")
    if start < 0:
        return []
    # Keyed on the entry NAME and the presence of a `shape` field, not on whichever field
    # happens to come first. The original matched `= { tint`, and the moment the look format
    # changed to lead with `colour` this reported four materials missing that were all
    # present. A check that fails on a formatting change teaches people to ignore it, which
    # is worse than not having it.
    # Scanned line by line rather than matched as a block, because these entries do not end
    # on a line of their own -- they close with `blur = 2 },` inline -- so every attempt to
    # write one regex for "an entry" got it wrong in a different way. Two rewrites of this
    # check reported materials missing that were present, which is the failure mode that
    # matters most: a check nobody believes is a check nobody reads.
    looks = set()
    pending, body = None, []
    for line in text[start:].splitlines():
        opened = re.match(r"^	(\w+) = \{", line)
        if opened:
            if pending and any("shape =" in part for part in body):
                looks.add(pending)
            pending, body = opened.group(1), [line]
        elif pending:
            if line.startswith("}"):
                break
            body.append(line)
    if pending and any("shape =" in part for part in body):
        looks.add(pending)

    # NO_MARK is a DECLARATION that a material leaves nothing behind, and it counts as an
    # answer. Six materials are dry moulded plastic, cold tempered chocolate or a bar of
    # soap, and none of them put anything on a lens -- so the question worth asking is not
    # "does it have marks" but "has anyone decided", which is the part that gets forgotten.
    exempt = set()
    declared = re.search(r"local NO_MARK[^{]*\{(.*?)\n\}", text, re.S)
    if declared:
        exempt = set(re.findall(r"(\w+) = true", declared.group(1)))

    problems = []
    for missing in sorted(materials - looks - exempt):
        problems.append(
            f"{missing} is in neither ScreenEffects.LOOKS nor NO_MARK. Decide whether it "
            "marks the lens and write it down -- an omission here is silent, and the "
            "material ends up a feedback channel short with nothing to say so."
        )
    for extra in sorted(looks - materials):
        problems.append(
            f"ScreenEffects.LOOKS has an entry for {extra}, which is not a material in "
            "MaterialConfig -- a renamed material leaves its look behind and it never fires."
        )
    return problems


# A FUNCTION CALLED IN A FILE THAT THE FILE NEVER DECLARES.
#
# This has now happened three times, every time the same way: a block replacement that was
# meant to rewrite one function took a neighbouring one out with it, and nothing noticed
# until the line ran. DeformationService lost restoreAll, Bootstrap lost CHILL_SETBACK_STUDS,
# and ChunkBuilder lost attachAmbient -- that last one left `attachAmbient(slab, materialName)`
# sitting in the middle of the platform builder calling nothing, which is a hard error on
# every chunk that builds.
#
# check_undeclared_constants catches this for SCREAMING_SNAKE names and check_cross_module_calls
# catches it across modules. Neither covers a plain local function called in its own file,
# which is the most common shape of the mistake.
#
# The false-positive risk is twofold, and the first attempt tripped over both.
#
# KEYWORDS LOOK LIKE CALLS. `if (a and b) then`, `not (x)`, `return (y)` and every anonymous
# `function(...)` all match "name followed by an open bracket", and the first run reported
# nineteen problems of which all nineteen were `if()`, `not()`, `then()` and friends. A
# checker whose every finding is noise gets switched off, so the keywords are excluded first.
#
# GLOBALS look like calls too, so anything Luau or Roblox provides is listed below, and
# anything bound as a parameter, a loop variable or a local of any kind is collected from the
# file itself. A name that survives all three is genuinely called and genuinely absent.
LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
    "continue", "export", "type",
}

LUA_GLOBALS = {
    "print", "warn", "error", "assert", "pairs", "ipairs", "next", "select", "type",
    "typeof", "tostring", "tonumber", "unpack", "require", "pcall", "xpcall", "rawget",
    "rawset", "rawequal", "rawlen", "setmetatable", "getmetatable", "tick", "time", "wait",
    "spawn", "delay", "newproxy", "collectgarbage", "gcinfo", "loadstring",
    "table", "math", "string", "os", "task", "coroutine", "bit32", "utf8", "debug", "shared",
    "game", "workspace", "script", "plugin", "Instance", "Enum", "Vector2", "Vector3",
    "CFrame", "Color3", "ColorSequence", "ColorSequenceKeypoint", "NumberRange",
    "NumberSequence", "NumberSequenceKeypoint", "UDim", "UDim2", "TweenInfo", "Random",
    "Ray", "Region3", "BrickColor", "Rect", "PhysicalProperties", "Faces", "Axes",
    "OverlapParams", "RaycastParams", "DateTime", "buffer", "vector",
}

DECL_LOCAL = re.compile(r"^\s*local\s+(?:function\s+)?([A-Za-z_]\w*)", re.M)
DECL_MULTI = re.compile(r"^\s*local\s+([A-Za-z_][\w,\s]*?)\s*=", re.M)
DECL_PARAMS = re.compile(r"function[^(\n]*\(([^)]*)\)")
DECL_LOOPVAR = re.compile(r"\bfor\s+([A-Za-z_][\w,\s]*?)\s+(?:=|in)\b")
CALL_BARE = re.compile(r"(^|[^\w.:])([a-z_]\w*)\s*\(", re.M)


def check_undeclared_calls(path, clean):
    known = set(LUA_GLOBALS) | LUA_KEYWORDS
    for match in DECL_LOCAL.finditer(clean):
        known.add(match.group(1))
    for match in DECL_MULTI.finditer(clean):
        known.update(n.strip() for n in match.group(1).split(",") if n.strip())
    for match in DECL_PARAMS.finditer(clean):
        for param in match.group(1).split(","):
            # Strip any type annotation and any default.
            name = param.split(":")[0].strip().lstrip(".")
            if name:
                known.add(name)
    for match in DECL_LOOPVAR.finditer(clean):
        known.update(n.strip() for n in match.group(1).split(",") if n.strip())

    problems = []
    seen = set()
    for number, line in enumerate(clean.splitlines(), start=1):
        for _lead, name in CALL_BARE.findall(line):
            if name in known or name in seen:
                continue
            seen.add(name)
            problems.append(
                f"{path.name}:{number}  calls {name}(), which this file never declares and "
                "which is not a Luau or Roblox global. That is a nil call and it throws the "
                "first time the line runs -- usually a block replacement took the function "
                "out and left the call behind."
            )
    return problems



# A SERVICE IS NOT A GLOBAL, however much it reads like one.
#
# RunService.Heartbeat was written into HubService with no `local RunService = ...` above it.
# Every other check passed: the block structure was fine, nothing was used before its
# declaration, and the name looks so much like part of the language that reading the line does
# not raise a flag. It is a nil index and it throws the moment the pool is built.
#
# Roblox has no service globals at all -- every one of them has to come through GetService --
# so a bare service name that the file never binds is always a mistake.
SERVICES = (
    "RunService", "TweenService", "Players", "ReplicatedStorage", "ServerStorage",
    "UserInputService", "ContextActionService", "CollectionService", "Debris",
    "PhysicsService", "SoundService", "TeleportService", "DataStoreService",
    "MarketplaceService", "HttpService", "PathfindingService", "TextService",
    "MessagingService", "MemoryStoreService", "Lighting", "StarterGui",
)


def check_services_are_required(path, text):
    problems = []
    name_of = str(path).replace("\\", "/").rsplit("/", 1)[-1]
    rows = text.splitlines()
    for name in SERVICES:
        used = None
        for number, row in enumerate(rows, 1):
            # Not preceded by a dot or colon: game.Workspace is a property access, and
            # ReplicatedStorage.Assets.ReplicatedStorage would be too.
            if re.search(r"(?<![\w.:])" + name + r"\s*[.:]", row):
                used = number
                break
        if used is None:
            continue
        # Any binding will do -- `local X = game:GetService("X")` is the normal one, but a
        # module that takes the service as a parameter or aliases it is equally fine. What is
        # never fine is the name appearing with nothing behind it.
        if re.search(r"\blocal\s+" + name + r"\b[^\n]*=", text):
            continue
        problems.append(
            "%s:%d  uses %s but never binds it. Roblox has no service globals, so this is a "
            "nil index the first time the line runs. Add: "
            'local %s = game:GetService("%s")' % (name_of, used, name, name, name))
    return problems


# EVERY ENUM.MATERIAL NAME IS ONE ROBLOX HAS. An invented one (CorrugatedPlate) is not a compile
# error: the module loads, and the first build that reaches the line throws, which took a whole
# level down to its fallback. This list is the engine's Enum.Material, parts and terrain.
MATERIALS = {
    "Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Basalt", "Slate", "CrackedLava",
    "Concrete", "Limestone", "Granite", "Pavement", "Brick", "Pebble", "Cobblestone", "Rock", "Sandstone",
    "CorrodedMetal", "DiamondPlate", "Foil", "Metal", "Grass", "LeafyGrass", "Sand", "Fabric", "Snow", "Mud",
    "Ground", "Asphalt", "Salt", "Ice", "Glacier", "Glass", "ForceField", "Air", "Water", "Cardboard",
    "Carpet", "CeramicTiles", "ClayRoofTiles", "RoofShingles", "Leather", "Plaster", "Rubber",
}


def check_material_names(path, clean):
    problems = []
    for number, row in enumerate(clean.splitlines(), 1):
        for name in re.findall(r"Enum\.Material\.(\w+)", row):
            if name not in MATERIALS:
                problems.append("%s:%d  Enum.Material.%s does not exist; the line throws the first time it runs"
                                % (path.name, number, name))
    return problems


# A NAME DECLARED TWICE AT THE TOP OF A FILE. Luau allows it and says nothing: the second `local`
# makes a new variable and every line after it sees only that one. SunkenCityService declared
# `local STREET = 26` (the gap between blocks) and, two hundred lines later, `local STREET = { ... }`
# (the street furniture's numbers), and `BLOCK + STREET` became a number plus a table: the whole
# city failed to build. A type declared twice is the same trap for the type checker.
def check_top_level_redeclared(path, clean):
    problems = []
    seen = {}
    for number, row in enumerate(clean.splitlines(), 1):
        names = []
        match = re.match(r"^local\s+function\s+(\w+)", row)
        if match:
            names = [match.group(1)]
        else:
            match = re.match(r"^local\s+(.*)$", row)
            if match:
                # The names before the `=`, split on commas at bracket depth 0 only: a type such as
                # `{ level: number, on: number }` has commas of its own that are not more names.
                depth, piece, pieces = 0, "", []
                for ch in match.group(1):
                    if ch in "{([<":
                        depth += 1
                    elif ch in "})]>":
                        depth -= 1
                    elif depth == 0 and ch == "=":
                        break
                    if depth == 0 and ch == ",":
                        pieces.append(piece)
                        piece = ""
                    else:
                        piece += ch
                pieces.append(piece)
                for piece in pieces:
                    name = piece.split(":")[0].strip()
                    if re.match(r"^[A-Za-z_]\w*$", name):
                        names.append(name)
            else:
                match = re.match(r"^(?:export\s+)?type\s+(\w+)", row)
                if match:
                    names = ["type " + match.group(1)]
        for name in names:
            if name in seen:
                problems.append("%s:%d  `%s` is declared again at the top of the file (first at line %d); every "
                                "line after this sees the second one" % (path.name, number, name, seen[name]))
            else:
                seen[name] = number
    return problems


def main():
    files = sorted(ROOT.glob("src/**/*.lua"))
    if not files:
        print("no Lua sources found")
        return 1

    problems = []
    crowded = []
    exports = collect_module_exports(files)
    for path in files:
        source = path.read_text(encoding="utf-8")
        clean = strip_noise(source)
        problems += check_use_before_declaration(path, clean)
        problems += check_block_balance(path, clean)
        # On the RAW source, not the stripped copy: strip_noise blanks string bodies, and
        # this check needs the line as written.
        problems += check_annotated_fields(path, source.splitlines())
        problems += check_undeclared_constants(path, clean)
        problems += check_cross_module_calls(path, clean, exports)
        problems += check_undeclared_calls(path, clean)
        problems += check_unterminated_strings(
            path, path.read_text(encoding="utf-8").splitlines())
        problems += check_comment_continuations(
            path, path.read_text(encoding="utf-8").splitlines())
        problems += check_services_are_required(path, clean)
        problems += check_shadowed_locals(path, clean)
        problems += check_constant_fields(path, clean)
        problems += check_material_names(path, clean)
        problems += check_top_level_redeclared(path, clean)

        used, used_line, over, lost = peak_live_locals(source)
        if over:
            # A FAILURE: this is the compile error itself, at the line Studio will name.
            problems.append(
                f"  {path.name}:{over[0]}  allocates `{over[1]}` with {REGISTER_LIMIT} locals already "
                f"live in its function: Luau refuses to compile the module (Out of local registers). "
                f"Give the section its own function, or fold locals into a table."
            )
        elif lost:
            problems.append(
                f"  {path.name}:{lost}  the live-locals count lost track of the blocks here, so it "
                f"cannot vouch for this file. Fix peak_live_locals in check_lua before trusting it."
            )
        elif used >= REGISTER_WARN:
            # A WARNING, NOT A FAILURE. Being near the ceiling is not a bug -- the file
            # compiles today -- so failing the run on it would leave every check red until
            # someone refactors, and a checker that is always red gets ignored.
            crowded.append((path.name, used, used_line))

    # Cross-file, so it runs once after the per-file loop rather than inside it.
    problems += check_stage_counts(files)
    problems += check_staged_reads_count(files)

    problems += check_screen_looks(files)

    print(f"checked {len(files)} Luau sources")

    for name, used, used_line in crowded:
        print(
            f"  NOTE: {name} has {used} locals live at once at line {used_line}, against Luau's "
            f"limit of {REGISTER_LIMIT} in one function."
        )
        print(
            "        Collapse related ones into a single table, or give a section its own "
            "function, before adding more."
        )

    if problems:
        print("\nPROBLEMS:")
        print("\n".join(problems))
        return 1
    print("no use-before-declaration, blocks balanced.")
    return 0


sys.exit(main())
