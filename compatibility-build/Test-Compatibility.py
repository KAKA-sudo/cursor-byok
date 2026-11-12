"""Exercise installer compatibility changes against isolated synthetic profiles."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile

root = Path(__file__).resolve().parent
test_root = (root / 'tests').resolve()
test_root.mkdir(exist_ok=True)
fixture_root = Path(tempfile.mkdtemp(prefix='compat-', dir=test_root)).resolve()
assert fixture_root.parent == test_root
powershell = Path(os.environ['WINDIR']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
script = root / 'Apply-Compatibility.ps1'
name = 'agent_host_local_loop'
hash31 = 0
for char in name:
    hash31 = (hash31 * 31 + ord(char)) & 0xffffffff
keys = {
    'none': name,
    'djb2': str(hash31),
    'sha256': base64.b64encode(hashlib.sha256(name.encode()).digest()).decode(),
}


def apply(profile):
    subprocess.run([str(powershell), '-NoProfile', '-NonInteractive', '-ExecutionPolicy',
                    'RemoteSigned', '-File', str(script), '-ProfileRoot', str(profile)], check=True)


try:
    for mode, key in keys.items():
        profile = fixture_root / mode
        user = profile / 'AppData/Roaming/Cursor/User'
        (user / 'globalStorage').mkdir(parents=True)
        settings = '// preserve comment\n{"cursor.general.disableHttp1SSE": true, "other": 123}\n'
        (user / 'settings.json').write_text(settings, encoding='utf-8')
        cache = {'hash_used': mode, 'feature_gates': {
            key: {'value': True}, 'unrelated': {'value': True}},
            'dynamic_configs': {'sample': [1, {'two': 2}]}}
        original = json.dumps(cache)
        state = user / 'globalStorage/state.vscdb'
        with sqlite3.connect(state) as db:
            db.execute('CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)')
            db.execute('INSERT INTO ItemTable VALUES (?,?)', ('workbench.experiments.statsigBootstrap', original))
            db.execute('INSERT INTO ItemTable VALUES (?,?)', ('unrelated-row', 'preserved'))
        db.close()
        apply(profile)
        with sqlite3.connect(state) as db:
            result = json.loads(db.execute("SELECT value FROM ItemTable WHERE key='workbench.experiments.statsigBootstrap'").fetchone()[0])
            assert result['feature_gates'][key]['value'] is False
            assert result['feature_gates']['unrelated']['value'] is True
            assert result['dynamic_configs'] == cache['dynamic_configs']
            assert db.execute("SELECT value FROM ItemTable WHERE key='unrelated-row'").fetchone()[0] == 'preserved'
            assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        db.close()
        updated = (user / 'settings.json').read_text(encoding='utf-8')
        assert updated == settings.replace('"cursor.general.disableHttp1SSE": true', '"cursor.general.disableHttp1SSE": false')
        backups = list(profile.glob('AppData/Local/Cursor BYOK Repair/installer-backups/*'))
        assert len(backups) == 1
        assert (backups[0] / 'cursor-statsig-bootstrap-original.json').read_text(encoding='utf-8') == original
        assert (backups[0] / 'cursor-settings-original.json').read_text(encoding='utf-8') == settings
        apply(profile)
        assert len(list(profile.glob('AppData/Local/Cursor BYOK Repair/installer-backups/*'))) == 1
        print('PASS:', mode, 'gate, settings, backups, unrelated data, integrity, idempotency')
    apply(fixture_root / 'fresh-profile')
    assert not (fixture_root / 'fresh-profile').exists()
    print('PASS: fresh profile requires no cache or external runtime')
finally:
    assert fixture_root.resolve().parent == test_root
    shutil.rmtree(fixture_root)
