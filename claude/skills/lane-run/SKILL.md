---
name: lane-run
description: Run one ticket end-to-end as an isolated lane — worktree from latest default branch, bootstrap, implement, verify in a real browser, review, against a live tracker artifact published at the start and updated at every stage. Built for several lanes running unattended overnight without colliding. Triggers on "/lane-run", "run this lane", "start a lane for <ticket>", "run these tickets overnight".
---

# Lane run

A **lane** is one ticket taken from brief to reviewed branch in its own worktree, with its own
port, its own database, and a live tracker artifact published at the start and updated at every
stage. Several lanes can run at once — the rules below are what keep them from destroying each
other.

This skill is written from a night that cost real time. Every rule traces to something that
actually broke, not to a hypothetical.

## The four laws

These override convenience. When a step below conflicts with one of these, the law wins.

1. **Own the gates. Dispatch what has no gate.** Sub-agents reliably write sound code and then fail
   to *close* — they stall on a slow gate, or hand back something unverified. The conclusion is not
   "never dispatch", it is that **closing is yours**: browser verification, review triage, the
   formatter, the push. What has no gate to stall on — read-only investigation above all — is
   dispatched to Sonnet under the delegation policy below. A dispatched investigation that fails
   costs one wasted call; a dispatched gate costs the night.
2. **One heavy job at a time.** Contention causes failed pushes, starved processes, and bogus test
   failures you then have to disprove. A "failure" produced under load costs more than the
   serialization would have.
3. **Browser-check before declaring done.** Verifying after you have called it finished is how a
   merge-ready PR gets re-opened. The check is part of the work, not a receipt for it.
4. **Never split a lane across work that shares a file.** Two lanes editing one schema or one
   shared component is not parallelism, it is a merge conflict with extra steps. Merge them into a
   single lane instead — one owner per file, always.

## Delegation policy

Law 1 splits the lane in two. This is the line.

### Dispatch to Sonnet

Use `subagent_type: "Explore"` for read-only work and `"Developer"` for bounded edits, both with
`model: "sonnet"`. Sonnet is the default because a lane's dispatched units are narrow and
well-specified; reach for a stronger model only when a unit comes back wrong twice.

| Dispatch | Because |
| --- | --- |
| **Per-unit investigation** — "how does control X persist, and where does it break?" | Read-only. Nothing to close, so law 1's failure mode cannot occur |
| **Repo reconnaissance** — locating the handler/mutation/route for each item in a list | Pure fan-out over independent targets |
| **Bounded mechanical fixes** — same edit shape applied to N files, boundary named per unit | The pattern is already decided; only application is delegated |
| **Evidence capture and PR body drafting** | Separable side-work, as before |

### Never dispatch

Browser verification · review triage · the formatter · `git push` · the merge of the default
branch · the decision that the lane is done. These are the gates. Law 3 exists because a lane that
verifies after declaring done re-opens a merge-ready PR, and a sub-agent reporting "verified" is
not verification.

### Rules that make the dispatch pay

- **Two or more independent units, or do it yourself.** A sub-agent re-injects the full system
  prompt and every MCP tool schema on each turn — field reports put the overhead near 10x. One unit
  never repays that. A list of eleven controls does.
- **Fan out in one message.** Multiple `Agent` calls in a single block run concurrently; separate
  blocks serialize and you have paid the overhead for nothing.
- **One unit, one owner, one named boundary.** Give each sub-agent the exact files it may touch.
  Two sub-agents editing one shared file is law 4 violated *inside* a lane, and it is harder to see
  there than across lanes.
- **Findings are claims until you check them.** Require `file:line` in every report and confirm the
  ones you act on. A sub-agent that cannot find the code will describe plausible code that does not
  exist — the same invention failure pre-flight check 1 guards against.
- **A shared-file fix collapses back to you.** The moment two units' fixes land in the same file,
  stop dispatching and apply that edit yourself.
- **Forbid repo-global git commands in the dispatch itself.** Every unit prompt says: no `git
  stash`, no `git reset`, no `git checkout -- .`, no branch switching. A sub-agent reaching for one
  to "compare against a clean baseline" blanks the working tree for every other unit and for you —
  and the damage is invisible until someone's `git status` lands inside the window. Naming the
  ban in the prompt is cheaper than diagnosing it afterwards.
- **A required field beats an optional one with a safe default.** When a dispatched change adds a
  flag that governs whether something writes, make it required: the compiler then enumerates every
  call site and forces each owner to state intent. An optional flag defaulting to "don't write"
  looks safe and silently disables the behaviour at callers nobody revisited.
- **Serialize anything heavy** — law 2 does not relax because the work is dispatched. Sub-agents
  running installs, migrations or suites concurrently produce exactly the contention failures law 2
  exists to prevent.

## Repo profile

Fill this once per repo before the first lane. Without it, the pre-flight cannot run and the lane
does not start. Keep it in the repo's own agent instructions, or paste it into the invocation.

| Field | What it is |
| --- | --- |
| `default_branch` | branch lanes cut from — always the *latest* remote state, never another lane's branch |
| `branch_pattern` | the remote's branch-name rule, if it has one. Rejected names cost a full push cycle to discover |
| `bootstrap` | ordered setup commands (see below) |
| `dev_command` | how to start the app **on a specified port** |
| `port_range` | one port per lane, assigned up front |
| `format_command` | the formatter CI enforces, and which file types it covers |
| `scoped_test` | how to run tests for a subset of files |
| `verify_url` | a URL that proves the app is up and serving the lane's surface |
| `banned` | commands that are unsafe in a worktree for this repo |

**Bootstrap order is load-bearing.** Dependency install, then client/codegen, then schema, then
seed. Running a seed against a stale generated client fails with an error that looks like a data
problem and is not.

## Pre-flight

Run every check before touching code. **All must pass or the lane does not start.** Failing here
costs a minute; failing at 2am costs the night.

