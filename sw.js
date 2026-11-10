/* Service worker mínimo: permite instalar o app e abrir a última versão da página sem internet.
   Os dados (pedidos, preços etc.) vêm sempre do Supabase e nunca são guardados aqui. */
const V = 'lavajato-v1';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});
self.addEventListener('fetch', e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== 'GET' || u.origin !== location.origin || r.mode !== 'navigate') return;
  e.respondWith(
    fetch(r).then(res => {
      const copia = res.clone();
      caches.open(V).then(c => c.put(self.registration.scope, copia)).catch(() => {});
      return res;
    }).catch(() => caches.match(self.registration.scope).then(x => x || Response.error()))
  );
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const alvo = new URL('./#admin', self.registration.scope).href;
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(l => {
      for (const c of l) if ('focus' in c) return c.focus();
      return self.clients.openWindow(alvo);
    })
  );
});
