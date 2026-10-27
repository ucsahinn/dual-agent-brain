import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {atomicJson} from './host-service.mjs';
test('atomic record replacement preserves the previous value through transient Windows sharing failures',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-atomic-')),file=path.join(root,'record.json');fs.writeFileSync(file,'{"old":true}');let tries=0;
 const io={writeFileSync:fs.writeFileSync,unlinkSync:fs.unlinkSync,renameSync:(from,to)=>{tries++;if(tries<3){assert.deepEqual(JSON.parse(fs.readFileSync(file)),{old:true});const e=new Error('sharing violation');e.code='EPERM';throw e;}fs.renameSync(from,to);}};
 try{atomicJson(file,{new:true},[],io);assert.equal(tries,3);assert.deepEqual(JSON.parse(fs.readFileSync(file)),{new:true});}finally{fs.rmSync(root,{recursive:true,force:true});}
});
