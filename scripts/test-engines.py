#!/usr/bin/env python3
"""Real engineering work through a freshly installed kernel, signed in as its first owner."""
import argparse
import base64
import hashlib
import json
import subprocess
import time
import urllib.error
import urllib.request
import urllib.parse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='http://127.0.0.1:38812')
    parser.add_argument('--password-file', required=True)
    parser.add_argument('--container', help='test-owned kernel container, for checking the managed slicer output without a real printer')
    parser.add_argument('--plant-spec', required=True)
    parser.add_argument('--plant-task', required=True)
    parser.add_argument('--receipt-file', help='write non-secret completed-report/engine evidence')
    parser.add_argument('--recover-receipt', help='verify cached/lasting recovery after Docker restart; mirror must be unavailable')
    parser.add_argument('--expect-unused', action='store_true', help='assert catalog listing prepared no unused engine')
    parser.add_argument('--train-steps', type=int, default=2048)
    args = parser.parse_args()
    endpoint = urllib.parse.urlsplit(args.base)
    assert endpoint.scheme == 'http' and endpoint.hostname in ('127.0.0.1', 'localhost', '::1') and endpoint.port not in (38788, 8787), 'engine acceptance requires a disposable loopback kernel'
    session = None

    def call(method, path, body=None, binary=False, allow_preparing=False):
        headers = {'content-type': 'application/json'}
        if session:
            headers['authorization'] = 'Bearer ' + session
        request = urllib.request.Request(args.base + path, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        result = raw if binary else json.loads(raw)
        assert 200 <= status < 300 or (allow_preparing and status == 503), (path, status, str(result)[:600])
        return result

    def wait_image(app, probe):
        until = time.monotonic() + 600
        while True:
            call('GET', probe, allow_preparing=True)
            listing = call('GET', '/api/applications')
            applications = listing if isinstance(listing, list) else listing['applications']
            row = next(row for row in applications if row['name'] == app)
            engine = row.get('engine') or {}
            assert engine.get('state') != 'failed', engine
            if engine.get('state') in ('ready', 'running'):
                return
            assert time.monotonic() < until, (app, engine)
            time.sleep(1)

    session = call('POST', '/sessions', {'username': 'admin', 'password': Path(args.password_file).read_text().strip()})['session']
    if args.recover_receipt:
        before = json.loads(Path(args.recover_receipt).read_text())
        wait_image('embodied', '/api/embodied/physics/status')
        reports = call('GET', '/api/embodied/physics/reports')['reports']
        preserved = next(row['report'] for row in reports if row['file'] == before['reportFile'])
        digest = hashlib.sha256(json.dumps(preserved, sort_keys=True).encode()).hexdigest()
        assert digest == before['reportSha256'], 'completed report changed across Docker restart'
        record = json.loads(subprocess.check_output(['docker', 'exec', args.container, 'cat', '/var/lib/oshal/engines/run/embodied/run.json'], text=True))
        assert (record['pid'], record['started']) != (before['engineRecord']['pid'], before['engineRecord']['started']), 'Docker restart must create a new engine process'
        print('ok: Docker restart reloaded the cached engine with the mirror unavailable; completed report bytes survived; engine process was replaced', flush=True)
        return
    rows = call('GET', '/api/applications')
    rows = rows if isinstance(rows, list) else rows['applications']
    engineering = {'design-studio', 'cad-studio', 'circuit-lab', 'embodied', 'aero-lab', 'scan-to-print'}
    assert all(row.get('authorized') for row in rows if row['name'] in engineering), 'the selected owner cannot open the engineering chain'
    assert engineering.issubset({row['name'] for row in rows}), 'selected engineering package missing from the catalog'
    if args.expect_unused:
        authority = call('GET', '/api/authorization/composites')
        held = [row['assignment'] for row in authority['assignments'] if row['status'] == 'active']
        assert {row['selection']['app'] for row in held} == engineering, 'installer assigned an unselected application or omitted a selection'
        assert all(row['target']['id'] == authority['caller']['id'] for row in held), 'installer changed another person'
        until = time.monotonic() + 45
        observed_since = None
        while True:
            states = [(row.get('engine') or {}).get('state') for row in rows if row['name'] in engineering - {'design-studio'}]
            assert not any(state in ('preparing', 'running', 'ready', 'failed') for state in states), 'listing the catalog prepared an unused engine'
            if all(state == 'not-prepared' for state in states):
                observed_since = observed_since or time.monotonic()
                # Default supervision ticks every ten seconds: cross two ticks before any probe.
                if time.monotonic() - observed_since >= 21:
                    break
            else:
                observed_since = None
            assert time.monotonic() < until, 'unused engine status did not become visible'
            time.sleep(1)
            listing = call('GET', '/api/applications')
            rows = listing if isinstance(listing, list) else listing['applications']
        print('ok: repeated catalog reads downloaded no unused engine', flush=True)
    wait_image('cad-studio', '/api/cad-studio/capabilities')
    cad = call('POST', '/api/cad-studio/models', {'title': 'Installer acceptance block', 'base': {'kind': 'box', 'sizeX': 20, 'sizeY': 20, 'sizeZ': 20}, 'features': []})
    assert cad['build']['ok'] and cad['model']['report']['valid'], cad
    stl = call('GET', cad['model']['artifacts']['stl'], binary=True)
    assert len(stl) > 84, 'CAD produced no real STL'
    print('ok: CAD built a valid solid and exported its STL', flush=True)
    wait_image('circuit-lab', '/api/circuit-lab/capabilities')
    circuit = call('POST', '/api/circuit-lab/designs', {'example': 'rc-charge', 'title': 'Installer acceptance RC'})
    assert circuit['build']['ok'] and circuit['design']['report']['readings'], circuit
    print('ok: Circuit solved the RC example with real readings', flush=True)
    wait_image('aero-lab', '/api/aero-lab/capabilities')
    aero = call('POST', '/api/aero-lab/evaluate', {'design': {}})
    assert 'build' in aero and 'energy' in aero, aero
    print('ok: Aero evaluated the default design with real mass and energy results', flush=True)
    wait_image('scan-to-print', '/api/scan-to-print/printers/profiles')
    profiles = call('GET', '/api/scan-to-print/printers/profiles')
    assert profiles['engine']['ready'] and profiles['printers'], profiles
    print('ok: Scan to Print read real slicer profiles as the owner', flush=True)
    if args.container:
        # A test-side inspection of the engine the authenticated profile request started.
        # No printer is registered, uploaded to, or started by this proof.
        script = '''import sys,json,socket,base64,zipfile,io
s=socket.socket(socket.AF_UNIX);s.settimeout(180);s.connect('/var/lib/oshal/engines/run/scan-to-print/link.sock')
f=s.makefile('rwb');hello=json.loads(f.readline());request=json.load(sys.stdin)
f.write((json.dumps(request)+'\\n').encode());f.flush();reply=json.loads(f.readline());assert reply.get('ok'),reply
result=reply['result'];archive=base64.b64decode(result['archive']);z=zipfile.ZipFile(io.BytesIO(archive))
assert any(n.endswith('.gcode') for n in z.namelist()),z.namelist()
print(json.dumps({'bytes':len(archive),'gcodeFiles':sum(n.endswith('.gcode') for n in z.namelist()),'profile':result['profile']}))
'''
        request = {'id': 'installer-slice', 'cmd': 'slice', 'args': {'stl': base64.b64encode(stl).decode(), 'name': 'installer-cube', 'modelId': 'N7', 'nozzle': '0.4', 'filament': 'Bambu PLA Basic', 'plate': 'Textured PEI Plate'}}
        sliced = subprocess.run(['docker', 'exec', '-i', args.container, 'python3', '-c', script], input=json.dumps(request), text=True, capture_output=True, timeout=240, check=True)
        print('ok: managed slicer produced a printer archive (test socket inspection): ' + sliced.stdout.strip(), flush=True)
    wait_image('embodied', '/api/embodied/physics/status')
    payload = {'project': 'installer-acceptance-lift', 'spec': json.loads(Path(args.plant_spec).read_text()), 'task': json.loads(Path(args.plant_task).read_text()), 'timesteps': 0, 'seed': 73}
    baseline = call('POST', '/api/embodied/physics/plant/train', payload)
    assert baseline['report']['baseline']['episodes'] == 5, baseline
    print('ok: Embodied ran five real baseline episodes', flush=True)
    payload['timesteps'] = args.train_steps
    training = call('POST', '/api/embodied/physics/plant/train', payload)
    assert training['started'], training
    until = time.monotonic() + 600
    while True:
        jobs = call('GET', '/api/embodied/physics/plant/train')['jobs']
        job = next(row for row in jobs if row['project'] == payload['project'] and row['seed'] == payload['seed'])
        assert not job.get('error'), job
        if job['state'] == 'done':
            break
        assert time.monotonic() < until, job
        time.sleep(1)
    certificate = call('POST', '/api/embodied/physics/plant/certify', {'file': job['file'], 'seeds': [31, 32]})
    assert certificate['certification']['buildHash'] and certificate['certification']['specSha256'], certificate
    print('ok: short training completed and the real certification gate ran; verdict ' + json.dumps(certificate['certification']['verdict']), flush=True)
    if args.receipt_file:
        reports = call('GET', '/api/embodied/physics/reports')['reports']
        report = next(row['report'] for row in reports if row['file'] == job['file'])
        record = json.loads(subprocess.check_output(['docker', 'exec', args.container, 'cat', '/var/lib/oshal/engines/run/embodied/run.json'], text=True))
        Path(args.receipt_file).write_text(json.dumps({'reportFile': job['file'], 'reportSha256': hashlib.sha256(json.dumps(report, sort_keys=True).encode()).hexdigest(), 'engineRecord': record}) + '\n')
    print('ALL ENGINE CHECKS PASSED (training quality is reported separately)', flush=True)


if __name__ == '__main__':
    main()
