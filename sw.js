// Keeps a copy of the website so it opens offline. Network first, so an online visit always gets the
// latest build; the copy is only used when the network fails. The data itself is in localStorage.
const CACHE = 'nobudget';
const cacheable = (url) =>
  url.startsWith(self.registration.scope) ||
  url.startsWith('https://www.gstatic.com/firebasejs/') || // Firebase's web SDK, loaded at start
  url.startsWith('https://fonts.gstatic.com/'); // fallback fonts for characters the app's fonts lack

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET' || !cacheable(e.request.url)) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          e.waitUntil(caches.open(CACHE).then((c) => c.put(e.request, copy)));
        }
        return res;
      })
      .catch(() => caches.match(e.request, { ignoreSearch: true }).then((hit) => hit || Response.error())),
  );
});

// On the first visit the page loads before this worker is in charge; the page then lists what it loaded.
self.addEventListener('message', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      Promise.all(
        e.data.filter(cacheable).map((url) => c.match(url).then((hit) => hit || c.add(url)).catch(() => {})),
      ),
    ),
  );
});
