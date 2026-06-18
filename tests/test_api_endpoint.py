#!/usr/bin/env python
"""Test the /api/environment/validate endpoint."""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from app import app

client = TestClient(app)
response = client.get('/api/environment/validate')

with open('api_response.txt', 'w') as f:
    f.write(f'Status: {response.status_code}\n')
    import json
    f.write('Response:\n')
    f.write(json.dumps(response.json(), indent=2))

print("API response written to api_response.txt")

