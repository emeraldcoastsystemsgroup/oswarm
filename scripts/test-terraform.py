"""Terraform acceptance: the module in terraform/ against a fresh, owned kind cluster.

  TERRAFORM=/path/to/terraform python3 scripts/test-terraform.py

It downloads the kind and kubectl the Kubernetes installer pins, creates one cluster with its own
kubeconfig (the current kubectl context is never read or changed), prepares the node the way a
cluster operator must (install/kubernetes/README.md: seccomp file, AppArmor profile, node label),
then runs terraform apply with the release defaults: the published image pulled by digest, an
in-cluster PostgreSQL, and the administrator and catalog init steps. It proves readiness, the image's
source revision, sign-in with the module's generated password, the staged catalog in the App
Loader, a second plan with no changes, and terraform destroy, then deletes the cluster.
Set OSWARM_TEST_REGISTRY_AUTH=1 to hand the node this machine's ghcr.io login while the image is
private; the receipt records it.
"""
from pathlib import Path
import base64, hashlib, json, os, secrets, shutil, subprocess, tempfile, time, urllib.error, urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / 'install/kubernetes/tools.lock.json').read_text())
TERRAFORM = os.environ.get('TERRAFORM') or shutil.which('terraform') or shutil.which('tofu')
PORT = int(os.environ.get('TEST_PORT', '38994'))


def platform():
    machine = os.uname().machine
    return 'linux-' + {'x86_64': 'amd64', 'aarch64': 'arm64', 'arm64': 'arm64'}[machine]


def fetch(url, digest, target):
    with urllib.request.urlopen(url, timeout=300) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise AssertionError(f'checksum mismatch for {url}')
    target.write_bytes(data)
    target.chmod(0o700)


