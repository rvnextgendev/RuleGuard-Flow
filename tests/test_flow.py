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
