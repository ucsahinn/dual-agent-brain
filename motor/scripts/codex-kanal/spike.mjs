export function loopbackEndpoint(value) {
  const u=new URL(value);
  if(u.protocol!=='ws:'||u.hostname!=='127.0.0.1'||!u.port||u.username||u.password||u.search||u.hash||u.pathname!=='/') throw new Error('Only ws://127.0.0.1:PORT is permitted');
  return u.href;
}
export function messagingAvailability(env=process.env){
  return env.CLAUDE_CODE_MESSAGING_SOCKET && env.CLAUDE_CODE_MESSAGING_TOKEN
    ? {available:true,result:'requires-chief-smoke'} : {available:false,result:'denenemedi'};
}
