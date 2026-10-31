"""Deterministic PR guard: inspect approved rules against working-tree files."""
import json
import re
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

def write_report(path, root=ROOT):
    result = findings(root)
    payload = {'findings': result, 'count': len(result), 'review_required': bool(result)}
    Path(path).write_text(json.dumps(payload, indent=2))
    return payload

if __name__ == '__main__':
    import sys
    data = write_report(sys.argv[1] if len(sys.argv) > 1 else 'ruleguard-report.json')
    print(json.dumps(data, indent=2))
