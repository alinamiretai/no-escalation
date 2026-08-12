# Appendix A — Worked Example and Conformance Test Vectors

Merge as Appendix A of `ext-noescalation-spec.md`.

---

## A.1 A worked delegation

A host agent is granted access to two repositories. It dispatches planning to a
planner, which dispatches a subtask to a worker. Each hop narrows.

### Stage 1 — host originates

The host's guard receives a `tools/call` with no inbound provenance. Its
disposition is `originate` (§5.5.1), so it constructs a chain and appends its
own hop:

```json
{
  "v": 1,
  "chain": [
    { "component": "host",
      "bound": [
        { "tool": "create_issue", "args": { "repo": { "in": ["acme/app", "acme/docs"] } } },
        { "tool": "read_file",    "args": { "path": { "prefix": "/srv/acme/" } } }
      ] }
  ]
}
```

**effbound** = the host's bound (one hop, nothing to intersect):
`create_issue` on `acme/app` or `acme/docs`; `read_file` under `/srv/acme/`.

### Stage 2 — planner narrows

The planner dispatches a subtask that only needs one repository. Its guard
appends a hop (§5.1) and MUST NOT modify the existing one:

```json
{
  "v": 1,
  "chain": [
    { "component": "host",
      "bound": [
        { "tool": "create_issue", "args": { "repo": { "in": ["acme/app", "acme/docs"] } } },
        { "tool": "read_file",    "args": { "path": { "prefix": "/srv/acme/" } } }
      ] },
    { "component": "planner",
      "bound": [
        { "tool": "create_issue", "args": { "repo": { "eq": "acme/app" } } }
      ] }
  ]
}
```

**effbound** = meet of both hops. Computed per §4.3:

- Across hops, bounds intersect. The planner's bound contains no `read_file`
  rule, so `read_file` drops out entirely.
- For `create_issue`, the argument constraints conjoin:
  `{"in": ["acme/app","acme/docs"]} ⊓ {"eq": "acme/app"}` = `{"eq": "acme/app"}`.

Result: **`create_issue` on `acme/app` only.** Note that `acme/docs` and
`read_file` are now unreachable for everything downstream of this hop, even
though the host conferred them.

### Stage 3 — worker calls

**Accepted call.**

```json
{ "method": "tools/call",
  "params": { "name": "create_issue", "arguments": { "repo": "acme/app", "title": "Fix login" } } }
```

Within effbound. `title` is unconstrained by the rule and therefore places no
restriction (§4.1). Forwarded with π attached.

**Rejected call — the confused deputy.**

```json
{ "method": "tools/call",
  "params": { "name": "create_issue", "arguments": { "repo": "acme/docs" } } }
```

`acme/docs` is inside the *host's* bound but outside the *planner's*. The meet
excludes it. This is the case a point-of-use authorization check cannot catch:
the worker holds a valid credential and the server would execute the call.
Rejected per §5.3:

```json
{ "jsonrpc": "2.0", "id": 7,
  "error": { "code": -32001,
    "message": "io.noescalation: 'create_issue' with these arguments is outside the conferred bound",
    "data": { "tool": "create_issue", "arguments": { "repo": "acme/docs" } } } }
```

**Rejected call — attempted re-amplification.**

Suppose the worker's own guard appends a hop conferring
`{"repo": {"in": ["acme/app", "evil/pwn"]}}` — wider than what it received.
Appending it is a violation of §5.1, but even if it occurs, the meet is
unaffected: `evil/pwn` appears in no earlier hop, so it is excluded by
intersection. Widening downstream cannot restore authority (`Kernel.lean`,
`meet_hop_sub`).

---

## A.2 Conformance test vectors

Each vector is a chain, a call, and the required verdict. A conforming guard
MUST produce the stated verdict for every vector. Machine-readable form:
`vectors.json` in the reference repository.

Bounds are abbreviated: `T{args}` denotes a rule for tool `T`.

### A.2.1 Composition

| # | Chain (bounds per hop) | Call | Verdict | Tests |
|---|---|---|---|---|
| C1 | `[ create{repo:eq acme/app} ]` | `create{repo:acme/app}` | **accept** | single hop, in bound |
| C2 | `[ create{repo:eq acme/app} ]` | `create{repo:acme/docs}` | **reject** | single hop, out of bound |
| C3 | `[ create{repo:in[app,docs]}, create{repo:eq app} ]` | `create{repo:app}` | **accept** | survives narrowing |
| C4 | `[ create{repo:in[app,docs]}, create{repo:eq app} ]` | `create{repo:docs}` | **reject** | **confused deputy** — in hop 1, not hop 2 |
| C5 | `[ create{repo:eq app}, create{repo:in[app,evil]} ]` | `create{repo:evil}` | **reject** | **re-amplification** — later hop cannot widen |
| C6 | `[ create{repo:in[a,b]}, create{repo:in[b,c]}, create{repo:in[b,d]} ]` | `create{repo:b}` | **accept** | three-hop intersection |
| C7 | same as C6 | `create{repo:c}` | **reject** | in hops 2 only |
| C8 | `[ create{...}, read{...} ]` where hop 2 omits `create` | `create{...}` | **reject** | tool absent from a hop drops out |

### A.2.2 Empty and degenerate

