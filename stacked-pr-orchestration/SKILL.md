---
name: stacked-pr-orchestration
description: Orchestrate a series of tickets (for example the sub-issues of a Linear epic) as a stack of green PRs. You stay the orchestrator; each ticket is implemented by a fresh pi subagent in a herdr pane (Opus via concentrate), reviewed by a second model (gpt-6.1-sol), then pushed as a stacked PR, taken through the automated Claude review and CI until green, before the next ticket starts. Use when the user asks to work through many tickets one at a time with subagents, herdr, stacked PRs, or "only move on when green".
---

# Stacked green PRs with herdr + pi subagents

You are the **orchestrator**. You do not write the feature code. You:

1. pick the next ticket and claim it in the tracker,
2. make its branch on top of the previous ticket's branch,
3. start a fresh implementer subagent for that one ticket,
4. validate its work, get a second-opinion review, push, and open a stacked PR,
5. take the PR through the automated review and CI until it is green,
6. only then move to the next ticket.

The scripts in `scripts/` encode the lessons from earlier runs. Use them. They are
config-driven (`$STACK_WORK/config.env`), so they work for any repository.

## Roles and models

| role | how | model (default) |
| -- | -- | -- |
| orchestrator | you, in the herdr pane the user talks to | (current) |
| implementer | `pi` in a new herdr pane, one per ticket, clean context | `concentrate/claude-opus-5-5`, thinking high |
| second-opinion reviewer | `pi` in a pane below the implementer, read-only | `openai-codex/gpt-6.1-sol`, thinking high |
| automated PR review | GitHub Action (`claude-review` check), runs when the PR opens | (repo config) |

Fallback if concentrate is down: `openrouter/anthropic/claude-opus-5.5`. Tell the user when you switch
models. Change `IMPLEMENTER_MODEL` in `config.env`.

The second-opinion review is worth it: on earlier runs it found real regressions on most PRs that the
automated review missed (lost images, skipped saves, unbounded caches, wrong focus handling).

## One-time setup

```bash
test "$HERDR_ENV" = 1            # Stop if you are not in herdr.
S=~/.agents/skills/stacked-pr-orchestration/scripts
eval "$($S/init.sh <RUN_ID> <REPO_PATH>)"   # Prints: export STACK_WORK=~/.cache/stacked-pr/<RUN_ID>
$S/preflight.sh                  # herdr, gpg signing, model auth, gh auth, clean tree
```

Then:

- **Tickets.** Fetch the epic and every open sub-issue (Linear MCP from codemode: `list_issues` with
  `parentId`, `get_issue` with `includeRelations`, `list_comments`). Write each one to
  `$STACK_WORK/<ID>.md` with a line `Suggested branch: <gitBranchName>` near the top, then the description,
  then the comments (they often hold important constraints). Write the epic to `$STACK_WORK/<EPIC>.md`.
  Make sure the branch name starts with the user's prefix (for example `murrayju/`).
- **Order.** Write `$STACK_WORK/ORDER.txt`, one ticket per line. Respect the blocking relations. Put
  unblockers first. Put whole-repo reformatting (prettier and similar) last. Mark progress in this file
  (`<ID> done #<PR>`), so you can resume after a pause or a context reset.
- **Brief.** Edit `$STACK_WORK/BRIEF.md` (copied from `templates/BRIEF.md`): the repo rules, the CI
  commands, the builds to run, and the environment notes (for example the container socket). Keep the test
  coverage, committing, and deliverables sections. All subagents read it first.
- **CI facts.** Find out which checks run on PRs (`.circleci/config.yml`, `.github/workflows/*`), and how the
  automated review is triggered. In the reference repo it runs only on `opened`, `ready_for_review` and
  `review_requested`, so it reviews each PR exactly once, at creation.

## The per-ticket loop

```bash
S=~/.agents/skills/stacked-pr-orchestration/scripts
T=POP-1234; BASE=<previous ticket branch, or main for the first>
```

