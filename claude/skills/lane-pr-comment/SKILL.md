---
name: lane-pr-comment
description: Turn a finished PR review or QA verification (a lane's blind review, or a manual test of someone else's PR) into ONE concise GitHub PR review comment - opening sentence, plain-language result bullets, before/after evidence blocks, test counts, and a few non-blocking notes. Works in any repo. Triggers on "draft the PR review comment", "post the lane review", "/lane-pr-comment", "QA comment for PR #n".
---

# lane-pr-comment

Distil a finished verification into one short review comment a human teammate would write. Project-agnostic: nothing here depends on a particular repo.

## Inputs (gather or ask for)

- PR number and repo (`owner/name`).
- Base ref and the branch/image actually tested, plus the setup or seed used on both.
- Verified results: from a blind review report or from your own manual testing.
- Evidence image/GIF URLs (our own app only; see rules).
- Test counts from a real run: new or changed tests that fail on the base code (red) and pass on the branch (green).

## Output format

Use `templates/pr-review-comment.md`. Exactly this order, no headings, no tables:

1. One opening sentence: what it was tested against and with what setup/seed.
2. Result bullets in plain user language, one per scenario or observable: what the base does vs what the branch does. No jargon, no file paths.
3. Evidence: under each image or GIF, a code block of aligned rows `base|branch  <scenario>:  <observed result>`.
4. One sentence on tests: how many new/changed tests fail on the base code, how many pass on the branch.
5. `N small things, neither blocking:` (or `Nothing else.`) as short bullets. Each is concrete, names a file only when needed, and says whether it is worth acting on now or later.

Target: under about 30 lines plus the evidence blocks. No severity tables, no hypothesis tables, no restated CI status, no "Summary" section.

## Rules

- **Every claim comes from something actually run.** Never invent counts. If no red run happened, say so in the tests sentence ("I did not run the new tests against the base code") instead of making one up. Re-run to get the numbers if cheap.
- **Distil, don't paste.** A long structured review (verdict, hypothesis table, severity list) collapses to the format above. Keep the verdict out of the prose; the GitHub review state (APPROVE / COMMENT / REQUEST_CHANGES) carries it. Only real findings become bullets in item 5; a blocking finding means the state is REQUEST_CHANGES and the bullets say what blocks, so retitle that section accordingly.
- **Images are our own app, before/after only.** Never include reference-app captures or recordings; if reference behavior must be shown, link a sketch mockup instead. Check each image before using it.
- **Host images where every viewer sees them**: GitHub user-attachments URLs (drag into a comment box, or use a user-attachments upload). Raw links to a private repo or an assets branch break for non-SSO viewers. Verify the URL renders before posting.
- **Posting is outward-facing.** Show the full draft to the user and get explicit approval first. Then:
  `gh pr review <n> --repo <owner/name> --comment --body-file <file>`
  Default to `--comment`; use `--approve` or `--request-changes` only if the user chose it. Never approve your own PR (check `gh pr view <n> --json author` against `gh api user --jq .login`).
- **No AI attribution footer** (no "Generated with Claude Code", no session link) when the repo or user instructions forbid it. When unsure, check CLAUDE.md in the repo and parents; if still unsure, ask.
- Write the body to a scratch file, not into the repo.

## Filled example (neutral, made-up)

```
Tested this against the main image with the same seed on both: a project with a Archived tab (saved filter), an Active tab, and a sort-only By date tab.

- Archived tab, opened directly: main shows the filter bar above the list. This branch hides it, still filtered (8 of 31), with the filter button highlighted. Clicking the button brings the bar back.
- Active tab, switched into from the board: same result.
- Sort-only tab: the Date pill no longer shows on load.
- Adding a filter during the session still shows its chip right away.

<img width="1200" height="900" alt="archived-tab" src="https://github.com/user-attachments/assets/<id>" />
main    Archived tab, opened directly:   filter bar above the list, 8 rows
branch  Archived tab, opened directly:   no filter bar, 8 rows, filter button active
branch  after clicking the filter button: filter bar shown

(Each block above is fenced in the real comment.)

The new tests do their job. Run against main's code, 6 of them fail. On this branch the two touched test files pass (41 tests).

Two small things, neither blocking:

- A ticket id slipped into two comments; worth dropping next time those files are touched.
- Overview pages get the same collapsed default, so an active filter shows only through the button highlight. Looks intended; flagging in case it was not.
```
