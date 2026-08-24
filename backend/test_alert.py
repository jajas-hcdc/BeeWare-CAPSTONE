import json
import urllib.request

url = 'http://127.0.0.1:8000/alerts'
data = {
    'hive_id': 'hive-1',
    'queen_status': 'Queen Absent',
    'title': 'Test Queen Alert',
    'message': 'This is a test alert from the FastAPI backend.',
    'additional_data': {'source': 'backend_test'},
}

req = urllib.request.Request(
    url,
    data=json.dumps(data).encode('utf-8'),
    headers={'Content-Type': 'application/json'},
)

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        print('STATUS', resp.status)
        print(resp.read().decode('utf-8'))
except Exception as exc:
    print('ERROR', exc)
