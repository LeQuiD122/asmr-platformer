"""EVERY LUAU FILE PARSED THE WAY LUAU PARSES IT.

check_lua.py looks for the particular ways a file here has broken before -- blocks that do not
balance, strings left open, too many locals, constants never declared -- but it does not PARSE.
A file can pass all of that and still fail to compile in Studio, and a ModuleScript that fails to
compile takes everything that requires it down with it, with nothing in the game to say so. The
Sunken City's client went unseen for several passes, and "does it even compile?" could not be
answered from here.

This is a recursive-descent parser for Luau's grammar (luau-lang.org/grammar): statements,
expressions with if-expressions and `::` casts, compound assignment, `continue`, interpolated
strings, generic functions, and the whole type language -- aliases, unions and intersections,
optionals, table and function types, packs and generic packs, `typeof`. It also refuses what the
Luau compiler refuses beyond the grammar: a statement after `return`, `break` or `continue` in the
same block; `break` or `continue` outside a loop; assigning to a call; and a call whose `(` starts
on a new line ("Ambiguous syntax" in Studio).

AND EVERY NAME IS RESOLVED. A name read before the `local` that declares it (further down the same
function) is not an error to the compiler -- Luau reads it as a GLOBAL, nil -- and the line throws
only when it runs. The glass's setup did exactly that once (`flood` used in a loop above its own
`local flood`), which would have stopped the aquarium's glass working at all. So every name must be a
local in scope at that line, a parameter, a loop variable, or one of Roblox's globals.

It builds nothing and runs nothing. Exit 1 names the file, line and what was expected.
"""
import pathlib
import sys

SRC = pathlib.Path(__file__).resolve().parent.parent / "src"

KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
            "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}
OPS = sorted(["...", "..=", "//=", "::", "->", "==", "~=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "^=",
              "..", "//", "+", "-", "*", "/", "%", "^", "#", "<", ">", "=", "(", ")", "{", "}", "[", "]",
              ";", ":", ",", ".", "?", "|", "&", "@"], key=len, reverse=True)
COMPOUND = {"+=", "-=", "*=", "/=", "//=", "%=", "^=", "..="}
BINARY = {"or": (1, 1), "and": (2, 2), "<": (3, 3), ">": (3, 3), "<=": (3, 3), ">=": (3, 3), "~=": (3, 3),
          "==": (3, 3), "..": (5, 4), "+": (6, 6), "-": (6, 6), "*": (7, 7), "/": (7, 7), "//": (7, 7),
          "%": (7, 7), "^": (10, 9)}
UNARY_PRIORITY = 8
# Everything Roblox's Luau provides without a `local`.
GLOBALS = set(
    "game workspace Workspace script plugin shared _G _VERSION Instance Vector3 Vector2 Vector3int16 Vector2int16 "
    "CFrame Color3 ColorSequence ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint NumberRange UDim UDim2 Rect "
    "Ray Region3 Region3int16 BrickColor TweenInfo Enum PhysicalProperties RaycastParams OverlapParams Random DateTime "
    "Font Axes Faces PathWaypoint Content SharedTable buffer math table string task coroutine os debug utf8 bit32 print "
    "warn error assert pcall xpcall typeof type pairs ipairs next select tostring tonumber setmetatable getmetatable "
    "rawget rawset rawequal rawlen require unpack tick time wait delay spawn elapsedTime settings UserSettings version "
    "newproxy gcinfo collectgarbage stats DockWidgetPluginGuiInfo CatalogSearchParams FloatCurveKey RotationCurveKey "
    "Path2DControlPoint SecurityCapabilities vector".split())


class LuauError(Exception):
    def __init__(self, line, message):
        super().__init__(message)
        self.line = line
        self.message = message


class Tok:
    __slots__ = ("kind", "value", "line", "end")

    def __init__(self, kind, value, line, end):
        self.kind, self.value, self.line, self.end = kind, value, line, end

    def __repr__(self):
        return "%s %r" % (self.kind, self.value)


def describe(tok):
    if tok.kind == "eof":
        return "<eof>"
    if tok.kind in ("string", "interp"):
        return "string"
    return "'%s'" % tok.value


# ===================================================================== the lexer

def long_bracket(src, i):
    """At `[`: the level of a long bracket opening here, or -1."""
    j = i + 1
    while j < len(src) and src[j] == "=":
        j += 1
    if j < len(src) and src[j] == "[":
        return j - i - 1
    return -1


