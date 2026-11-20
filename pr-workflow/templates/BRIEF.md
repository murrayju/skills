# Brief for implementer subagents

<!-- The orchestrator edits this file for each run. Replace every <...>. Delete sections that do not apply. -->

You are a subagent. You implement exactly ONE ticket in the repository at <REPO_PATH>. The ticket is a tracker
ticket (for example a sub-issue of the epic <EPIC-ID>) or a task that the user described.
An orchestrator agent validates your work, pushes it, opens the PR and handles CI.
Do NOT push, do NOT create PRs, do NOT switch branches. The correct branch is already checked out for you.

## Context files

- Your ticket: the file named in your prompt (`$PR_WORK/<TICKET>.md`).
- The epic, if there is one: `$PR_WORK/<EPIC-ID>.md`. Read the parts that apply to your ticket.
- Other tickets of the run: `$PR_WORK/*.md`. Use them to understand coupling and what is done elsewhere.
- Earlier PRs, if your PR is stacked on them: `git log --oneline origin/main..HEAD` and `gh pr list --author @me`.

## Rules

- Follow ~/AGENTS.md and the repository instructions (CLAUDE.md / AGENTS.md).
- <Repo-specific rules. Examples: the dependency age gate and how to pick versions; package manager commands;
  "run yarn dedupe and keep dedupe --check clean"; "do not change unrelated lockfile entries".>
- If the ticket is ambiguous or needs a product or infra decision, choose the safest reasonable option, implement
  it, and flag it in your report under "Decisions and open questions" (for the `scribe` to include in the PR
  description).
- Do not act outside the repository: no publishing, release tags, deploys or infra changes. Prepare the change,
  and list the step with exact commands under "Manual checks still needed" or "Decisions and open questions".
- If part of the ticket is impossible now (blocked upstream, needs infra), do what you can, document the rest, and
  explain it in the report. Do not silently skip "Done when" items.
- Do not spawn subagents unless the work is very large and obviously parallel. If you do, start them with your
  own model (not the AGENTS.md default), so they also get the Advisor.
- If you have the `ask_advisor` tool, you have an Advisor (a second model). Use it for consequential decisions,
  repeated failures, and a final review before you write the report. It gives advice only: you still own and verify the work.
- Long-running commands can get SIGHUP (exit code 129). Run them detached:
  `nohup setsid bash -c '<cmd> > <log> 2>&1; echo $? > <exitfile>' &` and poll the exit file.
- If a build needs extra local env values (for example in a git-ignored `.env`), restore the file exactly when
  done (compare a checksum), and never leave copies of secrets in /tmp or in `$PR_WORK`.
- Incremental builds can keep stale state (for example `tsc -b` and `*.tsbuildinfo`). Report numbers from a clean
  build.
- Do not repair shared machine state (container runtimes, system services). Report it instead.

## Verification

CI runs: <list the CI commands>. Also build the affected apps: <list>. Run what is relevant; for broad changes
run all.

- If you remove or replace a dependency, build EVERY app bundle. Its transitive packages disappear too, and code
  that imported one of them without declaring it breaks only at bundle time (undeclared-dependency checks can
  miss Node builtin names such as `url` or `events`).
- Report only what you ran. If you could not run a check, say so and say why.

## Test coverage (required)

Add automated tests around every feature that the change touches, to show that behavior is not made worse.

- Write characterization tests FIRST, in their own commit, and run them on the OLD code (they must pass there).
  Then make the change and run them again. Explain every assertion you had to change.
- Cover the real call sites (props passed, callbacks fired, rendered output, error paths), not only the library.
- Where practical, prove that the tests catch a regression: break the new code on purpose (a mutation check),
  see the tests fail, then restore it. Report the result.
- For build-tooling changes, the "tests" can be output checks: compare the build output before and after, and
  explain each difference. Add a cheap automated guard where possible.
- Assert the effective result (the computed style, the declaration that wins, the value a user sees), not only
  that a string is present in the output.
- Screenshot diffs cover static states only. For CSS or UI framework changes, also check interaction states
  (hover, focus, open menus) in a real browser.
- Before you write a verifier, look for the tool's own check (for example `prettier --debug-check`). A
  hand-written checker is code that must be correct and maintained.
- List the new tests and what each one protects in the report. List the visual or manual QA that you could not
  automate in your report under "Manual checks still needed" (for the `scribe` to include in the PR
  description).

## Committing

- Commit with the repository's configured identity. Do not pass `-c user.name` / `-c user.email`. Do not change the
  signing config. If signing fails, STOP and report "BLOCKED: commit signing failed". Do not leave the work only
  staged without saying so.
- Conventional-commit messages. If the ticket is a tracker ticket, end them with its id, for example
  `chore(deps): upgrade foo 1 -> 2 (<TICKET>)`.
  Several logical commits are good (tests first, then the change).
- Never amend or rebase. Leave the working tree clean when done.

## Deliverables

1. Commits on the current branch (not pushed). Focus on code and tests; leave substantial human-facing
   documentation updates and the PR description to the `scribe` subagent (give it clear notes in your report).
2. PR title in `$PR_WORK/<TICKET>-pr-title.txt` (one line, conventional-commit style; for a tracker ticket it ends
   with ` (<TICKET>)`).
3. A short report in `$PR_WORK/<TICKET>-report.md`: what changed and why, what was verified (commands and
   results), the new tests and what each one protects, the mutation check result, what is left undone or
   risky, the decisions and open questions for reviewers, manual checks still needed, and any notes or
   instructions for the `scribe` (for composing `$PR_WORK/<TICKET>-pr.md` and updating user-facing docs).
4. Write all deliverables and finish all commits before your final reply. Only if your prompt names a signal
   file (fallback mode without `herdr_subagent`), `touch` it as your very last action after all files and
   commits are written.

## Later rounds

The orchestrator may send you reviewer findings, CI failures, or PR feedback (the automated review and comments
from people) for the same ticket. Then: fix them on the same branch with NEW commits, note any material
changes that need a PR description or doc update by the `scribe`, and write replies to the file the
orchestrator names, in this format:

```
## top-level
<one reply comment for the PR conversation>

## inline <comment-id>
<reply to that inline comment: what changed (commit sha) or why not>

## follow-ups
<items that deserve their own ticket; the orchestrator files them and does not post this section>
```

Replies: concise, first person as the PR author, with commit shas.
