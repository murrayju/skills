---
name: stacked-pr-orchestration
description: Orchestrate a series of tickets (for example the sub-issues of a Linear epic) as a stack of green PRs. You stay the orchestrator; each ticket is implemented by a fresh pi subagent in a herdr pane (with an Advisor model), reviewed in two rounds by two other models (no Advisor), then pushed as a stacked PR, taken through the automated Claude review and CI until green, before the next ticket starts. Ask the user for the models up front. Use when the user asks to work through many tickets one at a time with subagents, herdr, stacked PRs, or "only move on when green".
---

# Stacked green PRs with herdr + pi subagents

You are the **orchestrator**. You do not write the feature code. You:

1. pick the next ticket and claim it in the tracker,
2. make its branch on top of the previous ticket's branch,
3. start a fresh implementer subagent for that one ticket,
4. validate its work, get review round 1, push, and open a stacked PR,
5. get review round 2 next to the automated PR review, and take the PR through CI until it is green,
6. only then move to the next ticket.

The scripts in `scripts/` encode the lessons from earlier runs. Use them. They are
config-driven (`$STACK_WORK/config.env`), so they work for any repository.

## Roles and models

| role | how | config key | default model |
| -- | -- | -- | -- |
| orchestrator | you, in the herdr pane the user talks to | | (current) |
| implementer | `pi` in a new herdr pane, one per ticket, clean context | `IMPLEMENTER_MODEL` | `concentrate/deepseek-v4-1-flash-1017` |
| Advisor of the implementer | pi-advisor extension (`ask_advisor` tool and gates), global config | `ADVISOR_MODEL` | `concentrate/claude-opus-5-5` |
| reviewer, round 1 | `pi` in a pane below the implementer, read-only, NO Advisor, before the PR opens | `REVIEWER_MODEL_1` | `openai-codex/gpt-6.1-sol` |
| reviewer, round 2 | the same, after the round 1 fixes, next to the automated PR review | `REVIEWER_MODEL_2` | `concentrate/claude-opus-5-5` |
| automated PR review | GitHub Action (`claude-review` check), runs when the PR opens | | (repo config) |

All pi agents run with `THINKING` (default high). Fallback for the implementer if concentrate is down:
`openrouter/deepseek/deepseek-v4.1-flash-1017`. Tell the user when you switch models (edit `config.env`).

**Two review rounds, two model families.** Each round found real bugs that the other round and the
automated review missed (lost hover states, a rem fallback that beat the px theme, a deploy race, a
silently skipped CI test). Round 2 gets the round 1 report and the automated review (`start-review.sh`
passes them), so it checks the fixes and looks for what the others missed.

## Before you start: ask the user

Ask these in one message, before `init.sh`, and wait for the answers. Show the defaults.

1. **Models** for the implementer, the Advisor, reviewer 1 and reviewer 2. The defaults suit routine
   dependency and refactor work. For complex or risky work (architecture, security, data migrations, large
   UI rewrites), offer stronger reviewers, for example `openai-codex/gpt-6-astra` and
   `concentrate/claude-fable-5-1`. The Advisor model is global (`~/.pi/agent/advisor.json`): if the user
   wants a different one, they change it with `/advisor-models`, not you.
2. **Scope:** the epic or ticket list, and tickets to skip or that need a product or infra decision.
3. **Authority outside the repo:** publishing packages, release tags, deploys, infra changes. Default: do
   not do them; park the ticket and ask.
4. **Merge strategy** (squash or rebase) and whether to pause after each PR.

Check each model id with `pi --list-models <id>`, then pass the answers to `init.sh` (below).

**Advisor rules.** The implementer gets the Advisor from the global pi-advisor config
(`~/.pi/agent/advisor.json`: `advisorToolsEnabled` true, `advisor` = `ADVISOR_MODEL`). `preflight.sh` checks
this and fails if it is off, if the model differs, or if it equals the implementer model (pi-advisor then
skips every call). Do not change `advisor.json` yourself: it is the user's global setting. Ask the user to run
`/advisor` or `/advisor-models`. If concentrate is down, the Advisor is down too; tell the user. The reviewers
must use only their own model: `start-review.sh` passes `--exclude-tools ask_advisor,record_advisor_outcome`,
which removes the tool, the prompt rules and the automatic gates. Keep that flag.

