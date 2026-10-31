import re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
RULES = {
 'PAY-001': ('Positive payment amount', 'Payment amount must be greater than zero', 'samples/PaymentService.cs', r'amount\s*<=\s*0'),
 'PAY-002': ('Idempotency key required', 'Payment idempotency key must not be blank', 'samples/PaymentService.cs', r'IsNullOrWhiteSpace\(idempotencyKey\)'),
 'PAY-003': ('Prevent duplicate capture', 'Existing idempotency keys must be rejected before insertion', 'samples/CapturePayment.sql', r'IF\s+EXISTS\s*\(\s*SELECT.*?IdempotencyKey\s*=\s*@IdempotencyKey'),
 'PAY-004': ('SQL positive amount', 'SQL capture must reject nonpositive amounts', 'samples/CapturePayment.sql', r'@Amount\s*<=\s*0'),
}
def discover():
 out = ROOT/'rules/drafts'; out.mkdir(parents=True,exist_ok=True)
 results=[]
 for rid,(title,desc,source,pattern) in RULES.items():
  content=(ROOT/source).read_text()
  match=re.search(pattern,content,re.I|re.S)
  if match:
   line=content[:match.start()].count('\n')+1
   path=out/f'{rid}.md'
   path.write_text(f'---\nid: {rid}\nstatus: draft\nsource: {source}\nline: {line}\n---\n# {title}\n\n{desc}\n\nEvidence: `{match.group(0)[:180]}`\n')
   results.append(str(path.relative_to(ROOT)))
 return results
def review():
 try:
  names=subprocess.run(['git','diff','--cached','--name-only'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.splitlines()
  staged={p:subprocess.run(['git','show',f':{p}'],cwd=ROOT,capture_output=True,text=True).stdout for p in names}
 except subprocess.CalledProcessError: return []
 alerts=[]
 for rid,(title,desc,source,pattern) in RULES.items():
  if not (ROOT/'rules/approved'/f'{rid}.md').exists() or source not in staged: continue
  if not re.search(pattern,staged[source],re.I|re.S): alerts.append(f'{rid}: Possible violation: {title}. {desc} ({source})')
 return alerts
