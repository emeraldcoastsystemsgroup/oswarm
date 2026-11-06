'use strict';
// Read the release lock, pull its server image by digest, and admit it only with the pinned
// architecture and source revision. A digest names exact bytes, so no other image can answer.
const fs=require('node:fs');
const path=require('node:path');
const IMAGE_RE=/^ghcr\.io\/emeraldcoastsystemsgroup\/oswarm:[0-9A-Za-z._-]+@sha256:[a-f0-9]{64}$/;
function release(file=path.join(__dirname,'docker/image-release.env'),arch=process.arch) {
  const values={};
  for(const line of fs.readFileSync(file,'utf8').split(/\r?\n/)) {
    if(!line || line.startsWith('#'))continue;
    const match=/^([A-Z0-9_]+)=(.*)$/.exec(line);
    if(!match || Object.hasOwn(values,match[1]))throw new Error('Invalid image release lock.');
    values[match[1]]=match[2];
  }
  const architecture={x64:'amd64',amd64:'amd64',x86_64:'amd64',arm64:'arm64',aarch64:'arm64'}[arch];
  if(!architecture)throw new Error(`Server installation does not support ${arch}.`);
  const result={format:values.FORMAT,version:values.VERSION,image:values.IMAGE,revision:values.REVISION,architecture,manifest:values[`${architecture.toUpperCase()}_MANIFEST`]};
  validateRelease(result);
  return result;
}
function validateRelease(selection) {
  if(selection.format!=='2')throw new Error('Unsupported image release format; download the current installer.');
  if(!IMAGE_RE.test(selection.image||'')||!/^[a-f0-9]{40}$/.test(selection.revision||''))throw new Error('Invalid image release identity.');
  if(!/^sha256:[a-f0-9]{64}$/.test(selection.manifest||''))throw new Error(`The ${selection.architecture} server image is not pinned in this installer.`);
  if(selection.version && !selection.image.includes(`:${selection.version}@`))throw new Error('The image release tag does not match its version.');
}
async function ensureImage({run,selection=release()}) {
  validateRelease(selection);
  let present=false;
  try {run('docker',['image','inspect',selection.image]);present=true;} catch { /* Absent: pull the pinned digest. */ }
  if(!present) {
    console.log('Downloading the Swarm server image (pinned by digest)…');
    run('docker',['pull',selection.image],{stdio:'inherit'});
  }
  const image=JSON.parse(run('docker',['image','inspect',selection.image]))[0];
  if(image.Architecture!==selection.architecture||image.Config.Labels?.['org.opencontainers.image.revision']!==selection.revision)throw new Error('Server image identity does not match this release.');
  return selection.image;
}
module.exports={release,ensureImage,validateRelease};
