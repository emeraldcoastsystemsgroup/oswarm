"""Real PowerShell/Compose acceptance on Linux; explicitly not Windows Desktop proof."""
from pathlib import Path
import json, os, re, secrets, shutil, subprocess, tempfile, urllib.request

ROOT = Path(__file__).resolve().parents[1]
PWSH = os.environ.get('PWSH') or shutil.which('pwsh')
IMAGE = os.environ.get('OSWARM_IMAGE', '')  # empty: the release path pulls the pinned image
PORT = int(os.environ.get('TEST_PORT', '38996'))

def main():
    if not PWSH: raise SystemExit('Set PWSH to an installed PowerShell executable, or put pwsh on PATH.')
    os.umask(0o077)
    root = Path(tempfile.mkdtemp(prefix='oswarm-powershell-'))
    directory = root / 'installation'
    project = 'oswarm-ps-proof-' + secrets.token_hex(4)
    password = secrets.token_urlsafe(24)
    env = dict(os.environ, OSWARM_DIR=str(directory), OSWARM_PORT=str(PORT),
               OSWARM_PROJECT=project, OSWARM_ADMIN_PASSWORD=password, OSWARM_NO_BROWSER='1')
    env.pop('OSWARM_IMAGE', None)
    if IMAGE: env['OSWARM_IMAGE'] = IMAGE
    checks = []
    def run(action='install'):
        file = ROOT/'install/install.ps1' if action == 'install' else directory/'oswarm.ps1'
        result = subprocess.run([PWSH,'-NoLogo','-NoProfile','-NonInteractive','-File',str(file),'-Action',action,'-Dir',str(directory),'-Port',str(PORT)],env=env,text=True,capture_output=True,timeout=360)
        if result.returncode:
            message = (result.stdout+'\n'+result.stderr).replace(password,'[private fixture password]')
            raise AssertionError(message[-6000:])
        return result.stdout
    def signin():
        body=json.dumps({'username':'admin','password':password}).encode()
        request=urllib.request.Request(f'http://127.0.0.1:{PORT}/sessions',data=body,headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=5) as response: assert response.status==201
    try:
        run();checks.append('fresh PowerShell install with Docker Engine on Linux')
        signin();checks.append('administrator password signs in')
        assert (directory/'applications/native-source-origin.json').is_file();checks.append('catalog staged')
        subprocess.run(['docker','compose','exec','-T','kernel','sh','-c','test -r /opt/oshal/applications/native-source-origin.json'],cwd=directory,env=env,check=True,capture_output=True)
        checks.append('non-root kernel can read staged catalog')
        run('stop');run('start');run('restart');signin();checks.append('stop/start/restart preserve administrator')
        run();signin();checks.append('rerun preserves existing installation')
        print(json.dumps({'status':'passed','scope':'PowerShell 7 on Linux with real Docker Engine; Windows hardware and Windows PowerShell 5.1 remain separate acceptance','checks':checks},indent=2))
    finally:
        if (directory/'compose.yaml').exists():subprocess.run(['docker','compose','down','--volumes','--remove-orphans'],cwd=directory,env=env,capture_output=True,timeout=90)
        shutil.rmtree(root)

if __name__ == '__main__':main()
