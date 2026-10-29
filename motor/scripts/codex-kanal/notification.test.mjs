import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {ChannelHost} from './host-service.mjs';

test('notifications follow the channel state vault despite stale launch and ambient destinations',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-notification-'));
 const realVault=fileURLToPath(new URL('../../..',import.meta.url));
 const realHandoff=path.join(realVault,'motor/scripts/.state/handoff');
 const inventory=dir=>fs.existsSync(dir)?fs.readdirSync(dir).filter(n=>n.endsWith('.json')).sort():[];
 const before=inventory(realHandoff),ambient=process.env.BEYIN_VAULT;
 try{
  const vault=path.join(root,'channel-vault'),foreign=path.join(root,'foreign-vault');
  const handoff=path.join(vault,'motor/scripts/.state/handoff');
  const foreignHandoff=path.join(foreign,'motor/scripts/.state/handoff');
  fs.mkdirSync(foreignHandoff,{recursive:true});
  fs.writeFileSync(path.join(foreignHandoff,'sentinel.json'),'{}');
  process.env.BEYIN_VAULT=foreign;
  for(const engine of ['codex','claude']){
   const state=path.join(vault,'motor/scripts/.state',engine+'-kanal');
   const id='CK-'+(engine==='codex'?'a':'b').repeat(32);
   fs.mkdirSync(state,{recursive:true});
   fs.writeFileSync(path.join(state,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:vault,Turn:1,Engine:engine}));
   // A stale launch destination is a canary, never the user's actual inbox.
   const host=new ChannelHost({state,id,owner:'fixture',vault:foreign,handoffDirectory:foreignHandoff});
   host.notify('completed');host.notify('completed');
  }
  assert.deepEqual(inventory(foreignHandoff),['sentinel.json']);
  assert.equal(inventory(handoff).length,2);
  for(const name of inventory(handoff))assert.match(JSON.parse(fs.readFileSync(path.join(handoff,name),'utf8')).question,/completed/);
  assert.deepEqual(inventory(realHandoff),before,'real vault inbox must remain unchanged');
 }finally{
  if(ambient===undefined)delete process.env.BEYIN_VAULT;else process.env.BEYIN_VAULT=ambient;
  fs.rmSync(root,{recursive:true,force:true});
 }
});

test('standalone state refuses a notification path outside its owned directory',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-notification-boundary-'));
 try{
  const state=path.join(root,'state'),outside=path.join(root,'outside');
  const id='CK-'+'c'.repeat(32);
  fs.mkdirSync(state);
  fs.writeFileSync(path.join(state,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'fixture',Project:root,Turn:1}));
  const host=new ChannelHost({state,id,owner:'fixture',handoffDirectory:outside});
  host.notify('completed');
  assert.equal(fs.existsSync(outside),false);
  assert.match(host.record.Warnings[0],/delivery refused/);
  // Refusing the foreign path must not consume the delivery marker.
  host.cfg.handoffDirectory=path.join(state,'notices');
  host.notify('completed');
  assert.equal(fs.readdirSync(host.cfg.handoffDirectory).length,1);
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});