0. **The ownership boundary is uncontended — and most apparent owners are not real ones.** Law 4 is
   otherwise only a principle for *choosing* lanes, with nothing enforcing it at run time. But a
   naive check over-reports badly: on a mature component, most branches touching a file are
   finished or abandoned work, not competition. Classify with three signals, in this order.

   **a. Tip versus tip, not commit ancestry.** A squash-merged branch keeps commits that are "not
   in the default branch" by SHA forever, so ancestry always looks divergent. Compare the file at
   both tips instead — identical means the work already landed.

   ```
   git -C "$d" diff --quiet <default_branch> HEAD -- <boundary paths>   # exit 0 = merged, not contention
   ```

   **b. The tracker decides what is previous work — git cannot.** A branch whose ticket is Done,
   Validation, or otherwise completed is finished work whose worktree simply still exists. Commit
   counts and staleness heuristics do not separate these; ticket status does. Look it up.

   **c. What survives a and b is the real owner.** And the right response is usually *not* a new
   lane: if a live lane already owns that file, **fold the work into it** rather than opening a
   second lane against the same file. That is law 4 applied correctly — one owner per file, and
   the owner is whoever is already there.

   Shell note: in `zsh` an unquoted variable holding several paths does **not** word-split, so
   `-- $PATHS` silently matches nothing and every branch reports clean. Pass paths as separate
   quoted arguments.

1. **Every path the brief references resolves inside the worktree, and its values still hold.** A
   brief that cites support docs by path is worthless if those docs live on an unmerged branch —
   the lane will not error, it will *invent* the values and look like it worked. Abort naming the
   missing file.

   **Re-confirm measured values against the current default branch.** Briefs go stale: a
   divergence recorded last week may already be fixed, and a lane sent to fix it will either do
   nothing or invent a change. Check that the thing you are about to fix is still broken.

   **The reproduction gate — for a bug-fix lane, run this before anything else.** Stand up a
   container built from the current default branch and try to reproduce the report on it. If it
   does not reproduce, **the lane does not start**: report "not reproducible on `<branch>@<sha>`",
   close the ticket against whatever shipped the fix, and stop. No worktree, no bootstrap, no
   branch.

   This is the cheapest check in the skill and it skips the most work. Client reports are filed
   against a *released runtime tag*, which can be weeks behind the default branch — so a large
   share of them are already fixed before anyone picks them up. In one session this gate would
   have pre-empted two full investigations and eight duplicate tickets in the same cluster, every
   one of them a stale-runtime false positive.

   A container is what makes the answer definitive, and it must be built from the default branch,
   not pulled from a release tag: a released image is a different commit, so it can only tell you
   the bug exists *somewhere*, never that it is still there. Reading the source and the git log
   can suggest the fix landed; only running the thing proves it. Keep the container up — it is
   also the Before/baseline for the A/B if the lane does proceed — and stop it at teardown.

   **Unverified in this repo as written.** It has a `Dockerfile`, a `DOCKER.md` and a
   `pnpm docker:pull` wrapper, and its tickets cite published runtime images, so the affordances
   exist — but the exact build-from-branch invocation has not been run end to end here. Prove it
   once and record the working command in the repo profile before relying on it.
2. **The assigned port is free.** If the dev command hardcodes a port, it will silently attach to
   another lane's server and verify the wrong app.
3. **Permission smoke test.** Run one harmless instance of every command family the lane needs —
   status, a PR read, the formatter's version, a scratch `Write`, a health `curl`. If any prompts
   or is denied, stop and name it. An unattended lane that hits a permission prompt mid-run is
   simply idle until a human returns.
4. **Bootstrap completed in profile order**, and the dev server answers `verify_url`.

## The lane runs to completion

Once pre-flight passes, a lane is a **one-way process**. It runs brief → tracker → worktree →
implement → verify → review → gates → commit → push → blind review → PR → tracker marked done
without checking in, and it is built to do that unattended overnight with nobody awake to answer.

**The stop conditions table below is the exhaustive list of reasons to pause.** Finishing a step
successfully is not one of them. "Gates are green, shall I continue?" and "ready for the PR, want
me to proceed?" are defects, not diligence: they stall the lane behind a human who was never
asked to be present, and on an overnight run they cost the whole night.

Report progress by *doing the next step*, not by asking whether to. The owner interrupts if they
want to redirect; silence is not a request for a status check. If a real stop condition fires,
stop and mark the tracker blocked — that is the one time a lane hands control back.

### 1 · Brief

A brief carries four things, and the lane refuses to start without all four: the **goal**, the
**measured values or acceptance criteria**, the **file-ownership boundary**, and the
**verification command**. Anything vaguer and the implementation invents scope.

**A component is not a deliverable until it is mounted.** Building it in isolation and verifying it
in a component workbench is a legitimate *step*, never the finish line — a lane that ends with a
component nothing renders has shipped nothing a user can reach. Every lane's boundary therefore
includes its integration point, and its verification runs against the real screen. If the
integration is genuinely blocked, that is a stop condition to report, not a scope to quietly drop.

### 2 · Tracker, then worktree

**Publish the tracker before the worktree exists.** It is the one durable, shareable surface for
the lane — publishing it only at the end proves the lane finished, never that it started, and an
overnight lane that dies silently between pre-flight and step 7 leaves nothing for the owner to
find. Publish first; every step after this one updates it, nothing re-publishes it.

**This is not optional, and a partial invocation does not waive it.** "Use the dev and
verification steps of /lane-run" still gets a tracker. If you skip any step of this skill, say so
in chat when you skip it, never after.

**If the invocation passes a tracker URL, adopt it — do not republish.** Read it with the Artifact
tool (`action: "read"`) and read its `lane/status` doc. The lane's job is to update that tracker,
not create a second one that splits the owner's attention.

#### Start: one publish, one write

The template (`templates/lane-tracker.html`) carries the whole page: layout, the default
checklist and the stage stepper. The database only holds what the lane actually knows. Starting a
lane is therefore two calls, and nothing is seeded.

