"""Fresh Linux Kubernetes acceptance through the actual npm tarball; owns one kind cluster."""
from pathlib import Path
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def main():
    os.umask(0o077)
    work = Path(tempfile.mkdtemp(prefix='oswarm-k8s-proof-'))
    directory = work/'installation'
    output = Path(os.environ.get('OSWARM_PROOF_OUTPUT', str(work/'receipt.json')))
    password = secrets.token_urlsafe(24)
    port = int(os.environ.get('TEST_PORT', '38992'))
    env = dict(os.environ, OSWARM_K8S_DIR=str(directory), OSWARM_ADMIN_PASSWORD=password,
               OSWARM_NO_BROWSER='1', OSWARM_NO_FORWARD='1', OSWARM_PORT=str(port), OSWARM_EDITOR_PORT=str(port+1))
    receipt = {'scope':'actual npm package, fresh owned kind cluster on Linux Docker Engine; Windows remains separate acceptance', 'checks':[], 'status':'running'}
    raw_log = []
    forward = None
    def save():
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt,indent=2)+'\n')
        output.with_suffix('.log').write_text('\n'.join(raw_log))
    def checked(command, timeout=900, quiet=False):
        result = subprocess.run(command,env=env,text=True,capture_output=True,timeout=timeout,cwd=work)
        message = (result.stdout+'\n'+result.stderr).replace(password,'[private fixture password]')
        raw_log.append(message)
        if not quiet:print(message,flush=True)
        if result.returncode: raise AssertionError(message[-6000:])
        return result.stdout
    def kube(*args):
        return checked([str(directory/'bin/kubectl'),'--kubeconfig',str(directory/'kubeconfig'),'--context','kind-'+state['cluster'],'-n','oshal-swarm',*args],timeout=360,quiet=True)
    def start_forward():
        nonlocal forward
        forward = subprocess.Popen([str(directory/'bin/kubectl'),'--kubeconfig',str(directory/'kubeconfig'),'--context','kind-'+state['cluster'],'-n','oshal-swarm','port-forward','--address','127.0.0.1','service/oshal-kernel-service',str(port)+':38788'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        for _ in range(90):
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{port}/readyz',timeout=3) as response:
                    if json.load(response)['readiness']=='ready': return
            except (OSError,ValueError): pass
            time.sleep(1)
        raise AssertionError('Loopback readiness did not succeed')
    def stop_forward():
        nonlocal forward
        if forward:
            forward.terminate()
            try:forward.wait(timeout=10)
            except subprocess.TimeoutExpired:forward.kill();forward.wait(timeout=5)
            forward=None
    def signin(value):
        request=urllib.request.Request(f'http://127.0.0.1:{port}/sessions',data=json.dumps({'username':'admin','password':value}).encode(),headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=10) as response:
                if value==password:
                    cookie=response.headers['Set-Cookie'].split(';')[0]
                    catalog_request=urllib.request.Request(f'http://127.0.0.1:{port}/api/swarm/apps/catalog',headers={'Cookie':cookie})
                    with urllib.request.urlopen(catalog_request,timeout=10) as catalog_response:catalog=json.load(catalog_response)
                    assert catalog['source']=='marketplace-files' and catalog['total']>=50
                    receipt['catalogVisibleInAppLoader']=catalog['total']
                return response.status
        except urllib.error.HTTPError as error:return error.code
    state=None
    try:
        packed=json.loads(subprocess.check_output(['npm','pack','--json','--pack-destination',str(work)],cwd=ROOT,text=True))[0]
        archive=work/packed['filename']
        receipt['packageSha256']=hashlib.sha256(archive.read_bytes()).hexdigest()
        with tarfile.open(archive) as bundle:bundle.extractall(work,filter='data')
        entry=str(work/'package/bin/oshal-swarm.cjs')
        command=lambda action:checked(['node',entry,'kubernetes',action])
        before=subprocess.check_output(['docker','ps','-aq'],text=True).split()
        command('install')
        state=json.loads((directory/'state.json').read_text())
        receipt.update(cluster=state['cluster'],clusterUid=state['clusterUid'],imageId=state['imageId'],revision=state['revision'],apparmor=state['apparmor'])
        receipt['checks'].append('fresh tarball installs cluster, sandbox, database, administrator, editor and catalog')
        manager=directory/'oswarm-kubernetes.sh'
        assert manager.is_file() and (directory/'installer/kubernetes/installer.cjs').is_file()
        # npm's temporary package cache is now absent. All later actions must
        # execute the persistent manager that setup left for the end user.
        shutil.rmtree(work/'package')
        command=lambda action:checked(['bash',str(manager),action])
        command('status')
        receipt['checks'].append('persistent management launcher works after the temporary npm package is removed')
        assert (directory/'state.json').stat().st_mode & 0o777 == 0o600
        receipt['checks'].append('private credentials mode 0600')
        start_forward()
        with urllib.request.urlopen(f'http://127.0.0.1:{port}/version',timeout=5) as response:assert json.load(response)['commit']==state['revision']
        assert signin(password)==201 and signin('wrong-password-fixture-123')!=201
        receipt['checks'].append('ready, exact image source revision and administrator sign-in; wrong password refused')
        count=int(kube('exec','deployment/oshal-kernel-deployment','--','sh','-c','find /opt/oshal/applications -maxdepth 2 -name oshal-app.yaml | wc -l').strip())
        assert count>=50
        receipt['catalogApplications']=count
        kube('exec','deployment/oshal-kernel-deployment','--','sh','-c','printf retained > /var/lib/oshal/installer-proof.txt')
        stop_forward();command('stop')
        deployments=json.loads(kube('get','deployments','-o','json'))
        assert all(item['spec']['replicas']==0 for item in deployments['items'] if item['metadata']['name'] in ['oshal-kernel-deployment','code-server'])
        for name in ['oshal-kernel','code-server']:
            assert not json.loads(kube('get','pods','-l','app.kubernetes.io/name='+name,'-o','json'))['items']
        command('start');start_forward();assert signin(password)==201
        stop_forward();command('restart');start_forward();assert signin(password)==201
        assert kube('exec','deployment/oshal-kernel-deployment','--','cat','/var/lib/oshal/installer-proof.txt').strip()=='retained'
        receipt['checks'].append('stop/start/restart preserve administrator and durable state')
        stop_forward();command('install');start_forward();assert signin(password)==201
        assert json.loads((directory/'state.json').read_text())['clusterUid']==state['clusterUid']
        receipt['checks'].append('rerun retains cluster, password and data')
        stop_forward();checked(['bash',str(manager),'uninstall','--purge'])
        remaining=subprocess.check_output(['docker','ps','-aq','--filter','label=io.x-k8s.kind.cluster='+state['cluster']],text=True).strip()
        assert not remaining
        assert all(subprocess.run(['docker','inspect',item],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0 for item in before)
        receipt['checks'].append('owned cluster removed; pre-existing containers retained')
        receipt['status']='passed'
    except Exception as error:
        receipt['status']='failed';receipt['error']=str(error).replace(password,'[private fixture password]');raise
    finally:
        stop_forward()
        state_file=directory/'state.json'
        if state_file.exists():
            current=json.loads(state_file.read_text())
            if current.get('phase')!='removed' and (directory/'bin/kind').exists():
                nodes=subprocess.run(['docker','ps','-aq','--filter','label=io.x-k8s.kind.cluster='+current['cluster']],capture_output=True,text=True).stdout.strip()
                if nodes:
                    cleanup=subprocess.run([str(directory/'bin/kind'),'delete','cluster','--name',current['cluster'],'--kubeconfig',str(directory/'kubeconfig')],capture_output=True,text=True,timeout=180)
                    receipt['failureCleanup']=cleanup.returncode==0
        save();print(json.dumps(receipt,indent=2),flush=True)
        shutil.rmtree(work)
    return receipt

if __name__=='__main__':main()
