"""Git integration checks for PR edits to the approved rule set."""
import subprocess
import sys
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'app'))
from approval import approved_rule_changes, write_report


def git(root, *args):
    return subprocess.run(['git', *args], cwd=root, capture_output=True, text=True, check=True).stdout.strip()


@pytest.fixture
def repo(tmp_path):
    git(tmp_path, 'init')
    git(tmp_path, 'config', 'user.name', 'Tests')
    git(tmp_path, 'config', 'user.email', 'tests@example.com')
    approved=tmp_path/'rules/approved';approved.mkdir(parents=True)
    (approved/'CUSTOM.md').write_text('Original rule')
    (tmp_path/'README.md').write_text('Readme')
    git(tmp_path,'add','.')
    git(tmp_path,'commit','-m','baseline')
    return tmp_path,git(tmp_path,'rev-parse','HEAD')


@pytest.mark.parametrize('action',['add','edit','delete','move'])
def test_approved_rule_changes_require_business_review(repo, action):
    root,base=repo
    path=root/'rules/approved/CUSTOM.md'
    if action=='add': (path.parent/'NEW.md').write_text('New rule')
    elif action=='edit': path.write_text('Changed rule')
    elif action=='delete': path.unlink()
    else: path.rename(root/'retired.md')
    git(root,'add','-A');git(root,'commit','-m',action)
    report=write_report(root/'report.json',root,base=base)
    assert report['review_required']
    assert report['approved_rule_changes']
    assert not report['findings']  # Generic approved rules require review without PAY violations.


def test_unrelated_changes_do_not_trigger_rule_approval(repo):
    root,base=repo
    (root/'README.md').write_text('Docs only')
    git(root,'add','.');git(root,'commit','-m','docs')
    assert not write_report(root/'report.json',root,base=base)['review_required']


def test_invalid_base_fails_closed(repo):
    root,_=repo
    with pytest.raises(subprocess.CalledProcessError):
        approved_rule_changes(root,'missing-revision')
