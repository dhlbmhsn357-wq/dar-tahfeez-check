/* ============================================
   Service Worker - دار الأرقم
   يخزن الصفحة الرئيسية محلياً بحيث تفتح
   حتى بدون اتصال بالإنترنت بعد أول زيارة.
   ============================================ */
const CACHE_NAME = 'dar-alarqam-cache-v1';
const APP_SHELL = [
  './',
  './index.html'
];

// عند التثبيت: تخزين الصفحة الرئيسية في الكاش
self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(APP_SHELL).catch(() => {
        // في حال فشل تخزين أحد الملفات، لا نوقف التثبيت بالكامل
      });
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

// عند كل طلب: نحاول نجيب من النت أولاً، ولو فشل (أوفلاين) نرجع للكاش
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  event.respondWith(
    fetch(event.request)
      .then((networkResponse) => {
        // نحدث الكاش بأحدث نسخة كل مرة يكون فيها نت
        const clone = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return networkResponse;
      })
      .catch(() => {
        // مفيش نت: نرجع النسخة المخزنة، ولو مش موجودة نرجع الصفحة الرئيسية
        return caches.match(event.request).then((cached) => {
          return cached || caches.match('./index.html');
        });
      })
  );
});
