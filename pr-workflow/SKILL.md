---
name: pr-workflow
description: Take work from a task or ticket to a green PR. You stay the orchestrator; a fresh pi subagent in a named Herdr tab via herdr_subagent (the current model, with the configured Advisor) implements it, a sequence of reviewer models (default neon, astra, fable; no Advisor) reviews it before the PR opens, then CI goes green, the PR feedback is addressed, and the reviewers run again until no high or medium findings remain. Falls back to manual Herdr split panes when herdr_subagent is not installed. Works for a single PR; a list of tickets (for example the sub-issues of a Linear epic) repeats the loop as stacked PRs. Do not ask the user about the workflow. Use when the user asks to implement a ticket or task as a PR, to work through tickets one at a time with subagents, herdr, stacked PRs, or "only move on when green".
---

# PR workflow with herdr + pi subagents

You are the **orchestrator**. You do not write the feature code. For each PR you:

1. claim the ticket in the tracker (if there is one) and make its branch,
2. start a fresh implementer subagent for that one ticket, which makes the change AND adds test coverage for
   it, and validate both,
3. run the reviewers, one after the other, and get their findings fixed, BEFORE the PR opens,
4. open the PR and take CI to green,
5. address the PR feedback (the automated review and comments from people),
6. run the reviewers again, and more rounds while the last round has high or medium findings to fix,
7. take CI to green again, and print the PR summary.

The base case is ONE PR. A list of tickets (for example the sub-issues of an epic) is the same loop, once for
each ticket, with each PR stacked on the previous one. After the summary of one PR, start the next item at
once. Do not wait for the user.

The scripts in `scripts/` encode the lessons from earlier runs. Use them. They are config-driven
(`$PR_WORK/config.env`), so they work for any repository.

## Defaults: do not ask the user

Do not ask questions about the workflow. Use these defaults, and change one only if the user's prompt says so.

| item | default |
| -- | -- |
| implementer | the model of the current pi session (`$PI_PROVIDER/$PI_MODEL`), in a named Herdr tab via `herdr_subagent`, one per ticket |
| Advisor of the implementer | the global pi-advisor config (`~/.pi/agent/advisor.json`), as the user set it |
| reviewers, in order | the newest `neon`, `astra` and `fable` models (`init.sh` resolves the names) |
| automated PR review | the repository's own (for example the `claude-review` GitHub check) |
| scope | what the prompt names: one task, one ticket, a list, or the open sub-issues of an epic |
| base branch | the default branch for the first PR; the previous PR's branch for each later item of a list |
| actions outside the repo | not authorized: publishing, release tags, deploys, infra changes. Park and continue |
| merges | never merge. The user merges (squash) |
| pauses | none between items. Stop only for a real blocker (see below) |

Using this skill is the explicit request to push branches and open PRs.

If the user names other models, resolve each name with
`~/.agents/skills/pr-workflow/scripts/resolve-model.sh "<the words the user used>"` and pass the full ids to
`init.sh`. The script reads the live catalog from `pi --list-models`, so keep no list of ids yourself: they
drift. It ranks an exact id first, then the provider (`concentrate`, then `openrouter`, then the others), then
the newest generation. Always pass full `provider/model` IDs: `herdr_subagent` requires an exact ID, and in
fallback mode `pi` resolves short names to the first catalog match.

If the items of a list are not related, or the user asks for it, base each PR on the default branch instead of
stacking it.

A real blocker is not a workflow question: gpg signing fails, auth is missing, or a product decision has no
safe default. Then stop and report. For everything else, choose the safest reasonable option and say what you
chose in the summary.

## Roles

| role | how | config key |
| -- | -- | -- |
| orchestrator | you, in the Herdr tab/pane the user talks to | |
| implementer | `pi` in a named Herdr tab (`herdr_subagent`), one per ticket, clean context | `IMPLEMENTER_MODEL` |
| Advisor of the implementer | pi-advisor extension (`ask_advisor` tool and gates), global config | (none) |
| reviewers | `pi` in a named Herdr tab (`herdr_subagent`, `advisor: false`), read-only, one round at a time | `REVIEWER_MODELS` |
| automated PR review | GitHub Action, runs when the PR opens | `CLAUDE_REVIEW_CHECK` |

