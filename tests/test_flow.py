from fastapi.testclient import TestClient
from backend import main
import pytest

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, 'DB', tmp_path / 'runs.db')
    import shutil
    shutil.copytree(main.ROOT / 'rules', tmp_path / 'rules')
    monkeypatch.setattr(main, 'RULE_ROOT', tmp_path / 'rules')
    return TestClient(main.app)

def run(client, sample):
    response = client.post('/api/runs', json={k: sample[k] for k in ('filename','before','after')})
    assert response.status_code == 202
    return client.get('/api/runs/' + response.json()['id']).json()

def test_payment_removed_and_decision_persisted(client):
    sample = client.get('/api/samples').json()[0]
    result = run(client, sample)
    assert result['status'] == 'awaiting_review'
    assert any(c['id']=='PAY-001' and c['kind']=='removed' for c in result['nodes'][2]['output']['changes'])
    url = '/api/runs/' + result['id'] + '/decision'
    assert client.post(url, json={'decision':'approved','reviewer':' ','comments':'ok'}).status_code == 422
    assert client.post(url, json={'decision':'approved','reviewer':'Demo owner','comments':'Reviewed diff and tests'}).status_code == 200
    assert client.get('/api/runs/'+result['id']).json()['decision']['reviewer']=='Demo owner'
    assert client.post(url, json={'decision':'rejected','reviewer':'Other','comments':'again'}).status_code == 409
    assert client.get('/api/runs').json()[0]['status']=='approved'

def test_term_change_and_unchanged(client):
    sample = client.get('/api/samples').json()[2]
    result = run(client, sample)
    assert result['nodes'][2]['output']['changes'][0]['kind']=='modified'
    sample['after']=sample['before']
    result=run(client,sample)
    assert result['nodes'][2]['output']['changes']==[]
    assert not result['nodes'][2]['output']['code_changed']

def test_sql_and_invalid_input(client):
    result=run(client, client.get('/api/samples').json()[1])
    assert 'PAY-003' in [c['id'] for c in result['nodes'][2]['output']['changes']]
    assert client.get('/api/runs/unknown').status_code==404
    assert client.post('/api/runs',json={'filename':'file.py','before':'x','after':''}).status_code==422

def test_ai_failure_retains_results(client, monkeypatch):
    import sys, types
    module=types.ModuleType('llm')
    def fail(_): raise RuntimeError('provider down')
    module.explain=fail
    monkeypatch.setitem(sys.modules,'llm',module)
    sample=client.get('/api/samples').json()[0]
    response=client.post('/api/runs',json={**{k:sample[k] for k in ('filename','before','after')},'use_ai':True})
    result=client.get('/api/runs/'+response.json()['id']).json()
    assert result['status']=='awaiting_review'
    assert result['nodes'][3]['output']['warning']

def test_llm_receives_full_context(client, monkeypatch):
    import sys, types
    prompts=[]
    module=types.ModuleType('llm')
    module.explain=lambda prompt: prompts.append(prompt) or '{"summary":"Advisory explanation","changes":[]}'
    monkeypatch.setitem(sys.modules,'llm',module)
    sample=client.get('/api/samples').json()[2]
    response=client.post('/api/runs',json={**{k:sample[k] for k in ('filename','before','after')},'use_ai':True,'business_context':'Removal must occur seven days after term start.'})
    result=client.get('/api/runs/'+response.json()['id']).json()
    import json
    context=json.loads(prompts[0].split('SOURCE DATA:\n',1)[1])
    assert context['before']==sample['before']
    assert context['after']==sample['after']
    assert 'seven days' in context['business_context']
    assert 'PAY-001' in context['approved_rules']
    assert result['nodes'][3]['output']['mode']=='llm-advisory'
    assert not result['nodes'][3]['output']['context']['before']['truncated']

def test_context_limits_and_safe_config(client, monkeypatch):
    _,metadata=main.llm_context({'filename':'x.sql','before':'x'*13000,'after':'','business_context':''}, [], '')
    assert metadata['before']['truncated']
    assert metadata['before']['sent_chars']==12000
    monkeypatch.setenv('GROQ_API_KEY','secret-test-value')
    monkeypatch.setenv('LLM_PROVIDER','groq')
    config=client.get('/api/llm-config')
    assert config.json()['groq_key_configured']
    assert 'secret-test-value' not in config.text

