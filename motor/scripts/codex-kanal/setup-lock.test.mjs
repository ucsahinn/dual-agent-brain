import test from 'node:test';import assert from 'node:assert/strict';import {randomUUID} from 'node:crypto';
import {acquireSetupLock} from './setup-lock.mjs';
test('independent processes serialize setup and release on an early signal',async()=>{
 const name='Local\\Beyin-test-'+randomUUID();const first=await acquireSetupLock({name});let entered=false;
 const pending=acquireSetupLock({name}).then(lease=>{entered=true;return lease;});
 try{await new Promise(r=>setTimeout(r,700));assert.equal(entered,false);first.release();const second=await pending;second.release();assert.equal(entered,true);}finally{first.release();}
});
test('setup lease expires at its bounded deadline even without a release signal',async()=>{
 const name='Local\\Beyin-test-'+randomUUID();const first=await acquireSetupLock({name,holdMs:100});
 try{const second=await acquireSetupLock({name,waitMs:3000});second.release();}finally{first.release();}
});
