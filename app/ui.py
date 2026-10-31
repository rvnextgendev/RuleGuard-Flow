import streamlit as st
from engine import ROOT, discover, review, RULES
st.set_page_config(page_title='Payment Rule Guard',layout='wide')
st.title('Payment Rule Guard · POC')
tab1,tab2,tab3=st.tabs(['Discover','Manage Rules','Developer Review'])
with tab1:
 st.write('Discover candidate rules from C# and SQL. AI candidates require manual approval.')
 mode=st.radio('Discovery mode',['AI','Pattern-based baseline'])
 if st.button('Discover rules'):
  try:
   if mode.startswith('AI'):
    from discovery_ai import discover_ai
    generated=discover_ai()
   else:
    generated=discover()
   st.success(f'Generated {len(generated)} draft rule(s)')
   st.write(generated)
  except Exception as e: st.error(f'Discovery failed: {e}')
with tab2:
 drafts=sorted((ROOT/'rules/drafts').glob('*.md'))
 if not drafts: st.info('Run discovery first')
 for draft in drafts:
  rid=draft.stem
  approved=ROOT/'rules/approved'/draft.name
  with st.expander(f'{rid} · '+('Approved' if approved.exists() else 'Draft')):
   content=st.text_area('Review/edit',draft.read_text(encoding='utf-8'),key=rid,height=180)
   if st.button('Approve',key='approve'+rid):
    approved.parent.mkdir(exist_ok=True,parents=True)
    approved.write_text(content.replace('status: draft','status: approved'),encoding='utf-8')
    st.success('Approved; commit this file to share it')
with tab3:
 st.write('Deterministic staged checks cover the baseline PAY rules; newly discovered AI rules are advisory only.')
 if st.button('Review staged changes'):
  alerts=review()
  if alerts:
   for a in alerts: st.warning(a)
  else: st.info('No detectable baseline violations in staged files; not a guarantee.')
 proposed=st.text_area('Paste proposed code or a question (optional)',height=160)
 if st.button('Ask AI'):
  try:
   from llm import explain
   context='\n'.join(p.read_text() for p in (ROOT/'rules/approved').glob('*.md'))[:12000]
   st.write(explain('Approved rules:\n'+context+'\nDeveloper input:\n'+proposed[:12000]))
  except Exception as e: st.error(f'LLM unavailable: {e}')
st.divider()
st.subheader('Business Owner Approval · POC')
st.caption('GitHub Environment reviewers provide actual approval. This page previews baseline findings only.')
try:
 from approval import findings
 pending=findings()
 if pending:
  for finding in pending: st.warning(f"{finding['id']} · {finding['title']}: {finding['description']}")
 else: st.success('No detected baseline rule violations.')
except Exception as exc: st.warning(f'Approval preview unavailable: {exc}')