Prefer the `herdr_subagent` tool (from `murrayju/pi-herdr-subagents`) whenever it is available: it launches
workers in named background Herdr tabs, tracks usage and cost in the footer, and reports completion directly
without signal files. When `herdr_subagent` is not installed, use the fallback scripts described in
"Fallback: manual panes without `herdr_subagent`".

`herdr_subagent` inherits the orchestrator session's current thinking level, so run the orchestrator at `high`
thinking (`THINKING` in `config.env` only applies to the fallback scripts).

**Review rounds.** Round N uses the reviewer at position (N-1) modulo the count of `REVIEWER_MODELS`, so one
**pass** runs every reviewer once, in order. Each round gets all earlier reports and the PR feedback
(`start-review.sh --prepare` includes them), so it checks the fixes and looks for what the others missed. Keep the
reviewers in different model families: on earlier runs each family found real bugs that the others and the
automated review missed (lost hover states, a rem fallback that beat the px theme, a deploy race, a silently
skipped CI test, lost images, skipped saves, unbounded caches).

**Advisor rules.** The implementer gets the Advisor from the global pi-advisor config: omit `advisor` when
starting it via `herdr_subagent`. Do not change `advisor.json`: it is the user's setting. `preflight.sh`
prints a `WARN` line if the Advisor is off, or if it is the implementer model (pi-advisor then skips every
call, unless `advisorDisableSameModel` is false). Continue, and put the warning in the summary. The reviewers
must use only their own model: pass `advisor: false` to `herdr_subagent` (or `--exclude-tools
ask_advisor,record_advisor_outcome` in fallback mode), which removes the tool, the prompt rules and the
automatic gates.

**Check that the Advisor is used, not only available.** The declaration alone is not enough: workers whose
brief did not mention the Advisor called it about once per ticket (the completion gate). Count the calls in
the worker's session (`sessionFile` from `herdr_subagent status`: `grep -o '"toolName":"ask_advisor"'
<session.jsonl> | wc -l`) or read its footer (`Advisor: N calls`). In the first prompt, name the decisions
that deserve a consult. Note that `herdr_subagent send` rejects prompts while a worker is busy (HTTP 409), so
set expectations up front; if a worker on a long ticket still needs a mid-run nudge, tell the user to open its
tab (click the card or `/subagents <id>`).

## One-time setup

```bash
test "$HERDR_ENV" = 1            # Stop if you are not in herdr.
S=~/.agents/skills/pr-workflow/scripts
# Give IMPLEMENTER_MODEL or REVIEWER_MODELS="<id> <id> .." only if the user named other models.
eval "$($S/init.sh <RUN_ID> <REPO_PATH>)"   # Prints: export PR_WORK=~/.cache/pr-workflow/<RUN_ID>
$S/preflight.sh                  # herdr, gpg signing, models, Advisor, gh auth, clean tree
```

Then:

- **Tickets.** For each item, write `$PR_WORK/<ID>.md` with a line `Suggested branch: <branch>` near the top,
  then the description, then the comments (they often hold important constraints). The branch name starts with
  the user's prefix (for example `murrayju/`).
  - From Linear (MCP from codemode): `get_issue` with `includeRelations`, `list_comments`. For an epic, also
    `list_issues` with `parentId`, and write the epic to `$PR_WORK/<EPIC>.md`. Use the ticket's
    `gitBranchName`.
  - From the user's prompt (no tracker ticket): pick a short id (for example `fix-login-redirect`), and write
    the task in the user's words, plus what you learned from the repo.
- **Order.** Write `$PR_WORK/ORDER.txt`, one ticket per line (one line for a single PR). Respect the blocking
  relations. Put unblockers first. Put whole-repo reformatting (prettier and similar) last. Mark progress in
  this file (`<ID> done #<PR>`), so you can resume after a context reset.