def test_execution_events_preserve_fast_transitions(client):
    result=run(client,client.get('/api/samples').json()[0])
    events=result['events']
    assert [(e['node'],e['status']) for e in events]==[(0,'running'),(0,'completed'),(1,'running'),(1,'completed'),(2,'running'),(2,'completed'),(3,'running'),(3,'completed'),(4,'awaiting_review')]
    assert all(e['timestamp'] and e['message'] for e in events)
    decided=client.post('/api/runs/'+result['id']+'/decision',json={'decision':'approved','reviewer':'Owner','comments':'Reviewed'}).json()
    assert decided['events'][-1]['message']=='Decision saved'

def test_api_responses_are_not_cached(client):
    response=client.get('/api/health')
    assert response.headers['cache-control']=='no-store'

def approve(client, result, ids, decision='approved'):
    return client.post('/api/runs/'+result['id']+'/decision',json={'decision':decision,'reviewer':'Business owner','comments':'Verified evidence and boundary tests','selected_rule_ids':ids})

def test_selected_rule_saved_and_version_archived(client):
    result=run(client,client.get('/api/samples').json()[2])
    assert result['rule_proposals'][0]['action']=='create'
    response=approve(client,result,['TERM-REMOVAL'])
    assert response.status_code==200
    path=main.RULE_ROOT/'approved/TERM-REMOVAL.md'
    assert 'INT = 7' in path.read_text()
    assert result['id'] in path.read_text()
    assert response.json()['decision']['saved_files']==['rules/approved/TERM-REMOVAL.md']
    previous=path.read_text()
    sample=client.get('/api/samples').json()[2]
    sample['before']=sample['after']
    sample['after']=sample['after'].replace('INT = 7','INT = 6')
    result2=run(client,sample)
    assert approve(client,result2,['TERM-REMOVAL']).status_code==200
    assert (main.RULE_ROOT/f'archived/{result2["id"]}/TERM-REMOVAL.previous.md').read_text()==previous
    assert 'INT = 6' in path.read_text()

def test_removal_requires_explicit_selection_and_archives(client):
    result=run(client,client.get('/api/samples').json()[0])
    path=main.RULE_ROOT/'approved/PAY-001.md'
    original=path.read_text()
    assert approve(client,result,[]).status_code==200
    assert path.read_text()==original
    result=run(client,client.get('/api/samples').json()[0])
    assert approve(client,result,['PAY-001'],'rejected').status_code==422
    assert approve(client,result,['PAY-001']).status_code==200
    assert not path.exists()
    archive=main.RULE_ROOT/f'archived/{result["id"]}'
    assert (archive/'PAY-001.previous.md').read_text()==original
    assert 'status: retired' in (archive/'PAY-001.retired.md').read_text()

def test_stale_unknown_rejected_and_write_failure(client, monkeypatch):
    result=run(client,client.get('/api/samples').json()[2])
    assert approve(client,result,['UNKNOWN']).status_code==422
    assert approve(client,result,[],'rejected').status_code==200
    assert not (main.RULE_ROOT/'approved/TERM-REMOVAL.md').exists()
    result=run(client,client.get('/api/samples').json()[2])
    path=main.RULE_ROOT/'approved/TERM-REMOVAL.md'
    path.write_text('Other reviewer updated this rule')
    assert approve(client,result,['TERM-REMOVAL']).status_code==409
    assert path.read_text()=='Other reviewer updated this rule'
    path.unlink()
    result=run(client,client.get('/api/samples').json()[2])
    original=main.rule_store.atomic_write
    def fail(path,content):
        if path.name=='TERM-REMOVAL.md': raise PermissionError('read-only folder')
        return original(path,content)
    monkeypatch.setattr(main.rule_store,'atomic_write',fail)
    assert approve(client,result,['TERM-REMOVAL']).status_code==503
    assert client.get('/api/runs/'+result['id']).json()['status']=='awaiting_review'
    assert not path.exists()

def test_selective_approval_does_not_save_other_proposals(client):
    sample=client.get('/api/samples').json()[0]
    sample['after']=sample['before']
    sample['before']='// Original empty implementation'
    result=run(client,sample)
    assert len(result['rule_proposals'])==2
    existing=(main.RULE_ROOT/'approved/PAY-001.md').read_text()
    assert approve(client,result,['PAY-002']).status_code==200
    assert (main.RULE_ROOT/'approved/PAY-002.md').exists()
    assert (main.RULE_ROOT/'approved/PAY-001.md').read_text()==existing