def tokenize(src):
    toks = []
    i, line, n = 0, 1, len(src)
    # Interpolated strings: each open one records the brace depth its current `{` was at.
    interp = []
    depth = 0

    def read_long(i, level, line):
        close = "]" + "=" * level + "]"
        j = src.find(close, i)
        if j < 0:
            raise LuauError(line, "unfinished long string or comment")
        return j + len(close), line + src.count("\n", i, j)

    def read_interp_part(i, line):
        """From just inside a backtick or just after a `}`: to the next `{` or the closing backtick."""
        start_line = line
        while True:
            if i >= n:
                raise LuauError(start_line, "unfinished interpolated string")
            c = src[i]
            if c == "\\":
                if i + 1 < n and src[i + 1] == "\n":
                    line += 1
                i += 2
                continue
            if c == "\n":
                raise LuauError(line, "malformed interpolated string: a line break inside it")
            if c == "`":
                return i + 1, line, "end"
            if c == "{":
                if i + 1 < n and src[i + 1] == "{":
                    raise LuauError(line, "double braces in an interpolated string are not allowed")
                return i + 1, line, "mid"
            i += 1

    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r\f\v":
            i += 1
            continue
        if src.startswith("--", i):
            if i + 2 < n and src[i + 2] == "[":
                level = long_bracket(src, i + 2)
                if level >= 0:
                    i, line = read_long(i + 2 + level + 2, level, line)
                    continue
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        start = line
        if c.isalpha() or c == "_":
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            word = src[i:j]
            toks.append(Tok("keyword" if word in KEYWORDS else "name", word, start, start))
            i = j
            continue
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            j = i
            if src.startswith(("0x", "0X"), i):
                j = i + 2
                while j < n and (src[j] in "0123456789abcdefABCDEF_"):
                    j += 1
            elif src.startswith(("0b", "0B"), i):
                j = i + 2
                while j < n and src[j] in "01_":
                    j += 1
            else:
                while j < n and (src[j].isdigit() or src[j] == "_"):
                    j += 1
                if j < n and src[j] == "." and not src.startswith("..", j):
                    j += 1
                    while j < n and (src[j].isdigit() or src[j] == "_"):
                        j += 1
                if j < n and src[j] in "eE":
                    j += 1
                    if j < n and src[j] in "+-":
                        j += 1
                    if j >= n or not src[j].isdigit():
                        raise LuauError(line, "malformed number")
                    while j < n and src[j].isdigit():
                        j += 1
            if j < n and (src[j].isalpha() or src[j] == "_"):
                raise LuauError(line, "malformed number near '%s'" % src[i:j + 1])
            toks.append(Tok("number", src[i:j], start, start))
            i = j
            continue
        if c in "\"'":
            j = i + 1
            while True:
                if j >= n:
                    raise LuauError(start, "unfinished string")
                d = src[j]
                if d == c:
                    j += 1
                    break
                if d == "\n":
                    raise LuauError(line, "malformed string: a line break inside it")
                if d == "\\":
                    e = src[j + 1] if j + 1 < n else ""
                    if e == "\n":
                        line += 1
                        j += 2
                    elif e == "z":
                        j += 2
                        while j < n and src[j] in " \t\r\n":
                            if src[j] == "\n":
                                line += 1
                            j += 1
                    else:
                        j += 2
                    continue
                j += 1
            toks.append(Tok("string", src[i:j], start, line))
            i = j
            continue
        if c == "[":
            level = long_bracket(src, i)
            if level >= 0:
                j, line = read_long(i + level + 2, level, line)
                toks.append(Tok("string", "[[...]]", start, line))
                i = j
                continue
        if c == "`":
            j, line, how = read_interp_part(i + 1, line)
            if how == "end":
                toks.append(Tok("interp", "simple", start, line))
            else:
                toks.append(Tok("interp", "begin", start, line))
                interp.append(depth)
            i = j
            continue
        if c == "}" and interp and depth == interp[-1]:
            j, line, how = read_interp_part(i + 1, line)
            if how == "end":
                toks.append(Tok("interp", "end", start, line))
                interp.pop()
            else:
                toks.append(Tok("interp", "mid", start, line))
            i = j
            continue
        for op in OPS:
            if src.startswith(op, i):
                if op == "{":
                    depth += 1
                elif op == "}":
                    depth -= 1
                toks.append(Tok("op", op, start, start))
                i += len(op)
                break
        else:
            raise LuauError(line, "unexpected character %r" % c)
    toks.append(Tok("eof", "", line, line))
    return toks


