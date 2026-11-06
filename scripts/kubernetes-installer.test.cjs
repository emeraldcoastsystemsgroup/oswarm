'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parse,render}=require('../install/kubernetes/installer.cjs');
const {writeManagement}=require('../install/kubernetes/installer.cjs');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawnSync}=require('node:child_process');
const fixture={id:'1234567890abcdef',image:'oshal-kernel:owned-test',imageId:'sha256:'+'a'.repeat(64),revision:'b'.repeat(40),username:'admin',port:38880,editorPort:38881,apparmor:true};
test('the persistent manager runs its copied installer from a quoted directory and rejects missing state before Docker',()=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'swarm-management-'));
  const directory=path.join(root,"owner's installation");fs.mkdirSync(directory);
  try {
    writeManagement(directory);
    for(const file of ['kubernetes/installer.cjs','kubernetes/tools.lock.json','kubernetes/resources.json','image-release.cjs','docker/image-release.env','install.sh','install.ps1'])assert.equal(fs.statSync(path.join(directory,'installer',file)).isFile(),true,file);
    const win=process.platform==='win32';
    const launcher=path.join(directory,win?'oswarm-kubernetes.ps1':'oswarm-kubernetes.sh');
    const result=spawnSync(win?'powershell.exe':'bash',win?['-NoProfile','-File',launcher,'status']:[launcher,'status'],{encoding:'utf8',timeout:10000});
    assert.notEqual(result.status,0);assert.match(result.stderr,/No installation was found/);
    assert.equal(fs.existsSync(path.join(directory,'state.json')),false);
  } finally {fs.rmSync(root,{recursive:true,force:true});}
});
test('invalid ports, missing values and unknown actions fail before cluster creation',()=>{
  for(const args of [['--port','0'],['--port','hello'],['--port','38880','--editor-port','38880'],['--dir'],['delete'],['--admin','admin;bad']])assert.throws(()=>parse(args));
});
test('kernel and database retain single-writer state and bounded sandbox policies',()=>{
  const resources=render(fixture);
  const kernel=resources.find(item=>item.kind==='Deployment'&&item.metadata.name==='oshal-kernel-deployment');
  assert.equal(kernel.spec.replicas,0,'the kernel must wait for password bootstrap');
  assert.equal(kernel.spec.strategy.type,'Recreate');
  const pod=kernel.spec.template.spec,security=pod.containers[0].securityContext;
  assert.equal(pod.hostUsers,false);assert.equal(pod.automountServiceAccountToken,false);
  assert.equal(security.allowPrivilegeEscalation,false);assert.equal(security.readOnlyRootFilesystem,true);
  assert.deepEqual(security.capabilities.drop,['ALL']);assert.equal(security.seccompProfile.type,'Localhost');
  assert.equal(security.appArmorProfile.localhostProfile,'oshal-bwrap');assert.equal(security.procMount,'Unmasked');
  const claim=pod.volumes.find(volume=>volume.name==='kernel-state');assert.equal(claim.persistentVolumeClaim.claimName,'oshal-kernel-state');
  assert.equal(resources.find(item=>item.kind==='Deployment'&&item.metadata.name==='oshal-postgres').spec.strategy.type,'Recreate');
  assert.ok(resources.filter(item=>item.kind==='PersistentVolumeClaim').length>=4);
});
test('platforms without AppArmor retain namespaces, seccomp and capability restrictions',()=>{
  const pod=render({...fixture,apparmor:false}).find(item=>item.kind==='Deployment'&&item.metadata.name==='oshal-kernel-deployment').spec.template.spec;
  assert.equal(pod.containers[0].securityContext.appArmorProfile,undefined);
  assert.equal(pod.hostUsers,false);assert.equal(pod.containers[0].securityContext.seccompProfile.type,'Localhost');
});
test('all resources stay in the owned namespace and editor listens on pod loopback',()=>{
  const resources=render(fixture);
  for(const item of resources){assert.equal(item.metadata.labels['oshal.ai/installation'],fixture.id);assert.equal(item.kind==='Namespace'?item.metadata.name:item.metadata.namespace,'oshal-swarm');}
  const editor=resources.find(item=>item.kind==='Deployment'&&item.metadata.name==='code-server');
  assert.ok(editor.spec.template.spec.containers[0].args.includes('127.0.0.1:8080'));
  assert.equal(editor.spec.template.spec.automountServiceAccountToken,false);
  const config=resources.find(item=>item.kind==='ConfigMap'&&item.metadata.name==='oshal-kernel-config');
  assert.equal(config.data.OSHAL_ADMIN_SUBJECT,'admin');assert.equal(config.data.OSHAL_CODE_SERVER_URL,'http://127.0.0.1:38881');
});