| # | Chain | Call | Verdict | Tests |
|---|---|---|---|---|
| E1 | `[ create{repo:eq app}, [] ]` | `create{repo:app}` | **reject** | empty bound admits nothing (§4.1) |
| E2 | `chain: []` | any | **reject** | empty chain confers nothing |
| E3 | absent π, disposition `reject` | any | **reject** | §5.5.1 |
| E4 | absent π, disposition `originate` | call in guard's own bound | **accept** | §5.5.1 |
| E5 | `v: 99` | any | **reject** | unrecognized version fails closed |
| E6 | malformed chain (hop missing `bound`) | any | **reject** | §5.3 |

### A.2.3 Constraint operators

| # | Constraint | Argument value | Result | Tests |
|---|---|---|---|---|
| O1 | `{eq: "acme/app"}` | `"acme/app"` | match | |
| O2 | `{eq: "acme/app"}` | `"acme/App"` | **no match** | case-sensitive by default (§4.2.2) |
| O3 | `{in: ["a","b"]}` | `"b"` | match | |
| O4 | `{in: ["a","b"]}` | `"c"` | no match | |
| O5 | `{prefix: "/srv/acme/"}` | `"/srv/acme/x.txt"` | match | |
| O6 | `{prefix: "/srv/acme/"}` | `"/srv/acme/../../etc/passwd"` | **no match** | **path traversal** — canonicalize first (§4.2.2) |
| O7 | `{prefix: "/srv/acme/"}` | `"/srv/acme/%2e%2e/x"` | **no match** | percent-decode then normalize |
| O8 | `{glob: "acme/*"}` | `"acme/app"` | match | |
| O9 | `{glob: "acme/*"}` | `"acme/app/sub"` | **no match** | `*` MUST NOT cross `/` (§4.2.4) |
| O10 | `{glob: "acme/**"}` | `"acme/app/sub"` | match | `**` crosses `/` |
| O11 | `{glob: "acme/app"}` | `"xacme/app"` | no match | anchored at both ends |
| O12 | `{glob: "f[a-c]o"}` | `"fbo"` | match | character class |
| O13 | `{prefix: "/srv/"}` | `12345` (number) | **no match** | type mismatch, no coercion (§4.2.1) |
| O14 | `{glob: "a*"}` | `null` | **no match** | type mismatch |
| O15 | `{eq: 5}` | `5.0` | match | numeric equality (§4.2.3) |
| O16 | `{glob: "a[b"}` | any | **malformed** | invalid pattern rejected, not recovered |

### A.2.4 Meet of constraints

The meet MUST be exact: it MUST NOT admit a value outside either input, and
MUST NOT exclude a value inside both.

| # | Constraint A | Constraint B | Required meet | Tests |
|---|---|---|---|---|
| M1 | `{in: [a,b,c]}` | `{eq: b}` | `{eq: b}` | reduces |
| M2 | `{in: [a,b]}` | `{in: [b,c]}` | `{in: [b]}` | set intersection |
| M3 | `{in: [a]}` | `{in: [b]}` | **empty** — rule dropped | disjoint |
| M4 | `{prefix: "/srv/"}` | `{prefix: "/srv/acme/"}` | `{prefix: "/srv/acme/"}` | one implies other |
| M5 | `{prefix: "/a/"}` | `{prefix: "/b/"}` | **empty** — rule dropped | disjoint prefixes |
| M6 | `{eq: "acme/app"}` | `{glob: "acme/*"}` | `{eq: "acme/app"}` | eq tested against glob |
| M7 | `{eq: "acme/app/x"}` | `{glob: "acme/*"}` | **empty** | eq fails the glob (O9) |
| M8 | `{glob: "a*"}` | `{prefix: "ab"}` | `{prefix: "ab"}` or `and` | either exact form |
| M9 | `{glob: "*x"}` | `{glob: "y*"}` | `{and: [both]}` | no single-operator form; conjunction is exact |
| M10 | `{and: [X,Y]}` | `{Z}` | `{and: [X,Y,Z]}` | conjunction is associative |

**Soundness requirement.** For every meet vector, a guard MUST NOT admit a
value admitted by only one input. Vector M7 is the sharpest case: a naive
implementation reducing `eq ⊓ glob` to `eq` without testing membership admits
`acme/app/x`, which the glob excludes.

### A.2.5 Rules and arguments

| # | Bound | Call | Verdict | Tests |
|---|---|---|---|---|
| R1 | `[create{repo:eq a}, read{path:prefix /p/}]` | `read{path:/p/x}` | **accept** | union within a bound |
| R2 | `[create{repo:eq a}]` | `delete{repo:a}` | **reject** | tool not in bound |
| R3 | `[create{repo:eq a}]` | `create{repo:a, title:"anything"}` | **accept** | unconstrained arg unrestricted |
| R4 | `[create{repo:eq a}]` | `create{title:"x"}` | **reject** | constrained arg absent (§4.1) |

---

## A.3 Using these vectors

A guard passing A.2 satisfies the mechanical requirements of §4 and §5.5.1.
It does **not** thereby satisfy §5.5 (chain integrity) or §5.6 (declared
unmediated set), which are deployment properties and cannot be established by
testing the guard in isolation.
