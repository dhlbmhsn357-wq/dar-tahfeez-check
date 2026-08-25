/* ============================================
   Service Worker - دار الأرقم
   يخزن الصفحة الرئيسية محلياً بحيث تفتح
   حتى بدون اتصال بالإنترنت بعد أول زيارة.

   مهم: لا نتدخل إطلاقاً في طلبات Supabase أو أي API،
   حتى لا نُرجع بيانات قديمة مخزّنة بدل البيانات الحية.
   ============================================ */
const CACHE_NAME = 'dar-alarqam-cache-v2';
const APP_SHELL = [
  './',
  './index.html'
];

// عند التثبيت: تخزين الصفحة الرئيسية في الكاش
self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(APP_SHELL).catch(() => {});
    })
  );
});

// عند التفعيل: حذف أي نسخ كاش قديمة
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);

  // لا نتدخل نهائياً في طلبات البيانات الحية (Supabase / أي API خارجي).
  // نتركها تمر مباشرة للشبكة بدون أي تخزين، حتى لا تُعرض بيانات قديمة أبداً.
  const isApi =
    url.hostname.endsWith('.supabase.co') ||
    url.hostname.endsWith('.supabase.in') ||
    url.pathname.includes('/rest/') ||
    url.pathname.includes('/auth/') ||
    url.pathname.includes('/realtime/');
  if (isApi) return; // نترك المتصفح يتعامل معه طبيعياً بدون كاش

  // نخزّن ونخدم فقط ملفات التطبيق نفسه (نفس الأصل)
  if (url.origin !== self.location.origin) return;

  // استراتيجية network-first لملفات التطبيق: أحدث نسخة أولاً، والكاش احتياط للأوفلاين
  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        const clone = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return networkResponse;
      })
      .catch(() => {
        return caches.match(event.request).then((cached) => {
          return cached || caches.match('./index.html');
        });
      })
  );
});
