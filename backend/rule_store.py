"""Preview and persist explicitly selected rule changes for the single-worker POC."""
import hashlib
import json
import os
from pathlib import Path


def digest(content):
    return hashlib.sha256(content.encode('utf-8')).hexdigest() if content is not None else None


def read(path):
    return path.read_text(encoding='utf-8') if path.exists() else None


def proposals(root, run, changes):
    result = []
    for change in changes:
        rid = change['id']
        current = read(root / 'approved' / f'{rid}.md')
        retiring = change['kind'] == 'removed'
        candidate = change['after'] or change['before']
        status = 'retired' if retiring else 'approved'
        content = '\n'.join(['---', f'id: {rid}', f'status: {status}',
            'source: ' + json.dumps(Path(run['input']['filename']).name),
            f'line: {candidate["line"]}', '---', f'# {candidate["title"]}', '',
            candidate['description'], '', '## Source evidence', '',
            '```text', candidate['evidence'].replace('```', '~~~'), '```', '',
            '## Change', '', f'Detected change: {change["kind"]}.',
            'Retirement removes this rule from the active approved set.' if retiring else
            'This approval records the shown source evidence; it does not prove program behavior.', ''])
        result.append({'id': rid, 'kind': change['kind'],
            'action': 'retire' if retiring else 'update' if current is not None else 'create',
            'selectable': not retiring or current is not None,
            'reason': 'No active approved file exists to retire.' if retiring and current is None else '',
            'expected_hash': digest(current), 'previous_content': current,
            'target': f'archived/{run["id"]}/{rid}.retired.md' if retiring else f'approved/{rid}.md',
            'markdown': content})
    return result


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    try:
        temporary.write_text(content, encoding='utf-8')
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def apply(root, run, selected, record):
    """Return saved paths and a rollback callback; caller persists DB before final success."""
    available = {p['id']: p for p in run.get('rule_proposals', [])}
    if len(selected) != len(set(selected)) or any(rid not in available or not available[rid]['selectable'] for rid in selected):
        raise ValueError('Select only available rule proposals, once each.')
    # Validate the whole selection before touching any files.
    for rid in selected:
        if digest(read(root / 'approved' / f'{rid}.md')) != available[rid]['expected_hash']:
            raise FileExistsError(f'{rid} changed since analysis. Run analysis again before approving.')
    originals = {}
    saved = []
    def write(path, content):
        originals.setdefault(path, read(path))
        atomic_write(path, content)
    def rollback():
        for path, original in reversed(list(originals.items())):
            if original is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, original)
    try:
        for rid in selected:
            proposal = available[rid]
            active = root / 'approved' / f'{rid}.md'
            if proposal['previous_content'] is not None:
                backup = root / 'archived' / run['id'] / f'{rid}.previous.md'
                write(backup, proposal['previous_content'])
                saved.append(str(backup.relative_to(root.parent)))
            audit = '\n## Review record\n\n```json\n' + json.dumps({
                'run_id': run['id'], 'reviewer': record['reviewer'],
                'comments': record['comments'], 'recorded_at': record['recorded_at'],
                'previous_sha256': proposal['expected_hash']}, indent=2).replace('```', '\\u0060\\u0060\\u0060') + '\n```\n'
            target = root / proposal['target']
            content = proposal['markdown'] + audit
            write(target, content)
            saved.append(str(target.relative_to(root.parent)))
            if proposal['action'] == 'retire':
                originals.setdefault(active, read(active))
                active.unlink()
        return saved, rollback
    except Exception:
        rollback()
        raise
