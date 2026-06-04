# skills

Personal collection of [pi](https://github.com/earendil-works/pi) agent skills.

Each skill lives in its own directory containing a `SKILL.md` file with YAML
frontmatter (`name`, `description`) followed by the instructions the agent
loads when the skill is invoked.

## Skills

- **review** — Run a focused code review using an Opus subagent. Reviews the
  diff of the latest commit (or a specified range) for bugs, logic errors,
  security issues, and missed edge cases. Invoke via `/skill:review` or
  `/skill:review HEAD~3..HEAD`.

## Usage

Clone this repo into your pi skills directory:

```bash
git clone git@github.com:murrayju/skills.git ~/.agents/skills
```