**Check that the Advisor is used, not only available.** The declaration alone is not enough: workers whose
brief did not mention the Advisor called it about once per ticket (the completion gate). Count the calls in
the pane's session (`grep -o '"toolName":"ask_advisor"' <session.jsonl> | wc -l`) or read the pi footer
(`Advisor: N calls`). In the first prompt, name the decisions that deserve a consult. If a worker on a large
ticket has not called it after an hour, send a steering prompt that names the decisions.

The reviews are worth it: on earlier runs they found real regressions on most PRs that the automated review
missed (lost images, skipped saves, unbounded caches, wrong focus handling).

## One-time setup

```bash
test "$HERDR_ENV" = 1            # Stop if you are not in herdr.
S=~/.agents/skills/stacked-pr-orchestration/scripts
# The models the user chose (any one you leave out gets its default).
eval "$(IMPLEMENTER_MODEL=<m> ADVISOR_MODEL=<m> REVIEWER_MODEL_1=<m> REVIEWER_MODEL_2=<m> \
  $S/init.sh <RUN_ID> <REPO_PATH>)"   # Prints: export STACK_WORK=~/.cache/stacked-pr/<RUN_ID>
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
   that earlier tickets in the stack already provide, the decisions to take to the Advisor, and what not to
   do (out-of-scope follow-ups). Use the pane id that the script prints; never guess it.
4. **Wait.** `$S/wait-done.sh $T`. It prints progress every 5 minutes. Exit codes: 0 done; 3 its own
   time limit (call it again); 5 the agent is idle without the signal file (it stopped early: an API
   error, a question, or a BLOCKED report; the script shows its screen); 1 the pane closed (pi exited).
   Large tickets take 1 to 3 hours. Wait with long bash timeouts (about 3500 s) and loop. Do not poll
   every minute.
5. **Validate.** Read `$STACK_WORK/$T-report.md`. Check `git status` (clean), `git log --format='%h %G? %s'
   $BASE..HEAD` (all commits signed: `G`), and look at the key production diffs yourself. Look for
   left-over secrets: `find $STACK_WORK /tmp -name '*env*'`.
6. **Review round 1.** `$S/start-review.sh $T $BASE 1`, then `$S/wait-review.sh $T`. If it reports
   "No issues found" with no "What I checked" section, ask for evidence before you trust it. Send real
   findings to the implementer (step 9 pattern, with signal `fix-done`), wait, and check the fix diff.
7. **Open the PR.** `$S/create-pr.sh $T $BASE` (it refuses a dirty tree and em dashes, pushes, checks that
   the remote head equals HEAD, and opens the PR against the previous branch). Set the ticket to
   "In Review".
8. **Wait for CI and the automated review, then review round 2.** `$S/wait-pr.sh <PR> 80 --review` (the
   first time only), `$S/fetch-review.sh $T`, then `$S/start-review.sh $T $BASE 2` and
   `$S/wait-review.sh $T`. Round 2 reads the round 1 report and the automated review.
9. **Address round 2 and the automated review together.** Send the implementer ONE prompt with
   `$S/prompt.sh <pane> "..."`. Name the review files, say for each item whether to fix it or to reply only,
   ask for NEW commits, a replies file `$STACK_WORK/$T-replies.md` (format in the brief; inline replies are
   for the automated review's comment ids), an updated PR description if material, and, as the very last
   action, `touch $STACK_WORK/$T-fix2-done`. Then `$S/wait-done.sh $T fix2-done`. For a later round, use
   `$T-replies2.md` and `$S/post-replies.py $T <PR> $STACK_WORK/$T-replies2.md`.
   - Fix in the PR: real bugs, test gaps, robustness, small cleanups in the touched code.
   - Reply only: pre-existing problems, product decisions, and large refactors. Put them under
     `## follow-ups` and file Linear tickets for them (`save_issue` with `relatedTo: [T]`, the label
     "written by claude").
   - Reply with evidence: findings that are wrong. Reviewers are wrong sometimes, and so is the automated
     review (it once called real formatter output "reconstructed" because it could not run the formatter).
     When a reviewer contradicts the implementer, or two reviews disagree, settle it with a reproduction or
     a tool run, not by majority. Ask the implementer to verify a contested claim before it changes code.
