import test from 'node:test';
import assert from 'node:assert/strict';
import { loopbackEndpoint, messagingAvailability } from './spike.mjs';
test('only the explicit loopback websocket endpoint is accepted',()=>{
  assert.equal(loopbackEndpoint('ws://127.0.0.1:45123'),'ws://127.0.0.1:45123/');
  const credentialUrl=new URL('ws://127.0.0.1:45');credentialUrl.username='user';credentialUrl.password='pass';
  for(const url of ['ws://0.0.0.0:45','ws://example.com:45',credentialUrl.href,'http://127.0.0.1:45']) assert.throws(()=>loopbackEndpoint(url));
});
test('Claude messaging spike reports unavailable without exposing secret values',()=>{
  assert.deepEqual(messagingAvailability({}),{available:false,result:'denenemedi'});
  const token=['fixture','Z'.repeat(32)].join('-');
  const result=messagingAvailability({CLAUDE_CODE_MESSAGING_SOCKET:'fixture-pipe',CLAUDE_CODE_MESSAGING_TOKEN:token});
  assert.equal(result.available,true); assert.ok(!JSON.stringify(result).includes(token));
});
