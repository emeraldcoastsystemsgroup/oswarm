'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const {release,ensureImage,validateRelease}=require('../install/image-release.cjs');
const revision='a'.repeat(40);
const image=`ghcr.io/emeraldcoastsystemsgroup/oswarm:0.0.1@sha256:${'c'.repeat(64)}`;
const selection={format:'2',version:'0.0.1',image,revision,architecture:'amd64',manifest:'sha256:'+'d'.repeat(64)};
const lock=(extra='')=>`FORMAT=2\nVERSION=0.0.1\nIMAGE=${image}\nREVISION=${revision}\nAMD64_MANIFEST=${selection.manifest}\nARM64_MANIFEST=sha256:${'e'.repeat(64)}\n${extra}`;

test('the shipped lock pins one GHCR image by digest for both architectures, and every installer names it',()=>{
  for(const arch of ['x64','arm64']) {
    const pinned=release(undefined,arch);
    assert.match(pinned.image,/^ghcr\.io\/emeraldcoastsystemsgroup\/oswarm:\d+\.\d+\.\d+@sha256:[a-f0-9]{64}$/);
    assert.match(pinned.manifest,/^sha256:[a-f0-9]{64}$/);
  }
  const result=spawnSync(process.execPath,[path.join(__dirname,'check-image-release.cjs')],{encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
});

test('the archive lock format, another registry, a tag without a digest and a version mismatch are refused',()=>{
  for(const bad of [{format:'1'},{image:'oshal-kernel:swarm-0.0.1'},{image:'docker.io/library/oswarm:0.0.1@sha256:'+'c'.repeat(64)},{image:'ghcr.io/emeraldcoastsystemsgroup/oswarm:0.0.1'},{version:'9.9.9'},{manifest:''},{revision:'short'}])
    assert.throws(()=>validateRelease({...selection,...bad}),Error,JSON.stringify(bad));
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'swarm-lock-'));
  try {
    const file=path.join(directory,'image-release.env');
    fs.writeFileSync(file,lock());assert.equal(release(file,'x64').image,image);
    fs.writeFileSync(file,lock(`IMAGE=${image}\n`));assert.throws(()=>release(file,'x64'),/Invalid image release lock/);
  } finally {fs.rmSync(directory,{recursive:true,force:true});}
});

test('the image is pulled by its pinned reference only when absent, and admitted only with the pinned architecture and revision',async()=>{
  for(const [present,bad] of [[false,null],[true,null],[false,'architecture'],[true,'revision']]) {
    const commands=[];let pulled=present;
    const record={Architecture:bad==='architecture'?'arm64':'amd64',Config:{Labels:{'org.opencontainers.image.revision':bad==='revision'?'f'.repeat(40):revision}}};
    const run=(_file,args)=>{commands.push(args);if(args[0]==='pull'){pulled=true;return '';}if(!pulled)throw new Error('absent');return JSON.stringify([record]);};
    if(bad)await assert.rejects(ensureImage({run,selection}),/identity/);
    else assert.equal(await ensureImage({run,selection}),image);
    assert.deepEqual(commands[0],['image','inspect',image]);
    assert.equal(commands.filter(args=>args[0]==='pull').length,present?0:1);
    for(const args of commands)assert.ok(!['load','tag'].includes(args[0]),'no archive load or retag');
    if(!present)assert.deepEqual(commands.find(args=>args[0]==='pull'),['pull',image]);
  }
});

function bashLoader(lockText,{revisionSeen=revision,pullFails=false}={}) {
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'swarm-bash-image-'));
  try {
    fs.writeFileSync(path.join(directory,'image-release.env'),lockText);
    const helper=fs.readFileSync(path.join(__dirname,'../install/docker/image-loader.sh'),'utf8');
    const result=spawnSync('bash',['-c',helper+`
DIR="$1"; ARCH=amd64; DOCKER=docker; PULLED=0
die() { echo "$*" >&2; exit 1; }; say() { :; }
docker() {
  echo "$*" >> "$DIR/docker-calls"
  case "$1" in
    pull) [ -n "$PULL_FAILS" ] && return 1; touch "$DIR/pulled"; return 0 ;;
    image) [ -e "$DIR/pulled" ] || return 1; [ "$#" -gt 3 ] && echo "amd64 $REVISION_SEEN"; return 0 ;;
  esac
  return 1
}
ensure_release_image && echo "IMAGE=$IMAGE"
`,'release-test',directory],{encoding:'utf8',env:{...process.env,REVISION_SEEN:revisionSeen,PULL_FAILS:pullFails?'1':''}});
    const calls=fs.existsSync(path.join(directory,'docker-calls'))?fs.readFileSync(path.join(directory,'docker-calls'),'utf8'):'';
    return {...result,calls};
  } finally {fs.rmSync(directory,{recursive:true,force:true});}
}

test('Bash pulls the pinned digest and admits it with the pinned revision',()=>{
  const result=bashLoader(lock());
  assert.equal(result.status,0,result.stderr);
  assert.match(result.stdout,new RegExp(`IMAGE=${image.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}`));
  assert.match(result.calls,new RegExp(`^pull ${image.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}$`,'m'));
  assert.doesNotMatch(result.calls,/^(load|tag) /m);
});

test('Bash refuses a wrong revision, a failed pull and the retired archive lock without loading anything',()=>{
  const wrong=bashLoader(lock(),{revisionSeen:'f'.repeat(40)});
  assert.notEqual(wrong.status,0);assert.match(wrong.stderr,/source revision does not match/);
  const failed=bashLoader(lock(),{pullFails:true});
  assert.notEqual(failed.status,0);assert.match(failed.stderr,/could not download the server image/);
  const archive=bashLoader(`FORMAT=1\nIMAGE=oshal-kernel:swarm-0.0.1\nREVISION=${revision}\nAMD64_URL=https://example.invalid/server.tar.gz\n`);
  assert.notEqual(archive.status,0);assert.match(archive.stderr,/unsupported image release format/);
  for(const run of [wrong,failed,archive])assert.doesNotMatch(run.calls,/^(load|tag) /m);
  assert.equal(archive.calls,'');
});