1. **Publish.** Run the Artifact tool's `quickstart` (`intent: "other"`) once, which carries the
   page contract the template already meets, and load `artifact-capabilities` (the tool requires
   it before any `capabilities`). Fill only `{{TICKET}}`, `{{TITLE}}` and `{{TICKET_URL}}` into a
   copy of the template in the scratchpad (`sed`), then publish it with an `icon` and:

   ```
   capabilities: {"db":{"rules":[{"path":"","read":"view","write":"admin"}]},"assets":{}}
   ```

   `assets` is required: the page's CSP blocks images from GitHub and every other host, so
   evidence GIFs must live in the tracker's own asset store.

2. **Write the start state** in one `ArtifactData` batch: `lane/status` and `lane/brief`.

   ```
   lane/status  { phase: "setup",
                  now:  "Cutting the worktree from origin/<default-branch> @ <sha>",
                  next: "Bootstrap, then red tests",
                  branch, worktree, port, updatedAt }
   lane/brief   { goal, acceptance: [...], boundary: [...], verify: [...],
                  links: [{ label, url }] }       // ticket, PR if one exists, triage (bug lanes only)
   ```

   The four `lane/brief` fields are the four things step 1 requires. Write them as plain strings and
   arrays; the page renders them. Never hand-write HTML.

Don't write the 14 checklist tasks: their ids, titles and stages are built into the page. Write
`tasks/<id>` only when one changes (`{status, note, updatedAt}`). `{hidden: true}` removes a
default that doesn't apply, and a new id needs `group` (one of the six stages below), `title` and
`order`.

#### Triage: bug lanes only

A triage artifact exists only when the lane fixes a bug that went through a triage skill or a
comparable triage. In that case:
- add it to `lane/brief.links` as `Triage`;
- when the lane is done, change the triage page's recommendation header to point at the tracker, so
  the triage page stops reading as a pending action.

Feature lanes have no triage page. Don't create one, and don't list one.

#### Update at every stage boundary, not just at the end

`lane/status.phase` is the stage **in progress**. The page's stepper colors every earlier stage
done, the current one teal and later ones grey. So write the next stage's name at the moment the
previous one finishes.

| Stage | Owns tasks | `phase` while it runs | Finished when |
| --- | --- | --- | --- |
| Setup | t10–t12 | `setup` | worktree cut, bootstrapped, Before evidence captured |
| Build | t20–t23 | `build` | red tests now green, mounted, E2E green |
| Verify | t30–t31 | `verify` | gates green, browser-verified, After GIF captured |
| Review | t32–t33 | `review` | two review passes triaged, blind review PASS |
| PR | t40–t41 | `pr` | PR open/updated, required CI green, ticket comment posted |
| Done | t50 | `done` | teardown confirmed (write `phase: "done"` only after it) |

Anything that stops the lane sets `phase: "blocked"`. The stepper shows the first stage with
unfinished tasks in red, and `now` states the stop condition.

Each boundary is **one** `ArtifactData` batch, pinned with `if_version` from your last read of
each doc:
- `lane/status` with the new `phase`, `now` and `next`, which are one sentence each;
- the `tasks/<id>` entries that moved;
- at most one `log/main` entry.