def test_db_failure_restores_rule_files(client,monkeypatch):
    result=run(client,client.get('/api/samples').json()[2])
    def fail(_): raise RuntimeError('database unavailable')
    monkeypatch.setattr(main,'save',fail)
    with pytest.raises(RuntimeError,match='database unavailable'):
        approve(client,result,['TERM-REMOVAL'])
    assert not (main.RULE_ROOT/'approved/TERM-REMOVAL.md').exists()
    assert main.get(result['id'])['status']=='awaiting_review'

def test_arbitrary_uploaded_sql_compared_by_llm(client, monkeypatch):
    import sys, types, json
    before='SELECT * FROM Orders WHERE Total > 500;'
    after='SELECT * FROM Orders WHERE Total > 1000;'
    module=types.ModuleType('llm')
    captured=[]
    def compare(prompt):
        captured.append(prompt)
        return json.dumps({'summary':'Threshold raised from 500 to 1000; test the boundary.', 'changes':[{'kind':'modified','title':'Order threshold','description':'Orders must now exceed 1000 rather than 500.','before_evidence':'Total > 500','after_evidence':'Total > 1000'}]})
    module.explain=compare
    monkeypatch.setitem(sys.modules,'llm',module)
    response=client.post('/api/runs',json={'filename':'UploadedOrders.sql','before':before,'after':after,'use_ai':True})
    result=client.get('/api/runs/'+response.json()['id']).json()
    output=result['nodes'][2]['output']
    assert output['changes']==[]
    assert output['ai_changes'][0]['before_evidence']=='Total > 500'
    assert output['ai_changes'][0]['after_line']==1
    assert output['ai_comparison_status']=='llm-advisory'
    assert before in captured[0] and after in captured[0]
    assert 'Threshold raised' in result['nodes'][3]['output']['explanation']
    assert result['rule_proposals']==[]  # Advisory findings never silently become approved rules.

def test_ai_comparison_rejects_invented_and_unchanged_evidence():
    import json
    from backend.ai_compare import validate
    raw=json.dumps({'summary':'Review required', 'changes':[
        {'kind':'modified','title':'Invented','description':'x','before_evidence':'Total > 1','after_evidence':'Total > 2'},
        {'kind':'modified','title':'Unchanged','description':'x','before_evidence':'SELECT','after_evidence':'FROM'}]})
    result=validate(raw,'SELECT * FROM Orders WHERE Total > 500','SELECT * FROM Orders WHERE Total > 1000')
    assert not result['changes']
    assert result['rejected_findings']==2

def test_invalid_llm_response_is_not_reported_as_success(client,monkeypatch):
    import sys,types
    module=types.ModuleType('llm');module.explain=lambda _: 'Unstructured answer'
    monkeypatch.setitem(sys.modules,'llm',module)
    response=client.post('/api/runs',json={'filename':'x.sql','before':'SELECT 1','after':'SELECT 2','use_ai':True})
    result=client.get('/api/runs/'+response.json()['id']).json()
    assert result['nodes'][2]['output']['warning']
    assert result['nodes'][2]['output']['ai_comparison_status']=='deterministic'

def test_builtin_scenarios_independent_of_editable_pr_samples(client, tmp_path, monkeypatch):
    # Reproduce the demo PR: remove PAY-001 from the editable source.
    checkout=tmp_path/'checkout'
    sample_dir=checkout/'samples'
    sample_dir.mkdir(parents=True)
    (sample_dir/'PaymentService.cs').write_text('public class PaymentService {}')
    (sample_dir/'CapturePayment.sql').write_text('-- editable SQL guard removed')
    monkeypatch.setattr(main,'ROOT',checkout)
    samples=client.get('/api/samples').json()
    assert 'amount <= 0' in samples[0]['before']
    assert 'amount <= 0' not in samples[0]['after']
    result=run(client,samples[0])
    assert any(c['id']=='PAY-001' and c['kind']=='removed' for c in result['nodes'][2]['output']['changes'])
    result=run(client,samples[1])
    assert any(c['id']=='PAY-003' and c['kind']=='removed' for c in result['nodes'][2]['output']['changes'])
    # The approval guard continues checking the editable file, not UI constants.
    from approval import findings
    import shutil
    shutil.copytree(main.RULE_ROOT/'approved',checkout/'rules/approved')
    assert any(item['id']=='PAY-001' for item in findings(checkout))
