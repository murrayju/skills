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

## Usage

Clone this repo into your pi skills directory:

```bash
git clone git@github.com:murrayju/skills.git ~/.agents/skills
```
