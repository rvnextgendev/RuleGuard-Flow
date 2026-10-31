"""Deterministic PR guard: inspect approved rules against working-tree files."""
import json
import re
import subprocess
from pathlib import Path
from engine import ROOT, RULES

def findings(root=ROOT):
    result = []
    for rid, (title, desc, source, pattern) in RULES.items():
        if not (root / 'rules' / 'approved' / f'{rid}.md').exists():
            continue
        file = root / source
        if not file.exists() or not re.search(pattern, file.read_text(), re.I | re.S):
            result.append({'id': rid, 'title': title, 'description': desc, 'source': source})
    return result

def approved_rule_changes(root, base, head='HEAD'):
    """Compare explicit PR revisions; additions, edits, deletions and moves require review."""
    paths = subprocess.run(
        ['git', 'diff', '--no-ext-diff', '--no-renames', '--name-only', '-z', base, head, '--'],
        cwd=root, capture_output=True, check=True).stdout.decode('utf-8').split('\0')
    return sorted({p for p in paths if p.startswith('rules/approved/')})


def write_report(path, root=ROOT, base=None, head='HEAD'):
    result = findings(root)
    changed = approved_rule_changes(root, base, head) if base else []
    payload = {'findings': result, 'count': len(result), 'approved_rule_changes': changed,
               'review_required': bool(result or changed),
               'approval_reasons': (['Approved rule files changed'] if changed else []) + (['Baseline violations detected'] if result else [])}
    Path(path).write_text(json.dumps(payload, indent=2))
    return payload

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('report', nargs='?', default='ruleguard-report.json')
    parser.add_argument('--base')
    parser.add_argument('--head', default='HEAD')
    args = parser.parse_args()
    data = write_report(args.report, base=args.base, head=args.head)
    print(json.dumps(data, indent=2))