- **Brief.** Edit `$PR_WORK/BRIEF.md` (copied from `templates/BRIEF.md`): the repo rules, the CI commands, the
  builds to run, and the environment notes (for example the container socket). Keep the test coverage,
  committing, and deliverables sections. All subagents read it first.
- **CI facts.** Find out which checks run on PRs (`.circleci/config.yml`, `.github/workflows/*`), and how the
  automated review is triggered. Set `CLAUDE_REVIEW_CHECK` in `config.env` to its check name, or to `""` if
  there is none. In the reference repo it runs only on `opened`, `ready_for_review` and `review_requested`, so
  it reviews each PR exactly once, at creation.

## The per-PR loop

```bash
S=~/.agents/skills/pr-workflow/scripts
T=<ticket id>; BASE=<default branch, or the previous ticket branch in a stack>
```

1. **Preflight.** `$S/preflight.sh`. If gpg signing fails, STOP and ask the user to unlock gpg (see
   Pitfalls). Keep the `WARN` lines for the summary.
2. **Claim the ticket** (tracker tickets only): `save_issue({id, assignee: "me", state: "In Progress"})`, then
   `get_issue` to confirm it (the update can silently not apply; repeat it).
3. **Start the implementer.** Confirm the tree is clean, read `Suggested branch:` from `$PR_WORK/$T.md`, and
   create the branch: `git checkout -q "$BASE" && git checkout -q -b "$BRANCH"`.
   Then call `herdr_subagent` with `action: "start"`, `name: "$T"`, `model: <IMPLEMENTER_MODEL>`, `cwd: <REPO>`
   (omit `advisor` so global Advisor settings apply), and prompt:
   `Read $PR_WORK/BRIEF.md first and follow it exactly. Your ticket: $PR_WORK/$T.md ($T). You are on branch $BRANCH, created from $BASE (see git log --oneline for earlier work in a stack). Your PR will target $BASE. <ticket-specific guidance>`
   Give specific guidance: the risky call sites, what to characterize before the change, the prerequisites
   that earlier PRs already provide, the decisions to take to the Advisor, and what not to do (out-of-scope
   follow-ups). Save the returned worker ID in `$PR_WORK/$T-worker` (it also stays in `herdr_subagent list`).
4. **Wait.** Call `herdr_subagent({ action: "wait", id: <worker-id>, timeoutSeconds: 600 })`.
   Large tickets take 1 to 3 hours: whenever `wait` returns `"timedOut": true`, call `wait` again. Never
   re-call `start` or `send` after a timeout (a timeout ends only the wait, not the worker).
   When `wait` settles:
   - `blocked`: tell the user to open the tab (click the card or `/subagents <id>`).
   - `failed`, `aborted`, or `disconnected`: inspect `output` and `sessionFile` before deciding next steps.
   - `completed`: this means Pi finished responding, not that the work is complete. Verify the deliverables in
     step 5; if `$PR_WORK/$T-report.md`, `$PR_WORK/$T-pr.md`, or commits are missing (or the worker asked a
     question), `send` a follow-up once idle and `wait` again.
5. **Validate.** Read `$PR_WORK/$T-report.md`. Check `git status` (clean), `git log --format='%h %G? %s'
   $BASE..HEAD` (all commits signed: `G`), and look at the key production diffs yourself. Look for
   left-over secrets: `find $PR_WORK /tmp -name '*env*'`.
   Check the tests too ("Test coverage" in the brief): a characterization-test commit comes before the change
   (or the report says why there is none), the report lists the new tests and what each one protects, gives
   the mutation-check result, and shows that the tests ran. If tests are missing or weak, send the
   implementer back with `herdr_subagent send` + `wait` before review pass 1.
6. **Review pass 1, before the PR.** Run one round for each reviewer (see "A review round"). The fixes stay
   local commits.
