#!/usr/bin/env node
'use strict';
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const argv=process.argv.slice(2);
const engine=argv[0]==='kubernetes'||argv[0]==='docker'?argv.shift():'docker';
if(argv.includes('--help')||argv.includes('-h')) {
  console.log('Open Swarm server installer\n\n  npx oswarm docker        Install Swarm with Docker\n  npx oswarm kubernetes    Install a dedicated local Kubernetes Swarm\n\nLater: add status, start, stop, restart or logs.\nUse --dir <folder> to select an installation. Kubernetes open keeps your local connection open.\nOrbit, the companion for a computer you want to control, is a separate download.');
} else if(engine==='kubernetes') {
  require('../install/kubernetes/installer.cjs').main(argv).catch(error=>{console.error(error.message);process.exitCode=1;});
} else {
  const win=process.platform==='win32';
  let args=argv;
  if(win) {
    args=[];
    for(let i=0;i<argv.length;i++) {
      const value=argv[i];
      if(['install','status','start','stop','restart','logs','upgrade','uninstall'].includes(value))args.push('-Action',value);
      else if(['--dir','--admin','--port','--image'].includes(value)) {
        if(!argv[i+1])throw new Error(`Supply a value for ${value}.`);
        args.push('-'+value.slice(2),argv[++i]);
      } else if(value==='--purge')args.push('-Purge');
      else throw new Error(`Unknown installer argument: ${value}`);
    }
  }
  const installer=path.join(__dirname,'../install',win?'install.ps1':'install.sh');
  const result=spawnSync(win?'powershell.exe':'bash',win?['-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',installer,...args]:[installer,...args],{stdio:'inherit'});
  if(result.error){console.error(result.error.message);process.exitCode=1;}
  else process.exitCode=result.status===null?1:result.status;
}
