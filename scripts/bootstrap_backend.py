#!/usr/bin/env python3
"""Create local Mock configuration once; never display or overwrite credentials."""
from pathlib import Path
import secrets
path = Path(__file__).resolve().parents[1] / 'backend' / '.env'
if path.exists():
    print('backend/.env already exists; left unchanged')
else:
    path.write_text('PROVIDER=mock\nSERVICE_TOKEN=' + secrets.token_urlsafe(32) + '\nOPENAI_API_KEY=\nOPENAI_MODEL=gpt-4.1-mini\n')
    path.chmod(0o600)
    print('Created ignored backend/.env (Mock mode). Copy SERVICE_TOKEN locally into iPhone service settings.')
