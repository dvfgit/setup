---
name: babysit
description: >-
  Keep a PR merge-ready by triaging comments, resolving clear conflicts, and
  fixing CI in a loop.
---
# Babysit PR
Your job is to get this PR to a merge-ready state.

Check PR status, comments, and latest CI and resolve any issues until the PR is ready to merge. Run this check on a loop, polling every 5 minutes, until the PR is mergeable + green + comments triaged.

To run on a true timed interval, invoke via the loop skill: `/loop 5m /babysit`.

1. Merge conflicts: Intelligently resolve any merge conflicts, preserving the intent and correctness of changes on your branch and the base branch. If intents conflict, abort the merge and ask for clarification.
2. Comments: Review active unresolved comments and resolve change requests / bug reports where valid. When fetching GitHub comments, filter out resolved threads first. Read only each comment body and the minimum location/URL needed to act on it; do not read the entire JSON output or other unnecessary payload data.
3. Cursor Bugbot: Do NOT manually close or resolve Cursor Bugbot comments. Instead, check for the latest Cursor bug review output: if a fresh review has completed and is ready, treat its findings as authoritative and ignore stale Bugbot comments left over from earlier runs (they reflect a prior state of the branch). Only act on findings from the current, ready review; carefully validate each one and fix only those that are valid, explaining when you disagree or are unsure. Let Bugbot resolve its own threads once the fix lands.
4. CI: Fix CI issues caused by changes within this PR's scope. Never change CI checks/workflows just to make failures pass, or make unrelated code changes; if that would be required, report back instead. For merge-blocking failures that seem unrelated to this PR, check whether the branch is behind the base branch and merge latest changes, since another PR may have fixed them. Push scoped fixes and re-watch CI until mergeable + green + comments triaged.