7. **Open the PR.** Read `$PR_WORK/$T-pr.md`. It must be short (see "PR descriptions"); if it is not, ask
   the implementer to cut it. Run `$S/review-summary.sh $T --update-pr` to put the table of review rounds
   under `## Reviews`. Then `$S/create-pr.sh $T $BASE` (it refuses a dirty tree and em dashes, pushes, checks
   that the remote head equals HEAD, and opens the PR against `BASE`). Set a tracker ticket to "In Review".
8. **CI until green.** `$S/wait-pr.sh <PR> 80 --review` (the first time only: it also waits for the
   automated review). On a failure, see "CI failures": make sure the implementer is idle, `send` the fix
   prompt via `herdr_subagent`, `wait` until settled, verify commits and clean tree, `$S/push-check.sh`,
   and `$S/wait-pr.sh <PR> 80` again. Do not continue while any check is red.
9. **PR feedback.** `$S/fetch-feedback.sh $T` writes `$PR_WORK/$T-feedback.md` (the automated review and
   comments from people; it leaves out our own replies). Do not wait for people who have not reviewed yet.
   If there is feedback, make sure the implementer is idle and send it ONE prompt with
   `herdr_subagent({ action: "send", id: <worker-id>, prompt: "..." })`: name the file, say for each item
   whether to fix it or to reply only, ask for NEW commits, a replies file `$PR_WORK/$T-replies.md` (format
   in the brief; inline replies are for the inline comment ids), and an updated PR description if material.
   Then `herdr_subagent wait` until settled, confirm `$PR_WORK/$T-replies.md` and new signed commits exist,
   check the diff, `$S/push-check.sh`, `gh pr edit <PR> --body-file $PR_WORK/$T-pr.md`, and
   `$S/post-replies.py $T` (it posts the top-level reply and one reply to each inline comment; it skips
   `## follow-ups`). For a later feedback round, use `$T-replies2.md` and
   `$S/post-replies.py $T <PR> $PR_WORK/$T-replies2.md`.
10. **Review pass 2.** Run one round for each reviewer again. Then, while the last round had high or medium
    findings that changed code, run one more round (`start-review.sh --prepare` picks the next reviewer). Stop
    when a round has no high or medium finding to fix. After 3 extra rounds, stop and put the open findings in
    the summary. If HEAD did not change since the last review round of pass 1 (no CI fix and no feedback fix),
    skip pass 2 and say so in the summary.
11. **Push and CI until green again.** `$S/push-check.sh`, `$S/review-summary.sh $T --update-pr`,
    `gh pr edit <PR> --body-file $PR_WORK/$T-pr.md`, and `$S/wait-pr.sh <PR> 80`, as in step 8. If a CI fix
    now changes production code, run one more review round. NEVER conclude a PR while a check is red or pending.
12. **Close out.** Close each idle worker created for this ticket (implementer in `$PR_WORK/$T-worker` and
    reviewers recorded as `sub:<id>` in `$PR_WORK/$T-reviews.tsv`, or found via `herdr_subagent list`) with
    `herdr_subagent({ action: "close", id })`. Unlike standalone `/skill:review`, `pr-workflow` closes its own
    reviewer and implementer tabs at close-out. `close` only removes original panes that confirm they are
    idle; never close the user's own tabs. Mark the ticket done in `ORDER.txt`, and print the PR summary (below).
13. **Next item.** If the user gave a list, start the next ticket at once, with `BASE` = this ticket's branch
    (or the default branch, see "Defaults"). After the last item, print a table of all PRs.

### A review round

1. Run `$S/start-review.sh --prepare $T $BASE`. It checks for a non-empty diff, writes the diff, commit log,
   and prompt (including earlier reports and PR feedback, without a done signal), appends the round to
   `$PR_WORK/$T-reviews.tsv`, and prints `round`, `model`, `id`, `prompt`, and `output`.
   Start the reviewer with `herdr_subagent({ action: "start", name: "$T-r$ROUND", model: <model>, advisor: false, cwd: <REPO>, prompt: <contents of prompt file> })`,
   then record its worker ID: `$S/start-review.sh --set-worker $T $ID <worker-id>`. (If `start` fails, retry
   `start` with the same prepared prompt file rather than re-running `--prepare`, which would advance the round.)
   Wait with `herdr_subagent({ action: "wait", id: <worker-id>, timeoutSeconds: 600 })` (loop on `timedOut: true`).
   When `completed`, confirm the output file (`$PR_WORK/review/$ID-output.md`) exists and is non-empty; if
   missing, check `output` or `send` a follow-up asking it to write the file and `wait` again. If a report
   says "No issues found" with no "What I checked" section, follow up with `send` + `wait` for evidence before
   you trust it.
