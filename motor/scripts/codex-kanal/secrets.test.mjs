import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {redact,atomicJson,ChannelHost,validHandoff} from './host-service.mjs';
test('secret strings, Bearer headers and private keys never reach snapshots',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-secret-')),file=path.join(dir,'record.json');
 const secret=['unpatterned','Q'.repeat(24)].join('-'),api='sk-'+ 'B'.repeat(32);
 const pem=boundary=>['-----',boundary,' PRIVATE KEY','-----'].join('');
 const privateKey=[pem('BEGIN'),'fixture-data',pem('END')].join('\n');
 try{
  atomicJson(file,{token:secret,answer:'Authorization: Bearer '+secret,api,privateKey},[secret]);
  const raw=fs.readFileSync(file,'utf8');for(const value of [secret,api,'fixture-data'])assert.ok(!raw.includes(value));assert.doesNotThrow(()=>JSON.parse(raw));
  assert.ok(!redact('Authorization: Bearer '+secret).includes(secret));
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test('a remembered ephemeral WS token is filtered from all host outputs',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-known-secret-')),id='CK-'+'b'.repeat(32),secret='opaque-'+ 'R'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0}));
 try{const host=new ChannelHost({state:root,id,owner:'owner'});host.rememberSecret(secret);host.record.Answer=secret;host.event('fixture',{detail:secret});const strings=[fs.readFileSync(host.file,'utf8'),fs.readFileSync(path.join(host.directory,'events.jsonl'),'utf8')];assert.equal(strings.filter(s=>s.includes(secret)).length,0);}finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('empty duplicate or reordered handoff fields fail closed',()=>{
 const good='Outcome: ok\nEvidence: proof\nChanged scope: none\nRisks: none\nOpen questions: none\nNext verification: none';
 assert.equal(validHandoff(good),true);assert.equal(validHandoff(good.replace('Risks: none','Risks:')),false);assert.equal(validHandoff(good+'\nOutcome: duplicate'),false);
});
