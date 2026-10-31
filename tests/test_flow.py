from fastapi.testclient import TestClient
from backend import main
import pytest

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, 'DB', tmp_path / 'runs.db')
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
    module.explain=lambda prompt: prompts.append(prompt) or 'Advisory explanation'
    monkeypatch.setitem(sys.modules,'llm',module)
    sample=client.get('/api/samples').json()[2]
    response=client.post('/api/runs',json={**{k:sample[k] for k in ('filename','before','after')},'use_ai':True,'business_context':'Removal must occur seven days after term start.'})
    result=client.get('/api/runs/'+response.json()['id']).json()
    import json
    context=json.loads(prompts[0].split('\n',1)[1])
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