2. Sort the findings:
   - Fix: real bugs, test gaps, robustness, small cleanups in the touched code.
   - Reply only (post-PR) or note in the summary (pre-PR): pre-existing problems, product decisions, and large
     refactors. File them as follow-up tickets (see "Tracker hygiene").
   - Reject with evidence: findings that are wrong. Reviewers are wrong sometimes, and so is the automated
     review (it once called real formatter output "reconstructed" because it could not run the formatter).
     When a reviewer contradicts the implementer, or two reviews disagree, settle it with a reproduction or
     a tool run, not by majority. Ask the implementer to verify a contested claim before it changes code.
3. If there is something to fix, make sure the implementer is idle and send it ONE prompt with
   `herdr_subagent({ action: "send", id: <worker-id>, prompt: "..." })`: the report path, the items to fix,
   and NEW commits. Then `herdr_subagent wait` until settled, and check the fix diff and commits.
4. Start the next round only after the fixes are done. A round with no findings to fix needs no prompt.

### The PR summary

When a PR is done (CI green), print a short summary, then continue with the next item:

```markdown
## <TICKET>: <PR title>
<PR url>, base `<BASE>`, CI green at `<sha>`.
<One to three sentences: what changed and why.>

Reviewers: <the reviewer models that ran, in order>
<the table from `$S/review-summary.sh $T`: round, reviewer, high, medium, low>
PR feedback: <n> comments (<who>): <n> fixed, <n> answered.
Needs you: <WARN lines, parked actions, open findings, manual checks; or "nothing">
```

`review-summary.sh` reads the `FINDINGS:` line that each report ends with. For a `?`, count the findings in the
report yourself. Count only findings in the diff, not the out-of-scope notes.

### Special cases

If a ticket needs no change after investigation (tracking tickets, still blocked upstream), let the subagent
write only a report, comment the findings on the ticket, move it back to Backlog, and delete the empty branch.

If a ticket needs an action outside the repo that the user did not authorize (publishing a package, a release
tag in another repository, a deploy, an infra change), park it in `ORDER.txt` with the reason, move on to the
next ticket, and list it under "Needs you". Work that you cannot verify locally (for example a staging
deploy) goes under "Manual checks still needed" with the exact commands.

If the user asks you to pause: finish the current PR to green, close the worker tabs, and give a status summary
(PR table, follow-up tickets filed, what needs the user, the next ticket).

## CI failures

Run `$S/ci-failures.sh <PR>` first (or `$S/ci-failures.sh job:<N>` for one job). Decide between "flake or infrastructure" and "real":

- **Infrastructure:** backend services that do not start ("Kafka not ready", docker buildkit "EOF"). Rerun
  the failed jobs (CircleCI MCP `rerun_workflow` with `{workflowId, fromFailed: true}`).
- **Known flake:** if the same failure also happens on `main`, it is not your change. Rerun, AND file a
  ticket. If it keeps failing, find the root cause: download the Playwright trace artifacts with the
  CircleCI API token (`Circle-Token` header) and search them (`location.url` of console errors). For
  Electron tests, the app's network and console events are in the `attachments/trace-*.zip` artifact; the
  top-level `trace.zip` is only the test runner trace. A recurring flake is worth its own small PR off
  `main`. Confirm the fix with two or three green runs, because flakes depend on timing.
- **Never rerun without reading the failure first.** A "flaky" e2e failure once hid a real break: removing a
  dependency removed a transitive package that the webapp imported without declaring it.
- **Real:** send the failure (job number, test, error) to the implementer. Timing-sensitive tests usually
  wait for a short transient state. Ask for a fix that waits for a stable end state, verified with
  repeated runs under CPU load.