10. **Push and reply.** `$S/push-check.sh`, `gh pr edit <PR> --body-file $STACK_WORK/$T-pr.md`,
    `$S/post-replies.py $T` (posts the top-level reply and one reply to each inline comment; it skips
    `## follow-ups`).
11. **CI until green.** `$S/wait-pr.sh <PR> 80`. On a failure, see "CI failures". Do not move on while
    any check is red.
12. **Close out.** `$S/close-panes.sh $T` (closes only the panes that this run recorded for the ticket;
    never close the user's own panes), mark the ticket done in `ORDER.txt`, and start the next ticket with
    `BASE` = this ticket's branch.

If a ticket needs no change after investigation (tracking tickets, still blocked upstream), let the subagent
write only a report, comment the findings on the ticket, move it back to Backlog, and delete the empty branch.

If a ticket needs an action outside the repo that the user did not authorize (publishing a package, a release
tag in another repository, a deploy, an infra change), park it in `ORDER.txt` with the reason, move on to the
next ticket, and ask the user in the status summary. Work that you cannot verify locally (for example a
staging deploy) goes under "Manual checks still needed" with the exact commands.

If the user asks you to pause: finish the current ticket to green, close the panes, and give a status summary
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

## herdr + pi: what works

- **Start pi with its first prompt as a positional message** (the method of the `review` skill):
  `herdr pane split --pane "$HERDR_PANE_ID" --direction right --cwd <repo> --no-focus`, write a runner
  script `exec pi --model <provider/model> --thinking high "$(cat <prompt file>)"`, then
  `herdr pane run <pane> "exec <runner>"`. `launch_pi` in `common.sh` does this. The first prompt cannot
  get lost, the command line stays short, and the pane closes when pi exits. herdr still detects pi in the
  pane, so `herdr agent prompt <pane>` works for later rounds.
- Do not use `herdr agent start` + an immediate `herdr agent prompt` for the first prompt: right after a
  start, prompts were rejected (`agent_not_found`, `agent_prompt_stalled`), and a rejected prompt is not
  delivered.
- **Target agents by pane id, not by name.** herdr loses agent names (`agent_not_found`). Pane ids stay
  stable.
- For later prompts, `herdr agent prompt` needs `--wait` before `--timeout`. Use `prompt.sh`, which tries
  again until the agent is `working`.
- A prompt to an agent that is already working is queued by pi as a steering message (the screen shows
  "Steering: ..."), and herdr reports a timeout. It is delivered at the next tool boundary. Do not send it
  again; `prompt.sh` sends it once in that case. Use this for nudges during long tickets (for example "take
  this decision to the Advisor").
- Do not trust herdr status alone. It can stay `working` long after the agent stopped, or show `done` before
  the last file writes. Use signal files plus a stable status (`wait-done.sh`).
- A closed pane: `herdr pane get` fails with error code `pane_not_found`. Other herdr errors can be short
  failures, so count a pane as closed only after 3 `pane_not_found` results in a row (`pane_gone` in
  `common.sh`).
- To see what an agent does: `herdr pane read <pane> --source visible` (or `recent-unwrapped --lines 80`;
  `pane read` works while pi is busy, but `herdr agent read` with `--lines` fails then). For tool-call
  detail, read its pi session JSONL (`herdr pane get <pane> | jq -r .result.pane.agent_session.value`).
- **A bad model id does not make pi exit.** pi shows the API error (`model_not_found`) and stays idle.
  `wait_working` catches it from the screen. Before a run, check models with `pi auth check --provider
  <p> --model <m>` (it only checks the provider) and `pi --list-models <m>` (it checks the model);
  `preflight.sh` does both.
- Only close the panes you made. The user can have panes of their own in the same workspace.
- To confirm the Advisor setup in a pane, look for an `ask_advisor` tool declaration in its pi session JSONL
  (`herdr pane get <pane> | jq -r .result.pane.agent_session.value`). The implementer must have it, the
  reviewers must not.

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
