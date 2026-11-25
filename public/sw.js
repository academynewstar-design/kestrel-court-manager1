self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
  for(const key of await caches.keys()) if(key.startsWith('kestrel-court-manager-')) await caches.delete(key);
  await self.clients.claim();
})()));
self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET'||new URL(request.url).origin!==self.location.origin)return;
  if(request.mode==='navigate'||request.destination==='document'){
    event.respondWith(fetch(request,{cache:'no-store'}));
  }
});
