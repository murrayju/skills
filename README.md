# skills

Personal collection of [pi](https://github.com/earendil-works/pi) agent skills.

Each skill lives in its own directory containing a `SKILL.md` file with YAML
frontmatter (`name`, `description`) followed by the instructions the agent
loads when the skill is invoked.

## Skills

- **review**: Run a focused code review using a stronger subagent model. By
  default reviews the current branch (all commits since it diverged from the
  default branch) for bugs, logic errors, security issues, and missed edge
  cases. Supports a custom revision range and a selectable reviewer model.
  Prefers `herdr_subagent` (from `murrayju/pi-herdr-subagents`) in a named
  Herdr tab, with manual Herdr/tmux/`pi -p` fallback. Invoke via
  `/skill:review`, `/skill:review main..HEAD`, or
  `/skill:review --model gpt-5.5`.

- **pr-workflow**: Take a task or ticket to a green PR. The agent stays the
  orchestrator: a fresh pi subagent in a named Herdr tab (`herdr_subagent`,
  with manual split-pane fallback) implements the work, a `scribe` subagent
  composes human-facing text (PR descriptions and documentation), a sequence of
  reviewer models reviews it before the PR opens, then CI goes green, the PR
  feedback is addressed, and the reviewers run again until no high or medium
  findings remain. A list of tickets (for example a Linear epic) repeats the
  loop as stacked PRs managed with `gh stack` so the stack can be reviewed and
  merged all at once. Includes helper scripts and subagent brief templates.

## Shared scripts

`scripts/` at the root of this repo holds the scripts that more than one skill
uses. A skill links to them instead of copying them, for example
`review/scripts/resolve-model.sh -> ../../scripts/resolve-model.sh`. The links
are relative, so a clone works anywhere. A skill moved out of this repo on its
own also needs the shared folder.

`scripts/resolve-model.sh` resolves the name of a model, as a user says it, to
the full `provider/model` IDs from the live `pi --list-models` catalog. It ranks
an exact ID first, then the provider (`concentrate`, then `openrouter`, then the
others), then the newest generation, and it prints the best three. Both the
`review` and `pr-workflow` skills use it.

## Usage

Clone this repo into your pi skills directory:

```bash
git clone git@github.com:murrayju/skills.git ~/.agents/skills
```