Check the commit statuses of recent `main` commits to see if a check is already red there:
`gh api repos/<owner>/<repo>/commits/<sha>/statuses`.

## Fallback: manual panes without `herdr_subagent`

If `herdr_subagent` is not installed, use the pane scripts in `scripts/` instead:

- **Start / wait implementer:** `$S/start-ticket.sh $T $BASE "<guidance>"` (splits a pane, writes `$PR_WORK/$T-pane`, launches `pi` with a positional prompt and `--thinking "$THINKING"`, expects `touch $PR_WORK/$T-done`), then `$S/wait-done.sh $T` (exit 0 done, 3 timeout/call again, 5 idle without signal, 1 pane closed).
- **Review round:** `$S/start-review.sh $T $BASE` (without `--prepare`; splits a pane, passes `--exclude-tools ask_advisor,record_advisor_outcome`, expects `touch ...-done`), then `$S/wait-review.sh $T`.
- **Follow-ups:** `$S/prompt.sh <pane> "<prompt> As your very last action, touch $PR_WORK/$T-<signal>."` then `$S/wait-done.sh $T <signal>`. `prompt.sh` sends once as a steering message if already working, or retries until `working`.
- **Close out:** `$S/close-panes.sh $T` (closes only recorded panes, skipping `sub:*` entries and `$HERDR_PANE_ID`).
- **Key fallback gotchas:** always target panes by pane ID (not agent name), use signal files plus stable status (Herdr status alone can lag), count a pane closed only after 3 consecutive `pane_not_found` errors (`pane_gone`), and inspect panes with `herdr pane read <pane> --source recent-unwrapped --lines 80` or the session JSONL (`herdr pane get <pane> | jq -r .result.pane.agent_session.value`). Always pass resolved full `provider/model` IDs: `pi` resolves short names to the first catalog match and does not exit on `model_not_found`.

## Pitfalls (each one cost time before)

- **Do not run dependent steps in parallel.** Push and `gh pr create` in the same parallel batch made a PR fail
  to open. Reading files that a subagent is still writing gave "missing" files. Do one step, check it, then
  do the next. Always give `gh pr create --head`.
- **Never push while the implementer still works.** One push went out before a pending amend. If that
  happens, do not force-push: `git reset --soft origin/<branch>` and commit the difference as a new commit.
- **Do not start a reviewer before the implementer is done.** An empty diff wastes a review.
  `start-review.sh` refuses an empty diff.
