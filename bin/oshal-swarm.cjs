#!/usr/bin/env node
/**
 * CHANGE LOG
 * -----------------------------------------------------------------------------
 * SEQ                 | AUTHOR                      | DESCRIPTION
 * -----------------------------------------------------------------------------
 * 1 | maintainer@emeraldcoastsystemsgroup.com   | Initial implementation
 * 2 | maintainer@emeraldcoastsystemsgroup.com   | Forward prepare action and --owner-apps option to Windows PowerShell installer
 */
'use strict';
const path=require('node:path');
const {spawnSync}=require('node:child_process');

/**
 * Translate POSIX CLI arguments into PowerShell named parameters on Windows.
 * @description Maps positional lifecycle actions and `--flag value` pairs to `install.ps1` parameters.
 * @param {string[]} argv Raw CLI arguments after engine selection.
 * @returns {string[]} PowerShell argument vector.
 */
function translateWindowsArgs(argv) {
  const args=[];
  for(let i=0;i<argv.length;i++) {
    const value=argv[i];
    if(['install','prepare','status','start','stop','restart','logs','upgrade','uninstall'].includes(value))args.push('-Action',value);
    else if(['--dir','--admin','--port','--image','--owner-apps'].includes(value)) {
      if(!argv[i+1])throw new Error(`Supply a value for ${value}.`);
      const param=value==='--owner-apps'?'-OwnerApps':'-'+value.slice(2);
      args.push(param,argv[++i]);
    } else if(value==='--purge')args.push('-Purge');
    else throw new Error(`Unknown installer argument: ${value}`);
  }
  return args;
}

function main(rawArgv=process.argv.slice(2)) {
  const argv=[...rawArgv];
  const engine=argv[0]==='kubernetes'||argv[0]==='docker'?argv.shift():'docker';
  if(argv.includes('--help')||argv.includes('-h')) {
    console.log('Open Swarm server installer\n\n  npx oswarm docker        Install Swarm with Docker\n  npx oswarm kubernetes    Install a dedicated local Kubernetes Swarm\n\nLater: add status, start, stop, restart or logs.\nUse --dir <folder> to select an installation. Kubernetes open keeps your local connection open.\nOrbit, the companion for a computer you want to control, is a separate download.');
    return;
  }
  if(engine==='kubernetes') {
    require('../install/kubernetes/installer.cjs').main(argv).catch(error=>{console.error(error.message);process.exitCode=1;});
    return;
  }
  const win=process.platform==='win32';
  const args=win?translateWindowsArgs(argv):argv;
  const installer=path.join(__dirname,'../install',win?'install.ps1':'install.sh');
  const result=spawnSync(win?'powershell.exe':'bash',win?['-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',installer,...args]:[installer,...args],{stdio:'inherit'});
  if(result.error){console.error(result.error.message);process.exitCode=1;}
  else process.exitCode=result.status===null?1:result.status;
}

module.exports={translateWindowsArgs,main};
if(require.main===module)main();
