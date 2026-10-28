import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {fileURLToPath} from 'node:url';import {ChannelHost} from './host-service.mjs';
for(const choice of ['catalog','review','none','same-catalog','always','combined','tool-text'])test('model_not_found fallback: '+choice,async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'beyin-model-')),id='CK-'+'c'.repeat(32);
 fs.writeFileSync(path.join(root,id+'.json'),JSON.stringify({Owner:'beyin-codex-kanal-v1',Id:id,OwnerSession:'owner',Project:root,Turn:0,RoleModel:'unsupported-model',CatalogModel:choice==='catalog'?'catalog-model':choice==='same-catalog'?'unsupported-model':'',ReviewModel:choice==='none'?'':'review-model'}));
 const mode=choice==='always'?'model-always':choice==='combined'?'model-then-sandbox':choice==='tool-text'?'tool-model-text':'model';
 const host=new ChannelHost({state:root,id,owner:'owner',command:process.execPath,args:[fileURLToPath(new URL('./fixtures/fallback-server.mjs',import.meta.url)),mode],timeout:1000,sleep:async()=>{}});
 try{await host.start();const r=await host.dispatch({owner:'owner',method:'sor',text:'task'});
  if(choice==='none'){assert.equal(r.Status,'failed');assert.equal(r.Attempts,1);assert.match(r.Error,/review_model|catalog/i);}
  else if(choice==='tool-text'){assert.equal(r.Status,'failed');assert.equal(r.Attempts,1);assert.ok(!r.ModelFallback);}
  else{assert.equal(r.Attempts,2);assert.equal(r.ModelFallback.from,'unsupported-model');assert.equal(r.ModelFallback.to,choice==='catalog'?'catalog-model':'review-model');assert.equal(r.ModelFallback.reason,'model_not_found');assert.equal(r.Status,choice==='always'?'failed':'completed');if(choice==='combined'){assert.ok(!r.SandboxFallback);assert.equal(r.RetryCount,1);}}
 }finally{await host.close();fs.rmSync(root,{recursive:true,force:true});}
});
