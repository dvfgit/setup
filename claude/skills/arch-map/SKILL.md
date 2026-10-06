---
name: arch-map
description: Analyze a codebase subsystem and produce an interactive architecture relationship map — a clickable dependency graph where selecting a component isolates its edges and lists what it depends on and what depends on it, each edge naming the real call site. Use when asked to "map the architecture", "show how these pieces relate", "diagram this integration/subsystem", "what depends on what", "generate an architecture map/graph", or "/arch-map". Produces a self-contained HTML file that opens locally or publishes as an Artifact.
---

# ARCH-MAP Task

## Objective

Turn a subsystem of a codebase into an **interactive relationship graph**: nodes are
modules with a distinct responsibility, edges are real call sites, and clicking a node
isolates its edges while a side panel lists its dependencies in both directions.

The point is not to draw boxes. It is to let a cold reader see a mechanism they would
otherwise have to assemble by reading twenty files.

## When to use

- "Map the architecture of X", "how do these packages relate", "diagram this integration"
- Onboarding onto an unfamiliar subsystem
- Preparing to explain a system in a review, a design doc, or an interview
- Before a refactor, to see what a change would touch

**Do not use** for a whole repo at once, for a single file, or when a three-sentence
answer would do. A graph with 40 nodes teaches nothing.

## Workflow

### 1. Scope it

A map answers one question. Pin the question before reading any code.

Good scopes: one integration, one request path, one data pipeline, one bounded context.
Bad scopes: "the repo", "the backend".

If the user named a vague target, ask which subsystem — one question, then proceed.
If they named a concrete one, do not ask; start reading.

### 2. Trace, do not inventory

Start from the boundaries and follow the calls. Do not walk the directory tree.

- **Entry points** — HTTP/GraphQL routes, queue consumers, CLI commands, cron, webhooks.
  Grep for route registration, resolver maps, handler exports.
- **External edges** — SDK clients, `fetch`/`axios` wrappers, vendor packages in
  `package.json`. These become `kind:"ext"` nodes.
- **The data layer** — ORM client, migrations, repositories.
- **Then follow imports between them**, reading enough of each file to name the actual
  function being called.

Delegate wide searches to subagents only if the user's setup allows it; otherwise
Grep and Read directly. Prefer reading a few files fully over skimming many.

### 3. Model it

**Nodes — aim for 8 to 16.**

- A node is a *module with one responsibility*, not a file and not a directory.
  Collapse `foo/index.ts`, `foo/lib/*.ts` into one `foo` node.
- Split a package into two nodes only if the halves have genuinely different
  responsibilities and different callers.
- External systems get nodes (`kind:"ext"`), so the trust boundary is visible.
- If you are over 16, your scope is too wide. Narrow it rather than shrinking the boxes.

**Edges — every one must name a real call site.**

This is the quality bar that makes the map worth more than a whiteboard sketch.
The `v` field takes a function name, symbol, route, or SQL verb:

```
GOOD  v:"fetchDealWithAssociations"      v:"POST /webhooks/deal"
      v:"prisma.$transaction"            v:"workflow.start via trigger package"
BAD   v:"uses"     v:"talks to"     v:"depends on"     v:"integrates with"
```

If you cannot name the call after reading the code, it is not an edge. Delete it.

**Edge kinds — pick a vocabulary that fits the domain.** The template ships four.
The default set works for most service code:

| kind | meaning |
|---|---|
| `control` | starts work: a request, a trigger, a job enqueue |
| `data` | reads or writes: API calls, queries, writes |
| `host` | build and runtime wiring: bundling, registration, DI |
| `type` | types and schemas only, no runtime call |

Separating `type` from `data` is often the highest-value distinction — it exposes
schemas that are declared but never enforced at runtime.

**Rows** encode the direction of flow. Entry points and external systems at row 0,
storage at the last row. Put mutually-dependent peers in the same row.

### 4. Render

Copy the template and replace only the data block:

```
cp ~/.claude/skills/arch-map/assets/graph-template.html <scratchpad>/<name>.html
```

Then edit, in this order:

1. `<title>`, the masthead (`kicker`, `h1`, `standfirst`), the intro paragraph, and the
   closing `.note` — all marked `REPLACE`.
2. `KINDS` — rename to the chosen vocabulary.
3. `NODES` — `id`, `label`, `sub` (the repo path), `row`, `role`, `body`.
   `body` is 2–3 sentences and takes inline `<code>`.
4. `EDGES` — `f`, `t`, `k`, `v`.
5. `DEFAULT_SELECTED` — the node the map should open on. Choose the chokepoint,
   not the entry point; leave `null` to auto-pick the busiest node.

**Positions are computed.** Do not hand-write coordinates or SVG paths. The router
lays out rows, spreads anchors, allocates lanes, and picks side corridors. If one
specific edge routes badly, set `d:"M … H … V …"` on that edge only.

