from pathlib import Path
import subprocess
root=Path(__file__).resolve().parent
hook_dir=subprocess.run(['git','rev-parse','--git-path','hooks'],cwd=root,capture_output=True,text=True,check=True).stdout.strip()
hook=Path(hook_dir)
if not hook.is_absolute(): hook=root/hook
hook.mkdir(parents=True,exist_ok=True)
p=hook/'pre-commit'
p.write_text('#!/bin/sh\ncd "$(git rev-parse --show-toplevel)" || exit 1\ndocker compose run --rm --no-deps -T app python app/cli.py review\n')
p.chmod(0o755)
print('Installed:',p)