# ===================================================================== the parser

class Parser:
    def __init__(self, toks):
        self.toks = toks
        self.i = 0
        # One entry per function being parsed: how many loops deep we are in it.
        self.loops = [0]
        # The names declared in each enclosing scope, innermost last.
        self.scopes = [set()]

    def declare(self, *names):
        self.scopes[-1].update(names)

    def resolve(self, tok):
        for scope in reversed(self.scopes):
            if tok.value in scope:
                return
        if tok.value not in GLOBALS:
            raise LuauError(tok.line, "'%s' is not declared here: no local of that name is in scope at this line, so "
                            "Luau reads it as a nil global" % tok.value)

    # --- tokens
    def peek(self, k=0):
        return self.toks[min(self.i + k, len(self.toks) - 1)]

    def prev(self):
        return self.toks[self.i - 1]

    def next(self):
        tok = self.toks[self.i]
        self.i += 1
        return tok

    def is_(self, value, k=0):
        tok = self.peek(k)
        return tok.kind in ("op", "keyword") and tok.value == value

    def is_name(self, value=None, k=0):
        tok = self.peek(k)
        return tok.kind == "name" and (value is None or tok.value == value)

    def accept(self, value):
        if self.is_(value):
            return self.next()
        return None

    def expect(self, value, context=None):
        if not self.is_(value):
            where = " (to close %s)" % context if context else ""
            raise LuauError(self.peek().line, "expected '%s'%s, got %s" % (value, where, describe(self.peek())))
        return self.next()

    def name(self, what="identifier"):
        tok = self.peek()
        if tok.kind != "name":
            raise LuauError(tok.line, "expected %s, got %s" % (what, describe(tok)))
        return self.next()

    # --- blocks
    def block_follows(self):
        tok = self.peek()
        return tok.kind == "eof" or (tok.kind == "keyword" and tok.value in ("else", "elseif", "end", "until"))

    def chunk(self):
        self.block()
        if self.peek().kind != "eof":
            raise LuauError(self.peek().line, "expected <eof>, got %s" % describe(self.peek()))

    def block(self, scope=True):
        if scope:
            self.scopes.append(set())
        try:
            self.block_statements()
        finally:
            if scope:
                self.scopes.pop()

    def block_statements(self):
        while not self.block_follows():
            if self.accept(";"):
                continue
            last = self.statement()
            self.accept(";")
            if last and not self.block_follows():
                raise LuauError(self.peek().line, "%s must be the last statement in its block, and %s follows it"
                                % (last, describe(self.peek())))

    # --- statements; returns the name of a last-statement kind, or None
    def statement(self):
        tok = self.peek()
        line = tok.line
        if tok.kind == "keyword":
            v = tok.value
            if v == "if":
                self.next()
                self.expr()
                self.expect("then")
                self.block()
                while self.accept("elseif"):
                    self.expr()
                    self.expect("then")
                    self.block()
                if self.accept("else"):
                    self.block()
                self.expect("end", "'if' at line %d" % line)
                return None
            if v == "while":
                self.next()
                self.expr()
                self.expect("do")
                self.loop_block()
                self.expect("end", "'while' at line %d" % line)
                return None
            if v == "do":
                self.next()
                self.block()
                self.expect("end", "'do' at line %d" % line)
                return None
            if v == "for":
                self.next()
                names = [self.binding()]
                if self.accept("="):
                    self.expr()
                    self.expect(",")
                    self.expr()
                    if self.accept(","):
                        self.expr()
                else:
                    while self.accept(","):
                        names.append(self.binding())
                    self.expect("in")
                    self.exprlist()
                self.expect("do")
                self.scopes.append(set(names))
                try:
                    self.loop_block()
                finally:
                    self.scopes.pop()
                self.expect("end", "'for' at line %d" % line)
                return None
            if v == "repeat":
                self.next()
                self.loops[-1] += 1
                # `until` sees the block's own locals, so the scope spans both.
                self.scopes.append(set())
                try:
                    self.block(scope=False)
                    self.loops[-1] -= 1
                    self.expect("until", "'repeat' at line %d" % line)
                    self.expr()
                finally:
                    self.scopes.pop()
                return None
            if v == "function":
                self.next()
                first = self.name("function name")
                if not any(first.value in scope for scope in self.scopes) and first.value not in GLOBALS:
                    self.scopes[0].add(first.value)
                method = False
                while self.accept("."):
                    self.name()
                if self.accept(":"):
                    self.name()
                    method = True
                self.funcbody(line, method)
                return None
            if v == "local":
                self.next()
                if self.accept("function"):
                    self.declare(self.name("function name").value)
                    self.funcbody(line)
                    return None
                names = [self.binding()]
                while self.accept(","):
                    names.append(self.binding())
                if self.accept("="):
                    self.exprlist()
                self.declare(*names)
                return None
            if v == "return":
                self.next()
                if not self.block_follows() and not self.is_(";"):
                    self.exprlist()
                return "return"
            if v == "break":
                self.next()
                if self.loops[-1] == 0:
                    raise LuauError(line, "break outside a loop")
                return "break"
        if tok.kind == "op" and tok.value == "@":
            self.attributes()
            local = bool(self.accept("local"))
            self.expect("function")
            first = self.name("function name")
            if local or first.value not in GLOBALS:
                self.declare(first.value)
            method = False
            while self.accept("."):
                self.name()
            if self.accept(":"):
                self.name()
                method = True
            self.funcbody(line, method)
            return None
        # The context-sensitive words: `type`, `export type` and `continue`, each only where a
        # name there could not be the start of an expression statement.
        if self.is_name("type") and self.peek(1).kind == "name":
            self.next()
            self.type_alias()
            return None
        if self.is_name("export") and self.is_name("type", 1):
            self.next()
            self.next()
            self.type_alias()
            return None
        if self.is_name("continue") and not (self.peek(1).kind == "op" and self.peek(1).value in
                                             ("(", ".", "[", ":", "=", ",", "{") | COMPOUND) \
                and self.peek(1).kind not in ("string", "interp"):
            self.next()
            if self.loops[-1] == 0:
                raise LuauError(line, "continue outside a loop")
            return "continue"
        # An expression statement: an assignment or a call.
        kind = self.suffixed()
        if self.is_("=") or self.is_(","):
            if kind not in ("name", "index"):
                raise LuauError(line, "assigned to something that is not a variable (a call or an expression)")
            while self.accept(","):
                if self.suffixed() not in ("name", "index"):
                    raise LuauError(line, "assigned to something that is not a variable")
            self.expect("=")
            self.exprlist()
            return None
        if self.peek().kind == "op" and self.peek().value in COMPOUND:
            if kind not in ("name", "index"):
                raise LuauError(line, "compound assignment to something that is not a variable")
            self.next()
            self.expr()
            return None
        if kind != "call":
            raise LuauError(line, "incomplete statement: expected an assignment or a function call, got %s"
                            % describe(self.peek()))
        return None

    def loop_block(self):
        self.loops[-1] += 1
        self.block()
        self.loops[-1] -= 1

    def attributes(self):
        while self.accept("@"):
            self.name("attribute")

    def binding(self):
        name = self.name().value
        if self.accept(":"):
            self.type_()
        return name

    def funcbody(self, line, method=False):
        if self.is_("<"):
            self.generic_list()
        self.expect("(")
        params = {"self"} if method else set()
        if not self.is_(")"):
            while True:
                if self.accept("..."):
                    if self.accept(":"):
                        self.variadic_annotation()
                    break
                params.add(self.binding())
                if not self.accept(","):
                    break
        self.expect(")")
        if self.accept(":"):
            self.return_type()
        self.loops.append(0)
        self.scopes.append(params)
        try:
            self.block()
        finally:
            self.scopes.pop()
            self.loops.pop()
        self.expect("end", "'function' at line %d" % line)

    # --- expressions
    def exprlist(self):
        self.expr()
        while self.accept(","):
            self.expr()

    def expr(self, limit=0):
        tok = self.peek()
        if (tok.kind == "keyword" and tok.value == "not") or (tok.kind == "op" and tok.value in ("-", "#")):
            self.next()
            self.expr(UNARY_PRIORITY)
        else:
            self.simple()
            if self.accept("::"):
                self.type_()
        while True:
            tok = self.peek()
            op = tok.value if tok.kind in ("op", "keyword") else None
            if op not in BINARY or BINARY[op][0] <= limit:
                break
            self.next()
            self.expr(BINARY[op][1])

    def simple(self):
        tok = self.peek()
        if tok.kind in ("number", "string"):
            self.next()
            return
        if tok.kind == "interp":
            self.interp()
            return
        if tok.kind == "keyword":
            if tok.value in ("nil", "true", "false"):
                self.next()
                return
            if tok.value == "function":
                self.next()
                self.funcbody(tok.line)
                return
            if tok.value == "if":
                self.next()
                self.expr()
                self.expect("then")
                self.expr()
                while self.accept("elseif"):
                    self.expr()
                    self.expect("then")
                    self.expr()
                if not self.accept("else"):
                    raise LuauError(self.peek().line, "an if-expression must have an 'else', got %s"
                                    % describe(self.peek()))
                self.expr()
                return
        if tok.kind == "op":
            if tok.value == "...":
                self.next()
                return
            if tok.value == "{":
                self.table()
                return
            if tok.value == "@":
                self.attributes()
                fn = self.expect("function")
                self.funcbody(fn.line)
                return
        self.suffixed()

    def interp(self):
        tok = self.next()
        if tok.value == "simple":
            return
        if tok.value != "begin":
            raise LuauError(tok.line, "a stray piece of an interpolated string")
        while True:
            self.expr()
            part = self.peek()
            if part.kind != "interp" or part.value not in ("mid", "end"):
                raise LuauError(part.line, "expected '}' to finish an interpolated string's expression, got %s"
                                % describe(part))
            self.next()
            if part.value == "end":
                return

    def primary(self):
        tok = self.peek()
        if tok.kind == "name":
            self.next()
            self.resolve(tok)
            return "name"
        if tok.kind == "op" and tok.value == "(":
            self.next()
            self.expr()
            self.expect(")", "'(' at line %d" % tok.line)
            return "paren"
        raise LuauError(tok.line, "expected an identifier or an expression, got %s" % describe(tok))

    def suffixed(self):
        kind = self.primary()
        while True:
            tok = self.peek()
            if tok.kind == "op" and tok.value == ".":
                self.next()
                self.name("field name")
                kind = "index"
            elif tok.kind == "op" and tok.value == "[":
                self.next()
                self.expr()
                self.expect("]")
                kind = "index"
            elif tok.kind == "op" and tok.value == ":":
                self.next()
                self.name("method name")
                self.call_args(method=True)
                kind = "call"
            elif (tok.kind == "op" and tok.value in ("(", "{")) or tok.kind == "string":
                self.call_args()
                kind = "call"
            else:
                return kind

    def call_args(self, method=False):
        tok = self.peek()
        if tok.kind == "op" and tok.value == "(":
            if tok.line != self.prev().end:
                raise LuauError(tok.line, "ambiguous syntax: this '(' on a new line reads as a call to the line "
                                "before; put ';' between them or join the lines")
            self.next()
            if not self.is_(")"):
                self.exprlist()
            self.expect(")", "'(' at line %d" % tok.line)
        elif tok.kind == "op" and tok.value == "{":
            self.table()
        elif tok.kind == "string":
            self.next()
        else:
            raise LuauError(tok.line, "expected arguments for a %scall, got %s" % ("method " if method else "", describe(tok)))

    def table(self):
        start = self.expect("{")
        while not self.is_("}"):
            if self.is_("["):
                self.next()
                self.expr()
                self.expect("]")
                self.expect("=")
                self.expr()
            elif self.peek().kind == "name" and self.is_("=", 1):
                self.next()
                self.next()
                self.expr()
            else:
                self.expr()
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}", "'{' at line %d" % start.line)

    # --- types
    def type_alias(self):
        self.name("type name")
        if self.is_("<"):
            self.generic_list(defaults=True)
        self.expect("=")
        self.type_()

    def generic_list(self, defaults=False):
        self.expect("<")
        while True:
            self.name("generic type name")
            self.accept("...")
            if defaults and self.accept("="):
                if self.is_("(") or self.is_("..."):
                    self.return_type()
                else:
                    self.type_()
            if not self.accept(","):
                break
        self.expect(">")

    def type_(self):
        self.accept("|") or self.accept("&")
        self.simple_type_suffixed()
        while self.is_("|") or self.is_("&"):
            self.next()
            self.simple_type_suffixed()

    def simple_type_suffixed(self):
        self.simple_type()
        while self.accept("?"):
            pass

    def simple_type(self):
        tok = self.peek()
        if tok.kind == "keyword" and tok.value in ("nil", "true", "false"):
            self.next()
            return
        if tok.kind == "string":
            self.next()
            return
        if tok.kind == "name":
            self.next()
            if tok.value == "typeof" and self.is_("("):
                self.next()
                self.expr()
                self.expect(")")
                return
            if self.accept("."):
                self.name("type name")
            if self.is_("<"):
                self.type_args()
            return
        if tok.kind == "op" and tok.value == "{":
            self.table_type()
            return
        if tok.kind == "op" and tok.value in ("(", "<"):
            if self.paren_type() == "pack":
                raise LuauError(tok.line, "a type pack where a single type was expected")
            return
        raise LuauError(tok.line, "expected a type, got %s" % describe(tok))

    def type_args(self):
        self.expect("<")
        if not self.is_(">"):
            while True:
                if self.accept("..."):
                    self.type_()
                elif self.is_("("):
                    self.paren_type(pack_ok=True)
                else:
                    self.type_()
                    self.accept("...")
                if not self.accept(","):
                    break
        self.expect(">")

    def table_type(self):
        start = self.expect("{")
        if self.accept("}"):
            return
        first = True
        while not self.is_("}"):
            if self.is_("["):
                self.next()
                self.type_()
                self.expect("]")
                self.expect(":")
                self.type_()
            elif self.peek().kind == "name" and self.is_(":", 1):
                self.next()
                self.next()
                self.type_()
            elif self.is_name("read") or self.is_name("write"):
                if self.peek(1).kind == "name" and self.is_(":", 2):
                    self.next()
                    self.next()
                    self.next()
                    self.type_()
                else:
                    self.type_()
            elif first:
                # { T }: an array of T, and nothing else in the braces.
                self.type_()
                self.expect("}", "'{' at line %d" % start.line)
                return
            else:
                raise LuauError(self.peek().line, "expected a table type's field, got %s" % describe(self.peek()))
            first = False
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}", "'{' at line %d" % start.line)

    def paren_type(self, pack_ok=False):
        """At '(' or '<': a function type, a parenthesised type, or (where allowed) a type pack.
        Returns 'function', 'type' or 'pack'."""
        generic = False
        if self.is_("<"):
            self.generic_list()
            generic = True
        start = self.expect("(")
        count, variadic = 0, False
        if not self.is_(")"):
            while True:
                if self.accept("..."):
                    self.type_()
                    variadic = True
                else:
                    if self.peek().kind == "name" and self.is_(":", 1):
                        self.next()
                        self.next()
                    self.type_()
                    if self.accept("..."):
                        variadic = True
                count += 1
                if not self.accept(","):
                    break
        self.expect(")", "'(' at line %d" % start.line)
        if self.accept("->"):
            self.return_type()
            return "function"
        if generic:
            raise LuauError(self.peek().line, "a generic type list must be followed by a function type ('->')")
        if count == 1 and not variadic:
            return "type"
        if not pack_ok:
            raise LuauError(start.line, "a type pack where a single type was expected (missing '->'?)")
        return "pack"

    def return_type(self):
        if self.accept("..."):
            self.type_()
            return
        if self.is_("(") or self.is_("<"):
            kind = self.paren_type(pack_ok=True)
            if kind != "pack":
                while self.accept("?"):
                    pass
                while self.is_("|") or self.is_("&"):
                    self.next()
                    self.simple_type_suffixed()
            return
        self.type_()
        self.accept("...")

    def variadic_annotation(self):
        if self.is_("(") or self.is_("<"):
            self.paren_type(pack_ok=True)
            return
        self.type_()
        self.accept("...")


def check(path):
    text = path.read_text(encoding="utf-8")
    Parser(tokenize(text)).chunk()


def main():
    problems = []
    files = sorted(SRC.rglob("*.lua"))
    for path in files:
        try:
            check(path)
        except LuauError as error:
            problems.append("%s:%d  %s" % (path.relative_to(SRC.parent), error.line, error.message))
        except RecursionError:
            problems.append("%s  nests too deeply for this checker" % path.relative_to(SRC.parent))
    print("parsed %d Luau sources" % len(files))
    if problems:
        print("\nWOULD NOT COMPILE:")
        for p in problems:
            print("  " + p)
        sys.exit(1)
    print("every file parses as Luau.")


if __name__ == "__main__":
    sys.setrecursionlimit(20000)
    main()