`now` and `next` are the first thing the owner reads. Make them state a position ("Blind review
running on 2456856c9") or a wait ("Waiting on a human to merge #2408"), never an intention ("working
on it").

Results go in their own docs, not the log:

| Doc | Written when | Shape |
| --- | --- | --- |
| `lane/gates` | each gate run (step 6) | `{items: [{name, command, result: pass·fail·skip·running, detail, at}]}` |
| `lane/reviews` | each review pass returns (step 5, blind review in 7) | `{items: [{name, verdict, at, findings: [{summary, where, disposition: fixed·rejected·parked·blocking·open}]}]}` |
| `lane/evidence` | each GIF/still (steps 2, 4) | `{items: [{label, url, provenance}]}`. Upload with Artifact `asset: true` (`file_paths` for several), then store the returned `/_blob/…` url |
| `lane/parked` | a finding is parked or needs a decision | `{items: [{summary, where, why}]}` |
| `log/main` | stage boundaries and stop conditions **only** | `{items: [{at, text}]}`, newest first, ≤ 40. The page shows 3 and folds the rest |

**Every section of the page has to tell the same story.** If the log says "red → green, gates
passing" while `lane/gates` is empty and the checklist still shows Setup, the page contradicts
itself, and the owner trusts the empty section. Rules that prevent this:

- **Write the result doc in the same step that produces the result.** When a test run, a gate, a
  review, or a GIF finishes, its `lane/gates`/`lane/reviews`/`lane/evidence` row goes into the
  *next* `ArtifactData` call. Never batch results "for later". A gate result that exists only in
  chat or in a log line counts as unrecorded.
- **A phase change carries its tasks.** A batch that advances `lane/status.phase` must also set
  every `tasks/<id>` of the stage it closes (`done`, `skip` with a reason, or `blocked`). Moving
  the stepper while the stage's tasks are untouched is a defect.
- **Red tests are a gate row too.** Record the red run (what failed and on which assertion) as a
  `lane/gates` row when it happens, then the green run as its own row. Don't wait for step 6.
- **Self-check before each status write.** Before writing `lane/status`, ask: do `lane/gates`,
  `tasks/*` and `lane/evidence` already show everything that `now` and the log claim? If not,
  put the missing rows in the same batch.

A note is a measured fact, never an intention. "t23 done — 6/6 e2e specs green,
`custom-definitions-navigation.spec.ts`" carries information a reviewer can check; "e2e looks
good" does not. Use a real UTC timestamp for every `updatedAt`, `at` and log entry
(`date -u +%Y-%m-%dT%H:%M:%SZ`), never an estimate.

After the first write, check the page once: one `ArtifactData` `get` of `lane/status`.

Cut the worktree from the latest `default_branch`. Never from another lane's branch. Name it to
match `branch_pattern`.

Then bootstrap in profile order.

### 3 · Implement

Investigate wide, then implement. Fan investigation out to Sonnet per the delegation policy — for a
ticket listing N broken items, that is N read-only units in one message, each returning
`file:line` and a proposed fix shape. Confirm what comes back before acting on it.

Then apply: directly when the fixes converge on shared files, dispatched as bounded units when they
genuinely do not. Either way the boundary rules hold — keep inside the file-ownership boundary, and
touching a file another lane owns is a stop condition, not a judgement call.

**Writes go through the file tools, never shell heredocs.** `Write`/`Edit` are covered by
edit-accepting permission modes; a `cat > file` heredoc is a shell command and prompts every time.
This single habit is the difference between a lane that runs unattended and one that stalls.

**Never `cd`. Target the worktree with a flag.**

```
git  -C   <worktree> status
pnpm --dir <worktree> test <paths>
grep -n pattern <worktree>/path/to/file        # absolute path as an argument
```

`cd <worktree> && …` prefixed onto every command is **the single largest source of permission
prompts in a lane**. The checker cannot resolve a `cd` target inside a compound command, so it asks
— every time — for commands that would otherwise pass silently. Unattended, that is a lane that
does nothing all night.

And do not try to fix it with one `cd` up front: **many harnesses reset the working directory after
every call**, so the directory does not persist and every later bare command runs in the wrong
place. Verify before relying on it — if the tool result says the cwd was reset, `cd` is useless
here.

Flags and absolute paths always work, need no state, and never prompt. Use them exclusively.

**Use a fixed command vocabulary. Do not improvise shell.** An allowlist can never cover a command
nobody predicted, so the lane must not invent one. Every stall observed so far came from an
improvised shape, not a missing entry — `node -e` to parse a file where `grep` would do, a `cd`
into a path containing shell-significant characters. Stay inside: the file tools, `git`, the
package manager's own scripts, and plain `grep`/`ls`/`cat`. When something seems to need a new
command shape, that is the signal to use a file tool instead. Reading JSON is `grep`, not an
interpreter.

### 4 · Verify in the browser

Before declaring anything done — law 3.

- **Restart the dev server after any branch change.** Dev servers serve stale compiled output
  across a checkout, so the page shows the previous branch's build and verification passes on code
  that is not there.
- **Use the same default-branch container from the reproduction gate as the Before/baseline side
  of any A/B** (see *The reproduction gate* in pre-flight). It is already running, it is the exact
  state the fix will merge into, and it never changes — so nothing about it needs hot reload. A
  second dev server is the worst way to provide a baseline: GBs of RSS, file-watching the whole
  tree, and the single biggest contributor to the load spiral in the traps table.
- **Assert a sentinel the new code produces**, not just that the page loaded.
- **Serialize browser access.** One shared browser, one tab group. One lane holds it at a time,
  and each re-enumerates tabs rather than reusing an id.
- **Do not open a third-party reference app unattended.** Session expiry or any modal dialog
  freezes the automation for the rest of the run, and nobody is there to dismiss it. Reference
  values belong in the brief; that is what the brief is for.
- **Sanity-check the frame before trusting geometry.** A degraded UI keeps answering queries with
  wrong numbers. Check a known-good measurement first and fail loudly if it is off.
- **Record the verification as a GIF.** A still screenshot proves a page rendered; it does not
  prove the behaviour the lane changed. **Use `/giff-it`** for the Before and the After. It
  records the screen, so native UI shows up: file pickers, `window.prompt`/`alert`/`confirm`, OS
  sheets. `gif_creator` and Playwright capture only the page and miss exactly those. Never
  intercept the dialog or feed a file straight to the input to "prove" it: that verifies the
  handler, not what the user sees, and the GIF gets re-recorded (this has cost two
  re-recordings before). `/giff-it` also covers blurring private content (real filenames in a
  picker) and publishing without a checkout. Plain page-only flows may still use
  `gif_creator`, capturing extra frames before and after each action so playback is readable.
  Name the file for the ticket
  (`abc-123-archived-item-refuses-writes.gif`). Upload it to the tracker as an asset, add it to
  `lane/evidence`, and attach it to the
  ticket's fix-summary comment — a reviewer who can watch the before/after does not have to
  reconstruct it from prose. If the flow genuinely cannot be driven in a browser, say so and fall
  back to stills; do not silently ship without visual evidence.
- **Verify the surface the change actually touches, not the first one that loads.** A guard added
  at a shared layer reaches every screen, so exercising one screen proves the least interesting
  case. Enumerate the surfaces the change can reach and check the ones most likely to break —
  the ones the product deliberately keeps working are exactly where an over-broad guard shows up.

### 5 · Review

Run the repo's review at high effort. **Two passes, hard stop.**

**One pass is not this step.** Pass two is not a formality that pass one makes redundant — it
reliably finds what pass one missed, including defects pass one's *own fixes* introduced. Getting
the ordering right (review before push) does not discharge the step; running it once and shipping
is the same shortcut wearing better clothes. Run pass two even when pass one came back clean, and
especially when you just finished fixing what it found.

**This step is not skippable, and it runs before the push — not after.** The only
condition that excuses it is being **over 90% of the session's token budget**, read from
the actual remaining figure and never estimated from how long the turn has felt. A long
turn is not a budget. If the review genuinely cannot run, that is a stop condition to
raise *before* pushing, so the owner decides whether to ship unreviewed — never a line in
a closing summary after the branch is already public. Review gates the push; running it
afterwards lands findings on a PR people are already reading.

**Target the worktree explicitly. `/code-review` reviews the session's working directory by
default**, which in a lane is the main checkout, not the branch you just wrote. It will happily
review an unrelated diff and report findings that have nothing to do with the lane — a full pass
spent, and worse, a false sense that the branch was reviewed. Pass the worktree path (or the
branch) as the target, and sanity-check that the findings name files your lane actually touched
before you believe any of them.

Classify what comes back:

- **Mechanical** — fix it.
- **Needs a product decision** — never guess. Park it on the tracker (`lane/parked`, naming the decision) and continue with the rest
  of the lane.
- **Requires a schema or contract change the brief did not scope** — hard stop. Two lanes
  improvising the same schema change is the collision this skill exists to prevent.

#### Two reviews, two different questions — run both

`/code-review` is not the blind review that `/pull-request` requires before a PR exists, and
neither substitutes for the other. They fail differently, which is the whole reason to run both.

| | `/code-review` (this step) | blind `qa-review` (step 7, before the PR) |
| --- | --- | --- |
| Sees | the diff | diff + ticket + running app, and deliberately **not** how it was built |
| Asks | is this code correct and clean? | does this satisfy the requirement, and can I break it? |
| Method | reads the changed code and reasons about it | adversarial hypothesis table + branch-regression bash |
| Output | ranked findings, advisory | **PASS / DISCUSS** + `[blocking]` / `fold-into-pr` — gates the PR |

**Why the primed one still earns its place.** Code-level reasoning finds what product-level
probing cannot: that an RPC declared `.mutation()` is semantically a *read*, that a guard's own
fix introduced a false positive on a sibling path. You will not discover those by driving the UI.

**Why the blind one is the gate.** By pass two you have handed the reviewer your framing — what
pass one found, what you fixed, what to skip. That is efficient and it inherits your blind spots.
The blind reviewer cannot, which is exactly what makes its PASS worth gating on.

**Do not brief the blind reviewer.** Give it the diff, the ticket as the *requirement*, repo and
app access, and environment facts it would otherwise lose an hour to (a port, a seeded fixture, a
grep that silently skips a file, a contention-prone suite). Never give it your findings, your
fixes, or your parked list — the moment you do, it stops being blind and becomes a third primed
pass. If it rediscovers something you already fixed, that is the check working, not waste.

### 6 · Close the gates

- **Run the formatter before pushing.** CI format checks usually cover markdown too, and
  hand-authored tables will not match the formatter's alignment. Discovering this in CI costs a
  full round trip.
- **Scoped tests only — CI runs the rest.** Run the tests in the lane's change scope: the files
  the lane owns, plus the suites that directly exercise what it changed. **Never the full suite
  inside a lane**, and never as a "blast radius is wide, so run everything" exception — that
  reasoning is exactly how the rule gets broken. Under parallel load the full suite produces
  failures that are contention, not defects: the failing set swings run to run, individual files
  pass in isolation, and the lane burns the night disproving its own noise. Running the rest is
  CI's job, on a quiet machine, and CI will catch what the lane's scope missed.

  If you genuinely need to know whether a broad change regressed something, **do not read a full
  run's absolute failure count** — it is meaningless under contention. Run a scoped A/B instead:
  the same targeted set with the change enabled and disabled, and compare the two failing sets.
  Only files that fail *with* and pass *without* are yours. Everything else is pre-existing or
  noise, and "pre-existing" must be proven that way, never assumed.
- **Merge the default branch in. Never rebase, never force-push.**
- Expect the push gate to be slow; background it rather than blocking.

**Run every gate CI runs, not just the ones you remember.** A repo's required checks are a list you
can read — open the CI workflow and run what it runs. Two classes cost a full round trip because
they are invisible locally until you look:

- **Release metadata.** Changesets, version bumps, migration notes. A repo that treats its schema
  or API as a public contract usually encodes that as a required file, and the post-merge bot's
  default is not the same as the deliberate one. If the lane touched a schema, check for the
  convention before pushing — `ls` the changeset directory and match the prevailing filename shape.
- **Whole-repo static analysis.** Dead-code and unused-export checks (`knip` and friends) fail on
  code that is *correct but not yet consumed* — an export whose caller arrives in a later PR is
  exactly the shape a split-by-layer plan produces. Run it; a green typecheck says nothing about it.

**A gate a review told you about once is not learned.** Carry the finding into the next PR of the
same shape yourself — the review may not catch it twice, and agreeing with a finding is not the
same as encoding it.

### 7 · Open the PR, then update the tracker to done

**The lane is not done at "gates green".** Green gates on an unpushed branch is work nobody can
see. The closing sequence is fixed and none of it is optional: commit → merge the base → push →
**blind review to PASS** → **`/pull-request`** → wait for required CI → tracker updated with the
PR link and `phase: "done"` → **teardown (step 8)**. The tracker already exists — nothing is
published here, only written to. A lane that stops after the gates and reports success has
misreported its own state; say "ready to commit, awaiting approval" instead, and name the steps
still outstanding.

**The blind review sits between the push and the PR, and the lane runs it explicitly — do not
leave it to `/pull-request`.** It is a gate, and law 1 says gates are yours: delegating it to
another skill means you cannot confirm it ran, cannot see its verdict, and cannot tell a PASS
from a step that was quietly skipped. Dispatch the blind reviewer yourself with the final diff,
the ticket as the requirement, and environment facts only — never your findings, fixes or parked
list. Push first — pushing a branch starts no pull-request CI — then review, then open the PR.
Opening the PR is what starts required CI, so review churn must happen before it exists, never on
an open ready PR that people are already reading. If the blind verdict is DISCUSS, stop and
report; do not open the PR. See the two-reviews table in step 5 for why this is not a repeat of
`/code-review`.

**Then tell `/pull-request` the blind review has already passed, and to skip its own.** Say so in
the invocation, and quote the verdict. Otherwise the same adversarial pass runs twice: the second
one is no longer blind (the branch now carries the fixes from the first), it costs a full review
cycle, and a DISCUSS from it lands after you have already decided to ship.

**Publish the evidence yourself before invoking `/pull-request`,** with `/giff-it` step 7 (no
checkout). Pass it the SHA-pinned URLs and tell it the evidence is already published. An
assets-branch recipe that checks out the whole repo into a worktree can stall for good under
endpoint security, one step short of the PR.

**Open the PR with `/pull-request`, not by hand.** (`/pull-request` here means the repo's own
PR skill; if the repo has none, follow its PR template and contributing guide with `gh pr
create`.) That skill owns the client-facing title and
body conventions, the integration base, and the required-CI close-out. Rolling your own `gh pr
create` skips all three and lands a PR that a human then has to fix.

**Post the review as one concise PR comment with `/lane-pr-comment`.** The blind review's
structured report (verdict, hypothesis table, coverage) is for the lane and the tracker, not
for the PR thread. Once the PR exists, distil it with `/lane-pr-comment`:
- what it was tested against;
- result bullets;
- `dev`/`branch` evidence blocks under each GIF;
- red/green counts;
- the non-blocking notes.

Posting it is outward-facing, so show the draft before posting unless the invocation already
authorized it.

**The invocation is the approval.** `/lane-run` authorizes commit → push → PR. A general "confirm
before committing" preference does not apply inside a lane — pausing for it stalls the lane and
was explicitly rejected by the owner. Stop before the commit only when the invocation or the repo
itself demands sign-off (a required reviewer gate, a protected-path rule), and then say so on the
tracker. Either way, run the whole sequence through to a tracker marked done rather than handing
back a branch and a summary.

### 8 · Tear the lane down

**A lane that ends without teardown leaks for the rest of the session.** A dev server left running
holds gigabytes of RSS and file-watches the whole tree; several of them together drive the load
average into the hundreds with the CPU near idle, because load counts processes *blocked on I/O*,
not processes computing. The symptoms arrive much later and look like anything but this: browser
automation timing out injecting scripts, test workers failing to start and collecting zero tests,
pushes hanging. Hours get spent debugging a page or a flaky suite that were never the problem.

Once the tracker is marked `done` or `blocked`, in this order:

- **Stop the lane's dev server** and any watcher it started. Kill the process group by the port you
  assigned — `lsof -nP -iTCP:<port> -sTCP:LISTEN` gives the pid — not by killing every `node`.
- **Remove the worktree** when the branch is merged, or the lane stopped and left nothing to resume
  (`git worktree remove`). Every worktree left behind is another full checkout that endpoint
  security re-scans and that every later `git worktree list` has to walk.
- **Confirm the teardown**: nothing listening on the lane's port, and `uptime` back to a normal
  idle figure. State it on the tracker, so a leak is visible rather than inherited by whoever
  works next.

Never kill a server you did not start. Another lane or the owner may be using it — identify it by
port and working directory first.

### Watch the load, not just the clock

Law 2 is easy to agree with and easy to break, because the cost is deferred. Make it concrete:

- **Check `uptime` before starting anything heavy** — an install, a suite, a dev server, a
  browser-driving sub-agent. Above roughly 20 on a laptop, wait rather than add to it.
- **Treat a high load average as a diagnosis, not noise.** A big number with idle CPU means blocked
  processes; the fix is to stop something, never to retry harder.
- **A sub-agent that drives a browser or runs suites is a heavy job**, even though you are idle
  while it works. Do not run one alongside your own browser verification or test runs.

One tracker **per lane**, named by ticket, published back at step 2 — so lanes cannot overwrite
each other's status, and there is nothing left to publish here, only to update.

**The tracker must end up carrying the PR link.** It is the one durable handle on the lane — the
tracker is what the owner reads in the morning, and without the link they cannot get from a status
summary to the actual change. Write `prUrl` onto `lane/status` in the same `ArtifactData` batch
that sets `phase: "done"`, right after the PR exists — never a placeholder. Alongside it: what
landed, what was parked and why, what was verified and how (with the verification GIF), the gate
results, and the exact stop condition if it stopped — as `lane/status.summary` and a final
`log/main` entry.

**The tracker is already live — mark it blocked on failure too.** A lane that died silently is the
worst outcome of the night — worse than one that failed loudly at pre-flight. There is no separate
"publish on failure" step: set `phase: "blocked"` on `lane/status` with the stop condition in
`summary`, in the same batch, and log it. If there is no PR because the lane stopped early, say
that in the summary instead of omitting the field.

### 8 · Tear the lane down

**A lane is not finished until the processes it started are dead.** This is the last step and it
runs on *every* exit path — success, stop condition, or pre-flight abort after `dev_command`
started. Updating the tracker is not the end; releasing the machine is.

The dev server is the expensive one. A Next.js `dev_command` is not one process: it is a server
plus a turbopack/webpack worker pool, and on a real app that is **3–4 GB per lane**. Nothing
reaps it when the lane ends, so N lanes overnight leave N of them resident until the machine is
rebooted. Measured on one machine after a night of lanes: **9 GB across 14 processes** from dev
servers alone, plus **1.3 GB across 8** from a Playwright browser nobody closed.

This is also the hidden cause of two traps already in this file — "another lane's dev server is
usually still up" (flaky full-suite runs) and the load-average trap. Both are downstream of never
tearing down.

Tear down in this order:

1. **Kill the dev server by port, not by name.** `pkill -f "next dev"` kills every lane's server
   and the owner's own dev server too. Target the port this lane was assigned from `port_range`:

   ```
   lsof -nP -tiTCP:<port> -sTCP:LISTEN | xargs -r kill
   ```

   Then confirm the port is free — the worker pool can outlive the parent:

   ```
   lsof -nP -iTCP:<port> -sTCP:LISTEN   # expect no output
   ```

   If workers survive, kill the process group rather than hunting children one at a time.
2. **Close the browser.** The shared browser from step 4 is one instance for all lanes, so the
   *last* lane closes it, not each one. A Playwright/Chrome-for-Testing stack left open is ~1 GB
   across half a dozen processes.
3. **Leave the worktree and the branch alone.** They are the durable record and the owner may
   still want them. Teardown reclaims *processes*, never work.

**Never kill by a pattern that can match outside the lane.** The owner's own dev server on the
main checkout looks identical to a lane's in `ps`; the port is what distinguishes them. Killing it
mid-session is a worse outcome than leaving a lane's server up.

## Never, in any lane

- **Read the agent config directory.** It is commonly deny-listed, and a deny beats every
  permission mode including bypass. Do not try; do not overwrite a config file you could not read.
- **`git stash`** — it is repo-global and will swallow another lane's work.
- **Rebase or force-push.**
- **Run the rules/skills compiler in a worktree** where it symlinks into the main checkout.
- **Full-suite test runs** while other lanes are live.
- **Bypass permissions mode.** It does not lift denies, and it makes the destructive-accident class
  more likely — which is the expensive failure, not the stalled one.
- **Delegate a gate.** Verification, review triage, the formatter, the push, and the call that the
  lane is done stay with the lane owner. Dispatch the investigation, never the closure.

## Deferred lanes

A lane that cannot start yet is the easiest thing in this skill to lose. It has no branch, no
worktree and no artifact, so every mechanism below that catches a failing lane misses it
entirely — it survives only as a sentence in the conversation, and a long session will drop it.

When a lane is held for want of an input (a reference capture, a product decision, an
environment fact, another lane's merge):

- **Record it the moment it is deferred**, with the blocker stated as a concrete event —
  "ABC-123: needs the upstream app's filter-panel field list" — not "blocked".
- **Name who clears it and what arriving looks like**, so the trigger is recognizable when it
  shows up hours later.
- **Re-check every deferred lane before reporting the batch done.** "Done" means every lane
  either shipped or is recorded as still deferred with its blocker. A lane nobody mentioned
  again is not done, it is lost.
- **When the blocker clears, launch it** — do not wait to be asked a second time. The input
  arriving *is* the go-ahead the deferral was waiting on.

A deferred lane and an unasked question are the same failure: work the owner believes is in
flight, and nothing is moving.

## Stop conditions

Default behaviour on every one: **stop, mark the tracker blocked, leave the branch intact.** Never
improvise past a missing input.

| Condition | Action |
| --- | --- |
| Pre-flight check failed | Abort naming the check. Do not substitute a guess for the missing input. |
| The bug does not reproduce on a container built from the default branch | The lane does not start. Report "not reproducible on `<branch>@<sha>`" and close the ticket against whatever shipped the fix. Client reports are filed against a released tag that can be weeks behind the branch, so this is common, not exceptional — and it is far cheaper to find here than after a worktree, a bootstrap and an investigation |
| A lane is held for an input and never starts | Record it per *Deferred lanes* and re-check it before reporting the batch done. A lane with no branch has no tracker yet, so nothing else here catches it — it is lost silently unless you track it deliberately |
| The input a deferred lane was waiting on arrives | Launch that lane. The input arriving is the go-ahead; do not wait to be asked again |
| Browser verification impossible | Fall back to DOM assertions in tests, mark **verified-partial**, say so plainly. Never claim green. |
| Review findings remain after two passes | Stop fixing. Park with severity and file. |
| Tempted to skip the review to save time | Don't. Check the real remaining budget; under 90% there is no case. Raise it before pushing or not at all. |
| Ran one review pass and called step 5 done | Pass two finds what pass one missed, including defects pass one's own fixes introduced. Run it even when pass one came back clean |
| CI fails on an unused export the typecheck was happy with | Whole-repo dead-code checks (`knip`) flag correct-but-unconsumed code. A split-by-layer plan produces exactly that shape — run it before pushing, and land an export with its caller |
| Schema changed but the release bump is wrong | Look for the repo's changeset convention before pushing; the post-merge bot's default is not the deliberate one |
| The same finding a review already gave you reappears in the next PR | Agreeing with a finding is not encoding it. Carry it forward yourself — the review may not catch it twice |
| A finding needs a product decision | Park it, name the decision, continue the rest. |
| Unscoped schema change required | Hard stop. |
| A file outside the ownership boundary must change | Hard stop — this is law 4 asserting itself. |
| "The change touches a shared layer, so I should run everything once to be safe" | No. That is the full-suite rule breaking itself with a plausible reason. Run the change scope; use a scoped A/B if you need a regression signal; let CI run the rest |
| Gates are green and you are about to report the lane finished | Check the closing sequence: commit → push → `/pull-request` → tracker updated with the PR link and `phase: "done"` → teardown (step 8). Green gates on an unpushed branch is not a delivered lane. If awaiting commit approval, say "awaiting approval" and list what is still outstanding — never "done" |
| The tracker is marked `done` or `blocked` and you are about to exit | Run teardown (step 8) first. Leaving the dev server up is a 3–4 GB leak per lane that nothing reaps; several lanes overnight will exhaust the machine. Kill by assigned port, never by name |

## Known traps

Each of these produced a wrong answer or a lost hour before it was written down.

| Trap | Guard |
| --- | --- |
| Seed fails with a proxy/`ownKeys` error | Stale generated client — run codegen *before* seed |
| Browser automation times out injecting scripts (`document_idle` never reached, screenshots fail, the tab seems to revert) right after a worktree checkout or install | **Check `uptime` first — this is almost always machine load, not the page or the extension.** Endpoint security (CrowdStrike Falcon and friends) scans every file written, so a 13k-file checkout plus a 1.5k-package install drives load into the hundreds for minutes afterwards, and the browser cannot get enough CPU to settle a page. The tell is a huge load average with only one or two processes visible in `ps -r` — that is blocked processes, not busy ones. Wait for it to decay rather than debugging the page, and never start a heavy job while you still need the browser (law 2). Diagnosing this as a permissions or page problem costs a full detour |
| A full-suite run reports a different failing set every time | Contention, not defects. Another lane's dev server is usually still up — the root cause is a lane that skipped teardown (step 8). Stop counting failures; switch to a scoped A/B with the change on vs off, and reap the stale servers by port |
| Load average in the hundreds while `ps -r` shows almost no CPU | Not compute — processes blocked on I/O. Usually dev servers left running by earlier lanes: each holds GBs of RSS and file-watches the whole tree, so two of them is tens of thousands of fsevents watches and constant page-ins. Count what is listening (`lsof -nP -iTCP -sTCP:LISTEN`), stop what you started, and check `uptime` again. Retrying the thing that timed out only deepens it |
| Test workers fail to start — "Failed to start forks worker", 0 tests collected | The machine is starved, not the tests. Stop a heavy job, then re-run the tests **alone**. Chaining tests + lint + format + typecheck into one command is a common self-inflicted cause: the typechecker is still burning CPU when the test workers try to spawn |
| `git status` suddenly shows a clean tree and your work looks gone | Before concluding anything was lost, check whether a dispatched agent ran `git stash` — it is repo-global, it blanks the tree for everyone, and a status landing inside that window reads as "reverted". Check `git stash list` and the reflog, and re-verify with `git diff HEAD --stat`. Tell dispatched agents explicitly not to stash |
| `grep "a\|b"` reports a pattern missing that is plainly in the file | BSD grep (macOS) treats `\|` as a literal, not alternation. Use `grep -E "a\|b"`. A false negative here can convince you work vanished |
| A "regression" from the suite passes when its file is run alone | It was never a regression. Confirm in isolation before investigating, and never fix a test that passes on its own |
| `pnpm --dir <worktree> vitest …` fails with `EACCES ... spawn <worktree>` | pnpm tries to spawn the directory as the command. Binaries need the exec form in a worktree: `pnpm --dir <worktree> exec vitest run <paths>`. A profile's `scoped_test: pnpm test <paths>` does not survive the `--dir` hop |
| The app serves 200 but renders a blank shell, with SSR data errors in the console | The dev server's port and its `PORT` env disagree. Where server-side data calls build their own origin (e.g. `http://localhost:${process.env.PORT ?? <default>}`), starting with `--port 3011` alone makes the server fetch the *default* port, get ECONNREFUSED, and fail every query. Always start a lane's server with both in sync: `PORT=<assigned> … --port <assigned>` |
| The red test fails, but on setup rather than on its assertion | Not a valid red — it guards nothing. A context-provider or mock error means the harness is wrong, not the behaviour. Fix the harness and re-run until it fails on the assertion you wrote. Mocking a barrel often misses; mock the module the barrel re-exports from |
| A still screenshot is the only visual evidence | It proves a page rendered, not that the behaviour changed. Record the flow as a GIF and attach it to the tracker and the ticket |
| The GIF stops at the click and the dialog never appears (file picker, URL prompt) | Page recorders cannot see native UI. Re-record with `/giff-it` (screen capture), and blur the picker's real filenames |
| Evidence publish hangs, or leaves a worktree with ~13k staged files and no commit | A `git worktree add` + `checkout --orphan` assets recipe checked out the whole repo under endpoint security. Build the assets commit from objects with `/giff-it` step 7 (temp index + `commit-tree`), and remove the stranded worktree |
| The tracker reached `phase: "done"` but has no PR link | Write `prUrl` onto `lane/status` right after `/pull-request` returns, in the same batch that sets the phase. A tracker without the link leaves the owner with a summary and no way to reach the change |
| `ArtifactData` batch refused with `version_mismatch` | The doc already exists — read it first, pin the write with `if_version` from that read, and resend. Never retry unpinned |
| `/code-review` reports findings in files the lane never touched | It reviewed the session's cwd, not the worktree. Re-run it with the worktree/branch as the explicit target; the first pass reviewed nothing of yours |
| "I already ran two review passes, the blind one is redundant" | It is not the same check. Primed passes inherit your framing; the blind one is the PR gate. Run both — see the two-reviews table in step 5 |
| The blind review was left to `/pull-request` to run | Run it yourself before invoking that skill, then tell it the verdict and to skip its own. A gate you delegated is a gate you cannot confirm ran, and letting it run afterwards means a DISCUSS arrives after you have already committed to shipping |
| Briefing the blind reviewer on what you fixed so it "doesn't waste time" | That un-blinds it into a third primed pass. Give it the diff, the ticket and environment facts only; rediscovering a fixed issue is the check working |
| Dev command ignores the port you asked for | Invoke the underlying server directly with an explicit port |
| Formatter check fails on a docs-only change | Run the formatter on markdown too, before pushing |
| Remote rejects the branch name | Check `branch_pattern` before the first push |
| Cherry-picking commits onto the default branch fails | The commits *modify* files that branch never had — move the file state, not the commits |
| Verification passes on the previous branch's build | Restart the dev server after every checkout |
| A screenshot coordinate misses its target | Read the position from the DOM; screenshots are scaled |
| Config file cannot be read but must be edited | Hand the user the exact block. Never write a config you could not read first |
| A "simple presentational fix" turns out to touch a hot shared file | Run pre-flight check 0 first. On a mature canvas or layout component, contention is the norm, not the exception |
| Contention check reports every branch as an owner | Ancestry over-reports. Compare tips, then check ticket status — finished work leaves its worktree behind |
| `git log -- $PATHS` returns nothing in zsh | Unquoted variables do not word-split. Pass each path as its own quoted argument |
| Permission prompts on ordinary commands, over and over | `cd <dir> && …` prefixed onto every call. Use `git -C`, `pnpm --dir`, and absolute paths instead — never `cd` |
| A single `cd` up front does not stick | The harness resets the working directory between calls. Check the tool result for a reset notice before depending on cwd |
| The bug in the brief is already fixed | Re-confirm measured values against the default branch before implementing |
| A sub-agent reports a fix in a file that does not contain it | Findings are claims. Require `file:line` and confirm before acting — an agent that cannot find the code invents plausible code |
| Two dispatched units edit the same file | Collapse them into one edit you make yourself. Law 4 applies inside a lane, not just across lanes |
| Dispatch made the lane slower, not faster | Fewer than two independent units, or fanned out across separate messages so they serialized. Both pay the overhead and buy nothing |
| A sub-agent says "verified" | It is not a gate. Re-run the browser check yourself — law 3 is not delegable |

## Worked profile — a Next.js + Prisma + pnpm repo

```
default_branch : dev
branch_pattern : ^(fix|feature|hotfix|release|refactor|chore|revert|task).+
bootstrap      : pnpm install
                 pnpm prisma:generate      # before seed, always
                 pnpm prisma:migrate
                 SEED_FORCE=1 pnpm prisma:seed
dev_command    : pnpm exec next dev --port <assigned>    # the `dev` script hardcodes one port
port_range     : 3011–3014, one per lane
format_command : oxfmt <paths>            # covers markdown
scoped_test    : pnpm test <paths>
banned         : pnpm rulesync (symlinks into main checkout), git stash, git push --force
```

## Invocation

```
/lane-run <ticket>                 # one lane
/lane-run <ticket> <ticket> ...    # several, subject to law 4 — merge any that share files
```

Assign ports up front, run pre-flight for every lane before starting any of them, and honour law 2
on anything heavy.
