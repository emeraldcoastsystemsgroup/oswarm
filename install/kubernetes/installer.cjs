#!/usr/bin/env node
'use strict';
// A private, owned local kind cluster. Never uses the operator's current kubectl context.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const {spawnSync, spawn} = require('node:child_process');
const lock = require('./tools.lock.json');
const imageRelease = require('../image-release.cjs');
const POSTGRES = 'postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea';
const CATALOG = '3a0e0764f143472ac3f181bd0f98127cc23dd90b';
const NS = 'oshal-swarm';
const LABEL = 'oshal.ai/installation';
const WIN = process.platform === 'win32';
const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function run(file, args, options = {}) {
  const result = spawnSync(file, args, {encoding:'utf8', timeout:600000, maxBuffer:16*1024*1024, ...options});
  if (result.error || result.status !== 0) {
    // Secret input and command output may contain credentials; do not echo them.
    throw new Error(`${path.basename(file)} ${args[0] || ''} failed. ${result.error?.code || `Exit ${result.status}`}. Installation state was retained for retry.`);
  }
  return (result.stdout || '').trim();
}
function prepareDocker(directory) {
  let available=spawnSync('docker',['info','--format','{{.OSType}}'],{encoding:'utf8',timeout:15000});
  if(available.status===0 && available.stdout.trim()==='linux')return;
  console.log('Preparing Docker for your Kubernetes Swarm…');
  const installer=path.join(__dirname,'..',WIN?'install.ps1':'install.sh');
  run(WIN?'powershell.exe':'bash',WIN?['-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',installer,'-Action','prepare']:[installer,'prepare'],{stdio:'inherit'});
  if(WIN) {
    process.env.Path=run('powershell.exe',['-NoProfile','-Command',"[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')"]);
  }
  available=spawnSync('docker',['info','--format','{{.OSType}}'],{encoding:'utf8',timeout:15000});
  if(available.status===0 && available.stdout.trim()==='linux')return;
  if(process.platform==='linux') {
    const executable=run('sh',['-c','command -v docker']);
    const sudo=spawnSync('sudo',['-n',executable,'info','--format','{{.OSType}}'],{encoding:'utf8',timeout:15000});
    if(sudo.status===0 && sudo.stdout.trim()==='linux') {
      const wrappers=path.join(directory,'docker-access');fs.mkdirSync(wrappers,{mode:0o700,recursive:true});
      const quote=value=>"'"+value.replaceAll("'","'\\''")+"'";
      fs.writeFileSync(path.join(wrappers,'docker'),'#!/bin/sh\nexec sudo '+quote(executable)+' "$@"\n',{mode:0o700});
      process.env.PATH=wrappers+path.delimiter+process.env.PATH;return;
    }
  }
  throw new Error('Docker is not ready yet. Complete the Docker Desktop setup or requested Windows restart, then run the same install command again.');
}
function localDockerOnly() {
  let endpoint=process.env.DOCKER_HOST;
  if(!endpoint) {
    const context=spawnSync('docker',['context','inspect','--format','{{.Endpoints.docker.Host}}'],{encoding:'utf8',timeout:15000});
    if(context.status===0)endpoint=context.stdout.trim();
  }
  if(endpoint && !endpoint.startsWith('unix://') && !endpoint.startsWith('npipe://'))throw new Error('Select your local Docker Desktop or Docker Engine context before installing a local Kubernetes Swarm. Remote Docker endpoints are not supported.');
}
function ensurePrivate(directory) {
  if (fs.existsSync(directory) && fs.lstatSync(directory).isSymbolicLink()) throw new Error('Installation directory must not be a symbolic link.');
  fs.mkdirSync(directory,{recursive:true,mode:0o700});
  if (WIN) {
    const me = run('whoami', []);
    run('icacls.exe', [directory,'/inheritance:r','/grant:r',`${me}:(OI)(CI)F`,'/grant:r','SYSTEM:(OI)(CI)F']);
  } else {
    const stat = fs.statSync(directory);
    if (stat.uid !== process.getuid()) throw new Error('Installation directory belongs to another account.');
    fs.chmodSync(directory,0o700);
  }
}
function writeManagement(directory) {
  const source=path.join(__dirname,'..'),persistent=path.join(directory,'installer');
  if(fs.existsSync(persistent)&&fs.lstatSync(persistent).isSymbolicLink())throw new Error('The management installer folder must not be a symbolic link.');
  if(path.resolve(source)!==path.resolve(persistent))fs.cpSync(source,persistent,{recursive:true,force:true});
  const entry=path.join(persistent,'kubernetes','installer.cjs');
  if(WIN) {
    const quote=value=>"'"+value.replaceAll("'","''")+"'";
    fs.writeFileSync(path.join(directory,'oswarm-kubernetes.ps1'),`& ${quote(process.execPath)} ${quote(entry)} --dir ${quote(directory)} @args\nexit $LASTEXITCODE\n`,{mode:0o600});
  } else {
    const quote=value=>"'"+value.replaceAll("'","'\\''")+"'";
    fs.writeFileSync(path.join(directory,'oswarm-kubernetes.sh'),`#!/usr/bin/env bash\nexec ${quote(process.execPath)} ${quote(entry)} --dir ${quote(directory)} "$@"\n`,{mode:0o700});
  }
}
function writePrivate(file, value) {
  const pending = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(pending, JSON.stringify(value,null,2)+'\n',{mode:0o600,flag:'wx'});
  fs.renameSync(pending,file);
}
async function download(url, digest) {
  const response = await fetch(url,{signal:AbortSignal.timeout(180000)});
  if (!response.ok) throw new Error(`Download failed (${response.status}) from ${new URL(url).hostname}.`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (digest && sha(bytes) !== digest) throw new Error('Downloaded tool checksum does not match this installer release.');
  return bytes;
}
async function tools(directory) {
  const platform = `${WIN?'windows':process.platform}-${process.arch==='x64'?'amd64':process.arch}`;
  if (!lock.kind[platform]) throw new Error(`Kubernetes setup does not support ${platform}.`);
  const bin = path.join(directory,'bin'); fs.mkdirSync(bin,{mode:0o700,recursive:true});
  const result = {};
  for (const name of ['kind','kubectl']) {
    const file = path.join(bin,name+(WIN?'.exe':''));
    if (!fs.existsSync(file) || sha(fs.readFileSync(file)) !== lock[name][platform]) {
      console.log(`Downloading verified ${name} for this computer…`);
      const url = name==='kind' ? `https://github.com/kubernetes-sigs/kind/releases/download/${lock.kindVersion}/kind-${platform}` :
        `https://dl.k8s.io/release/${lock.kubernetesVersion}/bin/${platform.replace('-','/')}/kubectl${WIN?'.exe':''}`;
      const data = await download(url,lock[name][platform]);
      fs.writeFileSync(file,data,{mode:0o700});fs.chmodSync(file,0o700);
    }
    result[name]=file;
  }
  return result;
}
function render(state) {
  const items = structuredClone(require('./resources.json'));
  const meta = name => ({name,namespace:NS,labels:{[LABEL]:state.id}});
  for (const item of items) {
    item.metadata.labels = {...item.metadata.labels,[LABEL]:state.id};
    if (item.kind==='Namespace') item.metadata.name=NS;
    else item.metadata.namespace=NS;
    if (item.kind==='PersistentVolumeClaim') Object.assign(item.spec,{storageClassName:'standard',accessModes:['ReadWriteOnce']});
  }
  const config = items.find(item=>item.kind==='ConfigMap' && item.metadata.name==='oshal-kernel-config');
  for (const key of Object.keys(config.metadata)) if (key.startsWith('OSHAL_')) {config.data[key]=config.metadata[key];delete config.metadata[key];}
  Object.assign(config.data,{OSHAL_DEPLOYMENT:'home',OSHAL_ADMIN_SUBJECT:state.username,
    OSHAL_PACKAGE_DATA_DIR:'/var/lib/oshal/package-data',OSHAL_APP_PRIVATE_DIR:'/opt/oshal/disabled-private',
    OSHAL_ADDITIONAL_APPLICATIONS_DIRS:'/opt/oshal/disabled-additional',OSHAL_CODE_SERVER_URL:`http://127.0.0.1:${state.editorPort}`});
  const kernel=items.find(item=>item.kind==='Deployment' && item.metadata.name==='oshal-kernel-deployment');
  kernel.spec.replicas=0;
  const pod=kernel.spec.template;
  pod.metadata.annotations={'oshal.ai/source-revision':state.revision,'oshal.ai/image-id':state.imageId};
  pod.spec.nodeSelector={'kubernetes.io/os':'linux','oshal.io/sandbox-ready':'true'};
  const container=pod.spec.containers[0];container.image=state.image;
  container.resources={requests:{cpu:'100m',memory:'256Mi'},limits:{cpu:'1500m',memory:'1536Mi'}};
  if (!state.apparmor) delete container.securityContext.appArmorProfile;
  items.find(item=>item.kind==='Deployment' && item.metadata.name==='code-server').spec.replicas=0;
  items.push({apiVersion:'v1',kind:'PersistentVolumeClaim',metadata:meta('oshal-postgres-data'),spec:{accessModes:['ReadWriteOnce'],storageClassName:'standard',resources:{requests:{storage:'2Gi'}}}},
    {apiVersion:'v1',kind:'Service',metadata:meta('oshal-postgres'),spec:{selector:{app:'oshal-postgres'},ports:[{port:5432,targetPort:5432}]}},
    {apiVersion:'apps/v1',kind:'Deployment',metadata:meta('oshal-postgres'),spec:{replicas:1,strategy:{type:'Recreate'},selector:{matchLabels:{app:'oshal-postgres'}},template:{metadata:{labels:{app:'oshal-postgres'}},spec:{automountServiceAccountToken:false,
      securityContext:{runAsUser:70,runAsGroup:70,fsGroup:70},containers:[{name:'postgres',image:POSTGRES,env:[{name:'POSTGRES_PASSWORD',valueFrom:{secretKeyRef:{name:'oshal-kernel-secret',key:'postgresPassword'}}},{name:'POSTGRES_DB',value:'oshal'},{name:'PGDATA',value:'/var/lib/postgresql/data/pgdata'}],
        resources:{requests:{cpu:'50m',memory:'128Mi'},limits:{cpu:'500m',memory:'512Mi'}},securityContext:{allowPrivilegeEscalation:false,capabilities:{drop:['ALL']},seccompProfile:{type:'RuntimeDefault'}},readinessProbe:{exec:{command:['pg_isready','-U','postgres','-d','oshal']}},
        volumeMounts:[{name:'database',mountPath:'/var/lib/postgresql/data'}]}],volumes:[{name:'database',persistentVolumeClaim:{claimName:'oshal-postgres-data'}}]}}}});
  return items;
}
function parse(argv) {
  const options={action:'install',directory:path.resolve(process.env.OSWARM_K8S_DIR || path.join(os.homedir(),'oswarm-kubernetes')),
    port:Number(process.env.OSWARM_PORT || 38788),editorPort:Number(process.env.OSWARM_EDITOR_PORT || 38789),
    image:process.env.OSWARM_IMAGE || imageRelease.release().image,username:process.env.OSWARM_ADMIN || 'admin'};
  for(let index=0;index<argv.length;index++) {
    const arg=argv[index];
    if(['install','status','start','stop','restart','logs','open','uninstall'].includes(arg)) options.action=arg;
    else if(arg==='--purge') options.purge=true;
    else if(['--dir','--port','--editor-port','--image','--admin'].includes(arg)) {
      const value=argv[++index];if(!value || value.startsWith('--'))throw new Error(`Supply a value for ${arg}.`);
      const key={'--dir':'directory','--port':'port','--editor-port':'editorPort','--image':'image','--admin':'username'}[arg];
      options[key]=key==='directory'?path.resolve(value):['port','editorPort'].includes(key)?Number(value):value;
    } else throw new Error(`Unknown Kubernetes installer argument: ${arg}`);
  }
  for(const port of [options.port,options.editorPort]) if(!Number.isInteger(port)||port<1024||port>65535)throw new Error('Choose ports between 1024 and 65535.');
  if(options.port===options.editorPort)throw new Error('The server and editor need distinct ports.');
  if(!/^[A-Za-z0-9][A-Za-z0-9_.@-]{0,79}$/.test(options.username))throw new Error('Choose a simple administrator name of up to 80 characters.');
  return options;
}
async function main(argv=process.argv.slice(2)) {
  const options=parse(argv),directory=options.directory,file=path.join(directory,'state.json');
  ensurePrivate(directory);
  if(fs.existsSync(file) && fs.lstatSync(file).isSymbolicLink())throw new Error('State file must not be a symbolic link.');
  let state=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):null;
  if(!state && options.action!=='install')throw new Error('No installation was found in this directory.');
  localDockerOnly();
  prepareDocker(directory);
  localDockerOnly();
  const dockerInfo=JSON.parse(run('docker',['info','--format','{{json .}}']));
  if(dockerInfo.OSType!=='linux')throw new Error('Start Docker Desktop in Linux containers mode, then run this command again.');
  if(dockerInfo.MemTotal<6*1024**3)throw new Error('Kubernetes needs at least 6 GB assigned to Docker. On Windows with WSL 2, raise the WSL memory limit and restart Docker Desktop. On other Docker Desktop systems, use Settings → Resources.');
  const binaries=await tools(directory);
  const save=()=>writePrivate(file,state);
  if(!state) {
    const password=process.env.OSWARM_ADMIN_PASSWORD || crypto.randomBytes(24).toString('base64url');
    if(Buffer.byteLength(password)<12 || Buffer.byteLength(password)>1024 || /[\x00-\x1f\x7f]/.test(password))throw new Error('Administrator password must be 12–1024 bytes without control characters.');
    const id=crypto.randomBytes(8).toString('hex');
    state={format:1,id,cluster:`oshal-${id}`,kubeconfig:path.join(directory,'kubeconfig'),directory,
      port:options.port,editorPort:options.editorPort,username:options.username,password,image:options.image,
      admin:crypto.randomBytes(32).toString('hex'),vault:crypto.randomBytes(32).toString('hex'),postgres:crypto.randomBytes(32).toString('hex'),phase:'planned'};
    save();
  }
  if(state.format!==1 || state.directory!==directory || !/^[a-f0-9]{16}$/.test(state.id) || state.cluster!==`oshal-${state.id}` || state.kubeconfig!==path.join(directory,'kubeconfig'))throw new Error('Installation identity does not match its private directory.');
  writeManagement(directory);
  const kube=(...args)=>run(binaries.kubectl,['--kubeconfig',state.kubeconfig,'--context',`kind-${state.cluster}`,...args]);
  const input=(data,...args)=>run(binaries.kubectl,['--kubeconfig',state.kubeconfig,'--context',`kind-${state.cluster}`,...args],{input:typeof data==='string'||Buffer.isBuffer(data)?data:JSON.stringify(data)});
  const apply=items=>input({apiVersion:'v1',kind:'List',items},'apply','-f','-');
  const owned=()=>{
    const node=JSON.parse(run('docker',['inspect',`${state.cluster}-control-plane`]))[0];
    if(node.Config.Labels['io.x-k8s.kind.cluster']!==state.cluster || (state.nodeId && node.Id!==state.nodeId))throw new Error('The owned Kubernetes node has changed.');
    if(state.clusterUid && kube('get','namespace','kube-system','-o','jsonpath={.metadata.uid}')!==state.clusterUid)throw new Error('Kubernetes cluster identity changed.');
    return node;
  };
  if(options.action==='uninstall') {
    if(!options.purge)throw new Error('Uninstall deletes this cluster and its data. Add --purge to explicitly remove it.');
    owned();run(binaries.kind,['delete','cluster','--name',state.cluster,'--kubeconfig',state.kubeconfig]);
    state.phase='removed';save();console.log('Removed this installation’s cluster and volumes. Its private receipt remains in the installation folder.');return;
  }
  if(options.action==='install') {
    if(state.phase==='removed')throw new Error('This installation was removed. Choose a new --dir for a new installation.');
    if(state.phase==='planned') {
      const clusters=run(binaries.kind,['get','clusters']).split(/\r?\n/);
      if(clusters.includes(state.cluster))throw new Error('The planned cluster name already exists. Refusing to adopt it.');
      console.log('Creating your private Kubernetes cluster. This first download can take several minutes…');
      // Explicit kubeconfig prevents changing or selecting the operator’s global current context.
      run(binaries.kind,['create','cluster','--name',state.cluster,'--image',lock.nodeImage,'--kubeconfig',state.kubeconfig,'--wait','180s'],{stdio:'inherit'});
      run('docker',['update','--memory','6g','--memory-swap','6g','--cpus','2',`${state.cluster}-control-plane`]);
      fs.chmodSync(state.kubeconfig,0o600);
      state.nodeId=owned().Id;state.clusterUid=kube('get','namespace','kube-system','-o','jsonpath={.metadata.uid}');state.phase='cluster-created';save();
    }
    owned();
    if(state.phase==='cluster-created') {
      console.log('Preparing the application sandbox inside your cluster…');
      const node=`${state.cluster}-control-plane`;
      const exec=(...args)=>run('docker',['exec',node,...args]);
      exec('mkdir','-p','/var/lib/kubelet/seccomp/oshal','/mnt/oshal-sysfs');
      exec('sh','-c','mountpoint -q /mnt/oshal-sysfs || mount -t sysfs -o ro,nosuid,nodev,noexec sysfs /mnt/oshal-sysfs');
      run('docker',['exec','-i',node,'sh','-c','cat > /var/lib/kubelet/seccomp/oshal/seccomp-bwrap.json'],{input:fs.readFileSync(path.join(__dirname,'../docker/seccomp-bwrap.json'))});
      state.apparmor=exec('sh','-c','cat /sys/module/apparmor/parameters/enabled 2>/dev/null || true')==='Y';
      if(state.apparmor) {
        exec('sh','-c','mountpoint -q /sys/kernel/security || mount -t securityfs securityfs /sys/kernel/security');
        exec('sh','-c','command -v apparmor_parser >/dev/null || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends apparmor; }');
        const profiles=exec('cat','/sys/kernel/security/apparmor/profiles');
        if(!profiles.split('\n').some(line=>line.startsWith('oshal-bwrap ('))) {
          const policy='abi <abi/4.0>,\ninclude <tunables/global>\nprofile oshal-bwrap /usr/bin/bwrap flags=(unconfined) {\n  userns,\n}\n';
          run('docker',['exec','-i',node,'apparmor_parser','-r','-K'],{input:policy});
        }
        exec('systemctl','restart','containerd');exec('systemctl','restart','kubelet');
      }
      kube('wait','--for=condition=Ready','node','--all','--timeout=180s');
      kube('label','node',node,'oshal.io/sandbox-ready=true','--overwrite');
      state.phase='sandbox-ready';save();
    }
    if(state.phase==='sandbox-ready') {
      console.log('Loading the Swarm server and database…');
      if(state.image===imageRelease.release().image) await imageRelease.ensureImage({directory,run,selection:imageRelease.release(undefined,dockerInfo.Architecture)});
      else {try {run('docker',['image','inspect',state.image]);} catch {run('docker',['pull',state.image],{stdio:'inherit'});}}
      const image=JSON.parse(run('docker',['image','inspect',state.image]))[0];state.imageId=image.Id;state.revision=image.Config.Labels?.['org.opencontainers.image.revision'];
      if(!/^[a-f0-9]{40}$/.test(state.revision || ''))throw new Error('Server image is missing its exact source revision label.');
      // kind/containerd resolves Docker Hub short image names differently; use an explicit local alias.
      const alias=`oshal-kernel:swarm-${state.id}`;run('docker',['tag',state.image,alias]);state.image=alias;
      // Import only our locally built/tagged kernel. containerd can retain a dangling
      // synthetic import-* name when kind imports an untagged multi-platform digest;
      // kubelet then fails checkpoint lookup even though the PostgreSQL digest exists.
      // PostgreSQL is public and pinned: let kubelet pull that exact digest normally.
      run(binaries.kind,['load','docker-image',state.image,'--name',state.cluster],{stdio:'inherit'});
      state.phase='images-ready';save();
    }
    const docs=render(state);
    if(state.phase==='images-ready') {
      const existing=kube('get','namespace',NS,'--ignore-not-found','-o','json');
      if(existing && JSON.parse(existing).metadata.labels?.[LABEL]!==state.id)throw new Error('Refusing to replace an existing namespace.');
      apply([docs.find(item=>item.kind==='Namespace')]);
      apply([{apiVersion:'v1',kind:'Secret',metadata:{name:'oshal-kernel-secret',namespace:NS},stringData:{OSHAL_ADMIN_TOKEN:state.admin,OSHAL_VAULT_KEY:state.vault,OSHAL_POSTGRES:`postgresql://postgres:${state.postgres}@oshal-postgres:5432/oshal`,postgresPassword:state.postgres}},...docs.filter(item=>item.kind!=='Namespace')]);
      kube('-n',NS,'rollout','status','deployment/oshal-postgres','--timeout=180s');state.phase='database-ready';save();
    }
    if(state.phase==='database-ready') {
      console.log('Setting up your administrator account…');
      const pod=structuredClone(docs.find(item=>item.kind==='Deployment'&&item.metadata.name==='oshal-kernel-deployment').spec.template);
      pod.metadata.labels={'oshal.ai/setup':'administrator'};pod.spec.restartPolicy='Never';
      const c=pod.spec.containers[0];for(const key of ['startupProbe','livenessProbe','readinessProbe','ports','args'])delete c[key];
      c.command=['/bin/sh','-c','exec /usr/local/bin/oshald init-password < /run/initial-password/input.json'];
      c.volumeMounts.push({name:'initial-password',mountPath:'/run/initial-password',readOnly:true});
      pod.spec.volumes.push({name:'initial-password',secret:{secretName:'oshal-initial-password',defaultMode:0o440}});
      apply([{apiVersion:'v1',kind:'Secret',metadata:{name:'oshal-initial-password',namespace:NS},stringData:{'input.json':JSON.stringify({username:state.username,password:state.password})}},
        {apiVersion:'batch/v1',kind:'Job',metadata:{name:'oshal-initialize-administrator',namespace:NS},spec:{backoffLimit:0,activeDeadlineSeconds:180,template:pod}}]);
      kube('-n',NS,'wait','--for=condition=complete','job/oshal-initialize-administrator','--timeout=180s');
      kube('-n',NS,'delete','secret','oshal-initial-password','--ignore-not-found');state.phase='administrator-ready';save();
    }
    if(state.phase==='administrator-ready') {
      console.log('Installing the public application catalog…');
      const pod={apiVersion:'v1',kind:'Pod',metadata:{name:'oshal-catalog-setup',namespace:NS},spec:{automountServiceAccountToken:false,restartPolicy:'Never',securityContext:{runAsUser:10001,runAsGroup:10001,fsGroup:10001},
        containers:[{name:'catalog',image:POSTGRES,command:['sleep','600'],securityContext:{allowPrivilegeEscalation:false,capabilities:{drop:['ALL']},seccompProfile:{type:'RuntimeDefault'}},resources:{requests:{cpu:'20m',memory:'32Mi'},limits:{cpu:'250m',memory:'256Mi'}},volumeMounts:[{name:'catalog',mountPath:'/catalog'}]}],volumes:[{name:'catalog',persistentVolumeClaim:{claimName:'oshal-kernel-applications'}}]}};
      apply([pod]);kube('-n',NS,'wait','--for=condition=Ready','pod/oshal-catalog-setup','--timeout=180s');
      const archive=await download(`https://codeload.github.com/emeraldcoastsystemsgroup/oshal-apps/tar.gz/${CATALOG}`,lock.catalogArchiveSha256);
      const names=input(archive,'-n',NS,'exec','-i','oshal-catalog-setup','--','tar','-tzf','-').split('\n');
      if(names.some(name=>name.startsWith('/')||name.split('/').includes('..')))throw new Error('Catalog archive contains an unsafe path.');
      const listing=input(archive,'-n',NS,'exec','-i','oshal-catalog-setup','--','tar','-tzvf','-');
      if(listing.split('\n').some(line=>line && !['-','d'].includes(line[0])))throw new Error('Catalog archive contains a link or special file.');
      kube('-n',NS,'exec','oshal-catalog-setup','--','mkdir','-p','/catalog/applications');
      input(archive,'-n',NS,'exec','-i','oshal-catalog-setup','--','tar','-xz','--strip-components=1','-C','/catalog/applications');
      kube('-n',NS,'exec','oshal-catalog-setup','--','chmod','-R','a+rX','/catalog/applications');
      input(JSON.stringify({version:1,origin:'https://github.com/emeraldcoastsystemsgroup/oshal-apps',reference:CATALOG,commit:CATALOG,provenance:'reconstructed-from-origin',archiveSha256:sha(archive)}),'-n',NS,'exec','-i','oshal-catalog-setup','--','sh','-c','cat > /catalog/applications/native-source-origin.json');
      kube('-n',NS,'delete','pod','oshal-catalog-setup','--wait=true');state.catalogRevision=CATALOG;state.catalogArchiveSha256=sha(archive);state.phase='catalog-ready';save();
    }
    if(state.phase==='catalog-ready' || state.phase==='ready') {
      for(const name of ['oshal-kernel-deployment','code-server']) {
        kube('-n',NS,'scale',`deployment/${name}`,'--replicas=1');
        kube('-n',NS,'rollout','status',`deployment/${name}`,'--timeout=300s');
      }
      const first=state.phase!=='ready';state.phase='ready';save();
      console.log(`Swarm is ready. Administrator: ${state.username}`);
      if(first && !process.env.OSWARM_ADMIN_PASSWORD)console.log(`Initial password: ${state.password}\nSave it now. It is also stored in your private installation folder.`);
    }
  } else {
    owned();
    const namespace=JSON.parse(kube('get','namespace',NS,'-o','json'));
    if(namespace.metadata.labels?.[LABEL]!==state.id)throw new Error('Namespace ownership changed.');
    if(options.action==='status') {console.log(kube('-n',NS,'get','deployments,pods,pvc','-o','wide'));return;}
    if(options.action==='logs') {console.log(kube('-n',NS,'logs','deployment/oshal-kernel-deployment','--tail=100'));return;}
    if(['start','stop','restart'].includes(options.action)) {
      for(const name of ['oshal-kernel-deployment','code-server']) {
        if(options.action==='restart')kube('-n',NS,'rollout','restart',`deployment/${name}`);
        else kube('-n',NS,'scale',`deployment/${name}`,`--replicas=${options.action==='stop'?0:1}`);
        if(options.action!=='stop')kube('-n',NS,'rollout','status',`deployment/${name}`,'--timeout=300s');
      }
      if(options.action==='stop')for(const name of ['oshal-kernel','code-server'])kube('-n',NS,'wait','--for=delete','pod','-l',`app.kubernetes.io/name=${name}`,'--timeout=180s');
      console.log(`Swarm ${options.action} complete; persistent data retained.`);return;
    }
  }
  console.log(`Manage this installation with ${path.join(directory,WIN?'oswarm-kubernetes.ps1':'oswarm-kubernetes.sh')}.`);
  if(process.env.OSWARM_NO_FORWARD==='1')return;
  const forwards=[['service/oshal-kernel-service',`${state.port}:38788`],['service/code-server',`${state.editorPort}:8080`]].map(args=>spawn(binaries.kubectl,['--kubeconfig',state.kubeconfig,'--context',`kind-${state.cluster}`,'-n',NS,'port-forward','--address','127.0.0.1',...args],{stdio:'inherit'}));
  const close=()=>forwards.forEach(child=>child.kill());process.once('SIGINT',close);process.once('SIGTERM',close);
  for(const child of forwards)child.on('error',close);
  console.log(`Open http://127.0.0.1:${state.port}/login. Keep this window open while using Swarm.`);
  if(process.env.OSWARM_NO_BROWSER!=='1') {
    await sleep(1500);const url=`http://127.0.0.1:${state.port}/login`;
    if(WIN)spawn('explorer.exe',[url],{stdio:'ignore'}).on('error',()=>{});
    else spawn(process.platform==='darwin'?'open':'xdg-open',[url],{stdio:'ignore'}).on('error',()=>{});
  }
  await Promise.all(forwards.map(child=>new Promise(resolve=>child.on('exit',code=>{close();if(code)process.exitCode=1;resolve();}))));
}
module.exports={parse,render,tools,writeManagement,main};
if(require.main===module)main().catch(error=>{console.error(`Swarm setup stopped: ${error.message}`);process.exitCode=1;});