The closing `.note` should state the one structural fact the graph makes obvious —
an odd-one-out node, a missing edge, a single chokepoint. If you cannot name one,
the map probably is not worth publishing.

### 5. Review the map against the code

**This step is not optional and it is not a re-read of your own notes.** A first-draft
graph is built from what you happened to open. This pass is built from what is actually
imported. On a real subsystem it routinely finds four to six relationships the draft
missed, and it is the difference between a map that looks right and one that is right.

Run all six checks. Then state in your summary what the pass changed.

**A. Reconcile every node against its real imports.** Not the ones you remember reading.

```bash
for f in $(find <pkg>/src -name "*.ts"); do
  echo "-- $f"; grep -hoE 'from "[^".][^"]*"' "$f" | grep -v '\.js"'
done
```

Every cross-package import is a candidate edge. If it is in the list and not in your
graph, you either missed it or you can justify leaving it out. Resolvers are the usual
offender: people read the helper a resolver calls and never open the resolver.

**B. Hunt orphans and half-orphans.** A node with no inbound edges is a service nobody
calls. A node with no outbound edges is a leaf that talks to nothing. Both are almost
always wrong.

```js
NODES.filter(n => !EDGES.some(e => e.t === n.id))  // nothing depends on it
NODES.filter(n => !EDGES.some(e => e.f === n.id))  // it depends on nothing
```

"Used by: nothing" on an API surface means you have not found its consumer yet.

**C. Sweep the siblings of every feature directory you mapped.**

```bash
ls apps/*/src/features/ packages/*/src/
```

The single most-missed thing is a second copy of the same feature serving a different
audience — a participant version beside a coach version. Directory typos hide these from
a targeted grep, so list the parent instead of searching for the name you expect.

**D. Prove every node you drew is really a caller.** A component containing a TODO and a
`<div>` is not a consumer. If you cannot point at the call, the node is fiction and the
edge is worse than missing, because it asserts something false.

**E. Before deleting an orphan, ask who calls it from outside the repo.** Mobile and
native clients, other services, and webhooks leave no import to grep. A public surface
with no in-repo caller is usually an external consumer, not dead code. Model it as a
`kind:"ext"` node with the operation names as the edge, rather than dropping it.

**F. Sweep auth on every client-facing entry point.** For each one, answer two questions:
what rule guards it, and is the acting identity derived from the session or taken from
client input?

```bash
grep -rn "<operationName>" apps/*/src/graphql/permissions.ts apps/*/src/**/*permission*
```

Arguments that are declared and never read are worth noting — a `fundraiserId` the
resolver ignores is a scoping check someone intended and did not finish.

### 6. Deliver

Do not publish before step 5 is done. A map that quietly omits a relationship is
worse than no map: it will be trusted.


**Locally** — the file is self-contained and needs no server:

```
open <path>.html
```

It deliberately omits `<!doctype>`/`<html>`/`<body>`, which browsers supply. That same
property makes it publishable as-is.

**Published** — call the `Artifact` tool with the file path, a `favicon`, and a
one-sentence `description`. Republishing the same path keeps the URL.

Ask which the user wants only if they have not said; default to publishing when the
map is a deliverable someone else will read, local when it is for the user's own
immediate use.

## What the template gives you

- Click or keyboard-select a node: its edges light, neighbours stay solid, the rest dims
- Side panel with **Depends on** / **Used by**, each row naming the call site
- Hovering a panel row solos that single edge
- Panel rows are clickable, so you can walk the graph
- Filter chips to hide an edge kind
- `#node-id` deep links, so a specific view is shareable
- Light/dark/system themes, phone-width layout, reduced-motion respected

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Graph looks like a hairball | scope too wide | one subsystem, not the repo |
| Edges say "uses", "calls" | never read the call site | read the file, name the symbol |
| Everything in one row | rows not assigned | rows encode flow direction |
| Two nodes with identical edges | over-split | merge them |
| Nothing interesting when clicking | nodes are directories | nodes are responsibilities |
| Path crosses a box | rare router case | manual `d` on that one edge |
| A node shows "used by: nothing" | consumer not found, or it is external | check C and E before deleting it |
| An edge you cannot point at a line for | inferred from a name or a folder | delete it, or go read the call |
| Two nodes with near-identical bodies | you mapped one of a duplicated pair | check C; the twin usually exists |

## Notes

- Read the code. Never infer a relationship from a package name or a directory layout.
- If you find a real problem while tracing (a schema declared but never parsed, a
  round-trip that does not round-trip), say so alongside the map. That is usually the
  most valuable output, and the graph is what makes it legible.
- The template's router lives between `/*--ROUTER-START--*/` and `/*--ROUTER-END--*/`
  and is pure. To debug layout, slice it out and run it under `node`.
