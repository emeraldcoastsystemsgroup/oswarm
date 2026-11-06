'use strict';
// Before a package or site is published: every installer names the one image the lock pins.
const fs=require('node:fs');
const path=require('node:path');
const {release}=require('../install/image-release.cjs');
const root=path.join(__dirname,'..');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const lock=release(undefined,'x64');release(undefined,'arm64');
const version=JSON.parse(read('package.json')).version;
if(lock.version!==version)throw new Error(`package.json is ${version} but the image lock is ${lock.version}.`);
const [name,digest]=lock.image.split('@');
const expected={
  'install/install.sh':`IMAGE_DEFAULT="${name.replace(`:${version}`,':${VERSION}')}@${digest}"`,
  'install/install.ps1':`$ImageDefault = "${name.replace(`:${version}`,':$Version')}@${digest}"`,
  'install/docker/.env.example':`OSWARM_IMAGE=${lock.image}`,
  'install/kubernetes/deployment.yaml':`image: ${lock.image}`,
  'install/kubernetes/resources.json':`"image": "${lock.image}"`,
};
for(const [file,line] of Object.entries(expected))if(!read(file).includes(line))throw new Error(`${file} does not name ${lock.image}.`);
if(!read('install/install.sh').includes(`VERSION="${version}"`)||!read('install/install.ps1').includes(`$Version = '${version}'`))throw new Error('An installer names another version.');
console.log(`Every installer names ${lock.image}.`);
