# skills

Personal collection of [pi](https://github.com/earendil-works/pi) agent skills.

Each skill lives in its own directory containing a `SKILL.md` file with YAML
frontmatter (`name`, `description`) followed by the instructions the agent
loads when the skill is invoked.

## Skills

- **review** — Run a focused code review using a stronger subagent model. By
  default reviews the current branch (all commits since it diverged from the
  default branch) for bugs, logic errors, security issues, and missed edge
  cases. Supports a custom revision range and a selectable reviewer model.
  Invoke via `/skill:review`, `/skill:review main..HEAD`, or
  `/skill:review --model gpt-5.5`.

- **stacked-pr-orchestration**: Work through a series of tickets (for example
  the sub-issues of a Linear epic) as a stack of green PRs. The agent stays the
  orchestrator: each ticket gets a fresh pi subagent in a herdr pane, a
  second-opinion review by another model, a stacked PR, and the automated
  review and CI loop until green. Includes helper scripts and a subagent brief
  template.

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
`review` and `stacked-pr-orchestration` skills use it.

## Usage

Clone this repo into your pi skills directory:

```bash
git clone git@github.com:murrayju/skills.git ~/.agents/skills
```
