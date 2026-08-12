"""
canonical.py — canonicalization (spec §4.2.2) and the glob dialect (§4.2.4).

These exist because the spec pass found two live bypasses in `Constraint.matches`:

  * `prefix` was string-prefix only, so "/srv/acme/../../etc/passwd" satisfied
    a bound of prefix "/srv/acme/" — classic path traversal.
  * `glob` used fnmatch, whose `*` crosses "/", so a bound of "acme/*" admitted
    "acme/app/sub". The spec requires `*` to stop at the separator and `**` to
    cross it, because a bound written as "acme/*" must not silently widen.

Both were permissive, i.e. they admitted calls the bound excluded.
"""

import re
import unicodedata
from urllib.parse import unquote

SEP = "/"
_MAX_DECODE_ROUNDS = 3


class Malformed(ValueError):
    """Value cannot be canonicalized; the call must be rejected (§4.2.2)."""


# ---------------------------------------------------------------------------
# §4.2.2 Canonicalization
# ---------------------------------------------------------------------------

def canonicalize(value, *, path_like: bool = True, fold_case: bool = False):
    """
    Canonicalize a value before constraint evaluation.

    Non-strings are returned unchanged (type compatibility is handled by the
    caller, §4.2.1). Strings get NFC, bounded percent-decoding, and — when
    path_like — path normalization.

    Raises Malformed if the value cannot be canonicalized, which the caller
    MUST treat as a rejection rather than matching against the raw value.
    """
    if not isinstance(value, str):
        return value

    # 1. Unicode normalization
    s = unicodedata.normalize("NFC", value)

    # 2. Bounded percent-decoding, repeated until stable
    for _ in range(_MAX_DECODE_ROUNDS):
        decoded = unquote(s)
        if decoded == s:
            break
        s = decoded
    else:
        if unquote(s) != s:
            raise Malformed("percent-encoding did not stabilize")

    # NFC again: decoding can introduce composable sequences
    s = unicodedata.normalize("NFC", s)

    if path_like:
        s = _normalize_path(s)

    if fold_case:
        s = s.casefold()

    return s


def _normalize_path(s: str) -> str:
    """
    Resolve '.' and '..', collapse repeated separators, drop a trailing
    separator. A value that escapes its own root is Malformed rather than
    normalized to something else (§4.2.2).
    """
    if s == "":
        return s

    absolute = s.startswith(SEP)
    parts = [p for p in s.split(SEP) if p not in ("", ".")]

    out = []
    for p in parts:
        if p == "..":
            if out:
                out.pop()
            else:
                # escapes the root: refuse rather than silently clamp
                raise Malformed("path escapes its root")
        else:
            out.append(p)

    joined = SEP.join(out)
    return (SEP + joined) if absolute else joined


# ---------------------------------------------------------------------------
# §4.2.4 Glob dialect
# ---------------------------------------------------------------------------

def glob_to_regex(pattern: str) -> "re.Pattern":
    """
    Compile a §4.2.4 glob to an anchored regex.

        ?           one char, not SEP
        *           zero or more chars, not SEP
        **          zero or more chars, including SEP
        [abc] [a-z] one char from set/range
        [!abc]      one char not in set
        \\x          literal x

    Raises Malformed on an invalid pattern (unterminated '[', trailing '\\').
    """
    out = ["\\A"]
    i, n = 0, len(pattern)

    while i < n:
        ch = pattern[i]

        if ch == "\\":
            if i + 1 >= n:
                raise Malformed("trailing backslash in glob")
            out.append(re.escape(pattern[i + 1]))
            i += 2
            continue

        if ch == "*":
            if i + 1 < n and pattern[i + 1] == "*":
                out.append(".*")          # ** crosses SEP
                i += 2
            else:
                out.append(f"[^{re.escape(SEP)}]*")
                i += 1
            continue

        if ch == "?":
            out.append(f"[^{re.escape(SEP)}]")
            i += 1
            continue

        if ch == "[":
            j = i + 1
            negate = False
            if j < n and pattern[j] in ("!", "^"):
                negate = True
                j += 1
            if j < n and pattern[j] == "]":   # literal ']' as first member
                j += 1
            while j < n and pattern[j] != "]":
                j += 1
            if j >= n:
                raise Malformed("unterminated '[' in glob")
            body = pattern[i + 1:j]
            if negate:
                body = body[1:]
                out.append(f"[^{_escape_class(body)}]")
            else:
                out.append(f"[{_escape_class(body)}]")
            i = j + 1
            continue

        out.append(re.escape(ch))
        i += 1

    out.append("\\Z")
    return re.compile("".join(out), re.DOTALL)


def _escape_class(body: str) -> str:
    """Escape a character-class body, preserving ranges."""
    return body.replace("\\", "\\\\").replace("]", "\\]").replace("^", "\\^")


def glob_match(value: str, pattern: str) -> bool:
    """Whole-value match under the §4.2.4 dialect."""
    if not isinstance(value, str):
        return False
    return glob_to_regex(pattern).match(value) is not None