def main():
    if not TERRAFORM:
        raise SystemExit('Set TERRAFORM to a Terraform (or OpenTofu) executable, or put terraform on PATH.')
    os.umask(0o077)
    work = Path(tempfile.mkdtemp(prefix='oswarm-terraform-proof-'))
    cluster = 'oswarm-tf-' + secrets.token_hex(4)
    kubeconfig = work / 'kubeconfig'
    context = 'kind-' + cluster
    password = secrets.token_urlsafe(24)
    output = Path(os.environ.get('OSWARM_PROOF_OUTPUT', str(work / 'receipt.json')))
    receipt = {'scope': 'terraform/ module, fresh owned kind cluster on Linux Docker Engine', 'cluster': cluster, 'checks': [], 'status': 'running'}
    env = dict(os.environ, TF_IN_AUTOMATION='1', TF_INPUT='0', KUBECONFIG=str(kubeconfig))
    module = work / 'module'
    forward = None

    def run(command, timeout=900, quiet=False):
        result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=timeout, cwd=module if module.exists() else work)
        message = (result.stdout + '\n' + result.stderr).replace(password, '[private fixture password]')
        if not quiet:
            print(message[-4000:], flush=True)
        if result.returncode:
            raise AssertionError(message[-6000:])
        return result.stdout

    bin_dir = work / 'bin'
    bin_dir.mkdir()
    kind, kubectl = bin_dir / 'kind', bin_dir / 'kubectl'
    node = cluster + '-control-plane'

    def kube(*args, **kw):
        return run([str(kubectl), '--kubeconfig', str(kubeconfig), '--context', context, *args], timeout=360, quiet=True, **kw)

    def start_forward():
        nonlocal forward
        forward = subprocess.Popen([str(kubectl), '--kubeconfig', str(kubeconfig), '--context', context, '-n', 'oshal-kernel', 'port-forward',
                                    '--address', '127.0.0.1', 'service/oshal-kernel-service', f'{PORT}:38788'], stdout=subprocess.DEVNULL, stderr=open(work / 'port-forward.log', 'a'))
        for _ in range(90):
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{PORT}/readyz', timeout=3) as response:
                    if json.load(response)['readiness'] == 'ready':
                        return
            except (OSError, ValueError):
                pass
            time.sleep(1)
        raise AssertionError('readiness through the Service did not succeed')

    def signin(value):
        request = urllib.request.Request(f'http://127.0.0.1:{PORT}/sessions', data=json.dumps({'username': 'admin', 'password': value}).encode(),
                                         headers={'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, response.headers.get('Set-Cookie', '').split(';')[0]
        except urllib.error.HTTPError as error:
            return error.code, ''

    try:
        name = platform()
        fetch(f"https://github.com/kubernetes-sigs/kind/releases/download/{LOCK['kindVersion']}/kind-{name}", LOCK['kind'][name], kind)
        fetch(f"https://dl.k8s.io/release/{LOCK['kubernetesVersion']}/bin/{name.replace('-', '/')}/kubectl", LOCK['kubectl'][name], kubectl)
        run([str(kind), 'create', 'cluster', '--name', cluster, '--image', LOCK['nodeImage'], '--kubeconfig', str(kubeconfig), '--wait', '180s'], timeout=600)
        receipt['checks'].append('fresh kind cluster with its own kubeconfig')

        # The cluster operator's part (install/kubernetes/README.md, "What the cluster must provide").
        def node_exec(*args, data=None):
            return subprocess.run(['docker', 'exec', '-i', node, *args], input=data, capture_output=True, check=True).stdout.decode().strip()
        node_exec('mkdir', '-p', '/var/lib/kubelet/seccomp/oshal', '/mnt/oshal-sysfs')
        node_exec('sh', '-c', 'mountpoint -q /mnt/oshal-sysfs || mount -t sysfs -o ro,nosuid,nodev,noexec sysfs /mnt/oshal-sysfs')
        node_exec('sh', '-c', 'cat > /var/lib/kubelet/seccomp/oshal/seccomp-bwrap.json', data=(ROOT / 'install/docker/seccomp-bwrap.json').read_bytes())
        apparmor = node_exec('sh', '-c', 'cat /sys/module/apparmor/parameters/enabled 2>/dev/null || true') == 'Y'
        if apparmor:
            node_exec('sh', '-c', 'mountpoint -q /sys/kernel/security || mount -t securityfs securityfs /sys/kernel/security')
            node_exec('sh', '-c', 'command -v apparmor_parser >/dev/null || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends apparmor; }')
            if not any(line.startswith('oshal-bwrap (') for line in node_exec('cat', '/sys/kernel/security/apparmor/profiles').splitlines()):
                node_exec('apparmor_parser', '-r', '-K', data=b'abi <abi/4.0>,\ninclude <tunables/global>\nprofile oshal-bwrap /usr/bin/bwrap flags=(unconfined) {\n  userns,\n}\n')
            node_exec('systemctl', 'restart', 'containerd')
            node_exec('systemctl', 'restart', 'kubelet')
        if os.environ.get('OSWARM_TEST_REGISTRY_AUTH') == '1':
            auth = json.loads((Path.home() / '.docker/config.json').read_text())['auths']['ghcr.io']['auth']
            node_exec('sh', '-c', 'umask 077; cat > /var/lib/kubelet/config.json', data=json.dumps({'auths': {'ghcr.io': {'auth': auth}}}).encode())
            node_exec('systemctl', 'restart', 'kubelet')
            receipt['registryAuth'] = 'this machine\'s ghcr.io login, written to the disposable node only (image private)'
        kube('wait', '--for=condition=Ready', 'node', '--all', '--timeout=180s')
        kube('label', 'node', node, 'oshal.io/sandbox-ready=true', '--overwrite')
        receipt['apparmor'] = apparmor
        receipt['checks'].append('node prepared: seccomp file, AppArmor profile when enabled, sandbox-ready label')

        # The module from a copy of this checkout, exactly as a person clones it.
        shutil.copytree(ROOT / 'terraform', module / 'terraform')
        shutil.copytree(ROOT / 'install', module / 'install')
        module = module / 'terraform'
        (module / 'test.auto.tfvars.json').write_text(json.dumps({
            'kube_context': context, 'kubeconfig': str(kubeconfig), 'storage_class': 'standard', 'state_access_mode': 'ReadWriteOnce',
            'apparmor': apparmor, 'deployment_profile': 'home', 'kernel_resources': {'requests': {'cpu': '100m', 'memory': '256Mi'}, 'limits': {'cpu': '2', 'memory': '2Gi'}},
        }))
        run([TERRAFORM, 'init', '-input=false'], timeout=600, quiet=True)
        run([TERRAFORM, 'apply', '-input=false', '-auto-approve'], timeout=1800)
        generated = run([TERRAFORM, 'output', '-raw', 'administrator_password'], quiet=True).strip()
        password = generated  # redact it from every later log line
        image = run([TERRAFORM, 'output', '-raw', 'image'], quiet=True).strip()
        receipt['image'] = image
        receipt['checks'].append('terraform apply: namespace, claims, in-cluster PostgreSQL, administrator and catalog init steps, kernel rollout')

        pod_image = kube('-n', 'oshal-kernel', 'get', 'pods', '-l', 'app.kubernetes.io/name=oshal-kernel', '-o', 'jsonpath={.items[0].status.containerStatuses[0].imageID}')
        assert image.split('@')[1] in pod_image, pod_image
        receipt['podImageId'] = pod_image
        start_forward()
        revision = next(line.split('=', 1)[1] for line in (ROOT / 'install/docker/image-release.env').read_text().splitlines() if line.startswith('REVISION='))
        with urllib.request.urlopen(f'http://127.0.0.1:{PORT}/version', timeout=5) as response:
            assert json.load(response)['commit'] == revision
        receipt['checks'].append('the pod runs the pinned digest; ready; /version reports the release revision')
        status, cookie = signin(password)
        assert status == 201, status
        assert signin('wrong-password-fixture-123')[0] != 201
        catalog_request = urllib.request.Request(f'http://127.0.0.1:{PORT}/api/swarm/apps/catalog', headers={'Cookie': cookie})
        with urllib.request.urlopen(catalog_request, timeout=10) as response:
            catalog = json.load(response)
        assert catalog['source'] == 'marketplace-files' and catalog['total'] >= 50, catalog.get('total')
        receipt['catalogVisibleInAppLoader'] = catalog['total']
        receipt['checks'].append('the generated password signs in, a wrong one is refused; the App Loader lists the staged catalog')

        plan = subprocess.run([TERRAFORM, 'plan', '-input=false', '-detailed-exitcode', '-no-color'], env=env, cwd=module, capture_output=True, text=True, timeout=600)
        assert plan.returncode == 0, plan.stdout[-3000:] + plan.stderr[-2000:]
        receipt['checks'].append('a second plan proposes no changes')

        # Both init steps run again on every start; neither may fail or reset anything.
        forward.terminate()
        forward.wait(timeout=10)
        kube('-n', 'oshal-kernel', 'rollout', 'restart', 'deployment/oshal-kernel-deployment')
        kube('-n', 'oshal-kernel', 'rollout', 'status', 'deployment/oshal-kernel-deployment', '--timeout=300s')
        start_forward()
        assert signin(password)[0] == 201
        steps = kube('-n', 'oshal-kernel', 'logs', 'deployment/oshal-kernel-deployment', '-c', 'initialize-administrator') + kube('-n', 'oshal-kernel', 'logs', 'deployment/oshal-kernel-deployment', '-c', 'stage-catalog')
        assert 'already set; left unchanged' in steps and 'already staged; left unchanged' in steps, steps
        receipt['checks'].append('a restart reruns both init steps without resetting the password or the catalog')

        forward.terminate()
        forward.wait(timeout=10)
        forward = None
        run([TERRAFORM, 'destroy', '-input=false', '-auto-approve'], timeout=900, quiet=True)
        assert 'oshal-kernel' not in kube('get', 'namespaces', '-o', 'name')
        receipt['checks'].append('terraform destroy removes the namespace and everything in it')
        receipt['status'] = 'passed'
    except Exception as error:
        diagnostics = []
        for args in (['get', 'pods,pvc', '-o', 'wide'], ['describe', 'pods', '-l', 'app.kubernetes.io/name=oshal-kernel'],
                     ['logs', 'deployment/oshal-kernel-deployment', '--all-containers', '--tail=60']):
            result = subprocess.run([str(kubectl), '--kubeconfig', str(kubeconfig), '--context', context, '-n', 'oshal-kernel', *args], capture_output=True, text=True, timeout=60)
            diagnostics.append(result.stdout[-3000:] + result.stderr[-500:])
        if (work / 'port-forward.log').exists():
            diagnostics.append((work / 'port-forward.log').read_text()[-1500:])
        receipt['diagnostics'] = [item.replace(password, '[private fixture password]') for item in diagnostics]
        receipt['status'] = 'failed'
        receipt['error'] = str(error).replace(password, '[private fixture password]')[-4000:]
        raise
    finally:
        if forward:
            forward.kill()
        if kind.exists():
            subprocess.run([str(kind), 'delete', 'cluster', '--name', cluster, '--kubeconfig', str(kubeconfig)], capture_output=True, timeout=300)
        receipt['clusterRemoved'] = not subprocess.run(['docker', 'ps', '-aq', '--filter', 'label=io.x-k8s.kind.cluster=' + cluster], capture_output=True, text=True).stdout.strip()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + '\n')
        print(json.dumps(receipt, indent=2), flush=True)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