1. **Preflight.** `$S/preflight.sh`. If gpg signing fails, STOP and ask the user to unlock gpg (see Pitfalls).
2. **Claim the ticket** in Linear: `save_issue({id, assignee: "me", state: "In Progress"})`, then
   `get_issue` to confirm it (the update can silently not apply; repeat it).
3. **Start the implementer.** `$S/start-ticket.sh $T $BASE "<ticket-specific guidance>"`.
   Give specific guidance: the risky call sites, what to characterize before the change, the prerequisites
   that earlier tickets in the stack already provide, and what not to do (out-of-scope follow-ups).
4. **Wait.** `$S/wait-done.sh $T` (prints progress every 5 minutes; returns exit code 3 on its own time
   limit, so call it again). Large tickets take 1 to 3 hours. Wait with long bash timeouts (about
   3500 s) and loop. Do not poll every minute.
5. **Validate.** Read `$STACK_WORK/$T-report.md`. Check `git status` (clean), `git log --format='%h %G? %s'
   $BASE..HEAD` (all commits signed: `G`), and look at the key production diffs yourself. Look for
   left-over secrets: `find $STACK_WORK /tmp -name '*env*'`.
6. **Second-opinion review.** `$S/start-review.sh $T $BASE`, then `$S/wait-review.sh $T`. If it reports
   "No issues found" with no "What I checked" section, ask for evidence before you trust it. Send real
   findings to the implementer (step 9 pattern, with signal `fix-done`), wait, and check the fix diff.
7. **Open the PR.** `$S/create-pr.sh $T $BASE` (it refuses a dirty tree and em dashes, pushes, checks that
   the remote head equals HEAD, and opens the PR against the previous branch). Set the ticket to
   "In Review".
8. **Wait for CI and the automated review.** `$S/wait-pr.sh <PR> 80 --review` (the first time only), then
   `$S/fetch-review.sh $T`.
9. **Address the review.** Send the implementer one prompt with `$S/prompt.sh <pane> "..."`. Name the
   review files, say for each item whether to fix it or to reply only, ask for NEW commits, a replies file
   `$STACK_WORK/$T-replies.md` (format in the brief), an updated PR description if material, and, as the
   very last action, `touch $STACK_WORK/$T-fix2-done`. Then `$S/wait-done.sh $T fix2-done`.
   - Fix in the PR: real bugs, test gaps, robustness, small cleanups in the touched code.
   - Reply only: pre-existing problems, product decisions, and large refactors. Put them under
     `## follow-ups` and file Linear tickets for them (`save_issue` with `relatedTo: [T]`, the label
     "written by claude").
10. **Push and reply.** `$S/push-check.sh`, `gh pr edit <PR> --body-file $STACK_WORK/$T-pr.md`,
    `$S/post-replies.py $T` (posts the top-level reply and one reply to each inline comment; it skips
    `## follow-ups`).
11. **CI until green.** `$S/wait-pr.sh <PR> 80`. On a failure, see "CI failures". Do not move on while
    any check is red.
12. **Close out.** `$S/close-panes.sh`, mark the ticket done in `ORDER.txt`, and start the next ticket with
    `BASE` = this ticket's branch.

If a ticket needs no change after investigation (tracking tickets, still blocked upstream), let the subagent
write only a report, comment the findings on the ticket, move it back to Backlog, and delete the empty branch.

If the user asks you to pause: finish the current ticket to green, close the panes, and give a status summary
(PR table, follow-up tickets filed, what needs the user, the next ticket).

## CI failures

Run `$S/ci-failures.sh <PR>` first (or `$S/ci-failures.sh job:<N>` for one job). Decide between "flake or infrastructure" and "real":

- **Infrastructure:** backend services that do not start ("Kafka not ready", docker buildkit "EOF"). Rerun
  the failed jobs (CircleCI MCP `rerun_workflow` with `{workflowId, fromFailed: true}`).
