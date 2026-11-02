#!/usr/bin/env python3
# Usage: post-replies.py <TICKET> [PR]
# Read $STACK_WORK/<TICKET>-replies.md. Post "## top-level" as a PR comment,
# and each "## inline <id>" as a reply to that review comment. Do not post
# other sections (for example "## follow-ups": put those in the tracker).
import os, re, subprocess, sys, tempfile

work = os.environ['STACK_WORK']
cfg = dict(re.findall(r'^(\w+)="?([^"\n]*)"?$', open(f'{work}/config.env').read(), re.M))
ticket = sys.argv[1]
pr = sys.argv[2] if len(sys.argv) > 2 else open(f'{work}/{ticket}-pr-number').read().strip()
text = open(f'{work}/{ticket}-replies.md').read()
for section in re.split(r'^## ', text, flags=re.M)[1:]:
    head, _, body = section.partition('\n')
    head = head.strip()
    if head == 'top-level':
        target = None
    elif head.startswith('inline '):
        target = head.split()[1]
    else:
        print(f'skip section: {head}')
        continue
    with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False) as f:
        f.write(body.strip())
    if target is None:
        cmd = ['gh', 'pr', 'comment', pr, '--body-file', f.name]
    else:
        cmd = ['gh', 'api', f"repos/{cfg['GH_REPO']}/pulls/{pr}/comments/{target}/replies",
               '-F', f'body=@{f.name}', '--jq', '.html_url']
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=cfg['REPO'])
    os.unlink(f.name)
    print(head, r.returncode, (r.stdout + r.stderr).strip()[:150])
