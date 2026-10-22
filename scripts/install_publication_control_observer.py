#!/usr/bin/env python3
"""Install the local, event-driven report bridge used by Publication Control."""
import argparse,os,plistlib,shutil,subprocess
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--install',action='store_true');args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
node=shutil.which('node')
if not node:raise SystemExit('Node.js is required')
label='com.serlest.uac.publication-control'
folder=Path.home()/'Library/LaunchAgents';log=root/'build/publication-control-observer';log.mkdir(parents=True,exist_ok=True)
source={'Label':label,'ProgramArguments':[node,str(root/'functions/scripts/publicationControlSync.mjs'),'--watch'],
 'WorkingDirectory':str(root),'RunAtLoad':True,'KeepAlive':True,'ThrottleInterval':60,
 'EnvironmentVariables':{'PATH':str(Path(node).parent)+':/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin'},
 'StandardOutPath':str(log/'observer.log'),'StandardErrorPath':str(log/'observer-error.log')}
if not args.install:print(plistlib.dumps(source).decode());raise SystemExit()
folder.mkdir(parents=True,exist_ok=True);target=folder/(label+'.plist');target.write_bytes(plistlib.dumps(source));target.chmod(0o600)
domain=f'gui/{os.getuid()}'
subprocess.run(['launchctl','bootout',domain+'/'+label],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['launchctl','bootstrap',domain,str(target)],check=True)
print(f'Installed {label}: filesystem events, no model calls or publication writes.')
