// YO'LDA service worker — ilovani o'rnatish uchun kerak. HECH NARSANI KESHLAMAYDI:
// har doim eng yangi versiya serverdan olinadi, shuning uchun eskirgan versiyada qolib ketish xavfi yo'q.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {}); // so'rovlar odatdagidek tarmoq orqali ketadi