- **Known flake:** if the same failure also happens on `main`, it is not your change. Rerun, AND file a
  ticket. If it keeps failing, find the root cause: download the Playwright trace artifacts with the
  CircleCI API token and search them (`location.url` of console errors). A recurring flake is worth its own
  small PR off `main`.
- **Real:** send the failure (job number, test, error) to the implementer. Timing-sensitive tests usually
  wait for a short transient state. Ask for a fix that waits for a stable end state, verified with
  repeated runs under CPU load.

Check the commit statuses of recent `main` commits to see if a check is already red there:
`gh api repos/<owner>/<repo>/commits/<sha>/statuses`.

## herdr + pi: what works

- Start an agent: `herdr pane split --pane "$HERDR_PANE_ID" --direction right --cwd <repo> --no-focus`, then
  `herdr agent start <name> --kind pi --pane <id> -- --model <provider/model> --thinking high`.
- **Target agents by pane id, not by name.** herdr loses agent names (`agent_not_found`) after pi reports its
  session. Pane ids stay stable.
- `herdr agent prompt` needs `--wait` before `--timeout`. A rejected prompt is not delivered. Use
  `prompt.sh`, which tries again until the agent is `working`.
- Do not trust herdr status alone. It can stay `working` long after the agent stopped, or show `done` before
  the last file writes. Use signal files plus a stable status (`wait-done.sh`).
- To see what a busy agent does: `herdr agent read <pane> --source visible`, or read its pi session JSONL
  (`herdr agent get <pane> | jq -r .result.agent.agent_session.value`). Long `--lines` reads fail while the
  agent works.
- If a pane shows `Model "..." not found`, pi did not start. Check `pi auth check --provider <p> --model <m>`
  (it only checks the provider) and `pi --list-models <m>` (it checks the model).

## Pitfalls (each one cost time before)

- **Do not run dependent steps in parallel.** Push and `gh pr create` in the same parallel batch made a PR fail
  to open. Reading files that a subagent is still writing gave "missing" files. Do one step, check it, then
  do the next. Always give `gh pr create --head`.
- **Never push while the implementer still works.** One push went out before a pending amend. If that
  happens, do not force-push: `git reset --soft origin/<branch>` and commit the difference as a new commit.
- **Do not start the reviewer before the implementer is done.** An empty diff wastes a review.
  `start-review.sh` refuses an empty diff.
- **gpg can expire during a long run.** pinentry cannot prompt from a non-interactive shell ("Screen or window
  too small"). The user's rule is: if signing fails, stop and report. A subagent can then leave work staged
  but not committed; after the user unlocks gpg, review the staged diff and commit it yourself.
- **Keep state out of /tmp.** State files there were lost during a run. `init.sh` puts the work directory in
  `~/.cache/stacked-pr/`. `read_file` in `common.sh` tries again on short read failures.
- **GitHub API returns short 404 errors.** Try again (`fetch-review.sh` does).
- **The CircleCI MCP log tool** often finds no logs or uses the wrong job number. The v1.1 API (`steps[].
  actions[].output_url`) and the v2 tests and artifacts endpoints with a token are reliable
  (`ci-failures.sh`).
- **Secrets.** Subagents sometimes put `.env` values in `/tmp` backups during builds. Check and delete them.
  The brief forbids it.
- **Shared machine state.** Do not "repair" container runtimes or services that the user also uses (for
  example `podman system migrate`). Report the problem; CI covers the affected tests.
- **Long commands in subagents** get SIGHUP (exit code 129). The brief tells them to use `nohup setsid`.
- **The automated review runs only once.** After later pushes, wait for CI only (no `--review`).

## Stacked PR mechanics

- Each PR targets the previous ticket's branch, so the PR diff shows only that ticket. The base branch must
  be pushed before you open the PR.
- Never amend or force-push a pushed branch unless the user asks. Fixes are new commits.
- With squash merges, when the bottom PR merges, the next PR must be retargeted to `main` and its branch
  rebased onto `main` (`git rebase --onto origin/main <old base sha>`). That needs a force-push, so ask the
  user first.
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
