import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {Supervisor,Ledger} from './supervisor.mjs';
test('fake clock yields one nudge then one stall, and budget blocks nudges',()=>{
 const s=new Supervisor({nudgeMs:100,stallMs:200});
 assert.equal(s.tick(0,50,true,false),'none');assert.equal(s.tick(0,101,true,false),'nudge');assert.equal(s.tick(0,120,true,false),'none');assert.equal(s.tick(0,201,true,false),'stall');assert.equal(s.tick(0,250,true,false),'none');
 assert.equal(new Supervisor({nudgeMs:100,stallMs:200}).tick(0,150,true,true),'none');
});
test('ledger deduplicates completion and recovers a corrupt primary snapshot',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-ledger-')),file=path.join(dir,'ledger.json');
 try{const l=new Ledger(file);assert.equal(l.add('turn-1-complete','completed',1),true);assert.equal(l.add('turn-1-complete','completed',1),false);l.add('turn-2-start','running',2);fs.writeFileSync(file,'{broken');const recovered=new Ledger(file);assert.ok(recovered.events.length>=1);assert.equal(recovered.recovered,true);}finally{fs.rmSync(dir,{recursive:true,force:true});}
});