- **gpg can expire during a long run.** pinentry cannot prompt from a non-interactive shell ("Screen or window
  too small"). The user's rule is: if signing fails, stop and report. A subagent can then leave work staged
  but not committed; after the user unlocks gpg, review the staged diff and commit it yourself.
- **Keep state out of /tmp.** State files there were lost during a run. `init.sh` puts the work directory in
  `~/.cache/pr-workflow/`. `read_file` in `common.sh` tries again on short read failures.
- **GitHub API returns short 404 errors.** Try again (`fetch-feedback.sh` does).
- **The CircleCI MCP log tool** often finds no logs or uses the wrong job number. The v1.1 API (`steps[].
  actions[].output_url`) and the v2 tests and artifacts endpoints with a token are reliable
  (`ci-failures.sh`).
- **Secrets.** Subagents sometimes put `.env` values in `/tmp` backups during builds. Check and delete them.
  The brief forbids it.
- **Shared machine state.** Do not "repair" container runtimes or services that the user also uses (for
  example `podman system migrate`). Report the problem; CI covers the affected tests.
- **Long commands in subagents** get SIGHUP (exit code 129). The brief tells them to use `nohup setsid`.
- **The automated review runs only once.** After later pushes, wait for CI only (no `--review`).
- **A dependency removal can break imports that no check sees.** Removing a package also removes its
  transitive dependencies. Code that imported one of them without declaring it breaks only at bundle time,
  and undeclared-dependency checks can miss it when the name is a Node builtin (`url`, `events`, `buffer`):
  webpack 5 does not polyfill those for the browser. Ask the implementer to build every app bundle for any
  dependency removal.
- **Screenshots cover static states only.** A CSS or framework upgrade can pass a full screenshot diff and
  still break hover, focus and open-menu states (Tailwind 4's cascade layers did). Ask for browser-level
  checks of interaction states, and for tests that assert the effective value (the computed style, or the
  declaration that wins), not a string in the output.
- **Prefer the official verifier over a bespoke one.** A 700-line hand-written "semantics check" for a
  reformat had many false negatives; `prettier --debug-check` does the same job. Tell implementers to look
  for the tool's own check before they write one (YAGNI).
- **Anything that records a commit SHA breaks under squash merges** (for example `.git-blame-ignore-revs`):
  the branch SHA does not exist on `main`. Plan a follow-up commit with the squashed SHA, or ask the user to
  rebase-merge that PR.
- **A side PR while the implementer works:** use a `git worktree` (never switch branches in the shared
  checkout). To lint or typecheck there, symlink `node_modules` from the main checkout, and delete the
  symlinks before you commit.

## Stacked PR mechanics

- Each PR targets the previous ticket's branch, so the PR diff shows only that ticket. The base branch must
  be pushed before you open the PR.
- Never amend or force-push a pushed branch unless the user asks. Fixes are new commits.
- With squash merges, when the bottom PRs merge, the next PR must be retargeted to `main` and its branch
  rebased onto `main`. That needs a force-push, so ask the user first ("please rebase" counts as yes). Steps:
  1. `git fetch --prune`. Record the old tip of every unmerged branch before you start.
  2. Check that the squash commit of the last merged PR has the content of its old branch tip:
     `git diff <old tip of last merged branch> <its squash commit on main>` must show only changes that
     other PRs made to `main` meanwhile.
  3. Rebase the first unmerged branch: `git rebase --onto origin/main <old tip of last merged branch>
     <branch>`. Then each child: `git rebase --onto <new parent tip> <old parent tip> <child>`.
  4. Check each result: every commit is still signed (`%G?` is `G`), and `git diff <old tip> <new tip>`
     equals the change on `main` (`git diff <old main> origin/main`).
  5. Push each with `git push --force-with-lease=<branch>:<old tip sha>`, and check that the remote head
     equals the local head. GitHub retargets a PR to `main` when its base branch is deleted; confirm with
     `gh pr view <PR> --json baseRefName,mergeable`.
  6. If the implementer is working in the checkout, rebase the other branches in a `git worktree`, and
     rebase the implementer's branch only after it is done (before review). An unpushed branch needs no
     force-push.
- A fix that every PR needs (for example a CI flake) belongs in its own small PR off `main`, not in the stack.

## Tracker hygiene (Linear)

- Claim at start (assignee "me", "In Progress"), "In Review" when the PR opens.
- File follow-ups as new tickets with `relatedTo`, the label "written by claude", state "Backlog". Do not
  post them as PR comments.
- Add findings that belong to another ticket as a comment on that ticket (for example a ready patch).
- A ticket that a PR fixes on the side: comment the PR link and set it "In Review" too.

## Writing style for PR text and replies

Follow the user's writing rules (for example: no em dashes, short sentences). Replies are first person as the
PR author, say what changed with commit shas, or why not.

### PR descriptions

Keep them short. A PR description says what changed and why, as the final state of the code. It does not tell
the story of how the work got there: no attempts, no command logs, no list of review findings or fixes. That
detail goes in the report (`$PR_WORK/$T-report.md`). The sections (the brief has the same list):

- a summary: a few bullets on what changed and why (one bullet can name the new test coverage),
- "Decisions and open questions": the choices made, and what a reviewer should think about (omit if none),
- "Manual checks still needed": exact steps (omit if none),
- `## Reviews`: only the table from `review-summary.sh --update-pr` (round, reviewer model, finding counts),
- `Closes <TICKET>` for a tracker ticket.

When later commits change the PR, rewrite the description for the new final state. Do not append a history.
