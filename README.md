# Pickup Drop

The customer-facing app for the Pickup & Drop delivery platform — built with
Flutter, backed by a shared Laravel API (the same backend the Rider App and
Admin Panel use).

A customer books a pickup/drop-off, tracks it live to a rider, and pays via
Stripe, Razorpay, or cash on delivery — all configured from the Admin Panel,
so a buyer can run the app with only the payment methods they've actually set
up.

## Modules

- **Auth** — signup, login, forgot/reset password
- **Welcome/onboarding** — admin-configured welcome screen
- **Home** — browse parcel categories, place a booking
- **Booking** — pickup/drop-off address selection, fare estimate, payment
- **Orders** — order history and detail
- **Tracking** — live order tracking
- **Notifications** — in-app + push (OneSignal)
- **Account** — profile and settings

See `project.txt` for the full module specification this app is built against.

## Requirements

- Flutter SDK ^3.12.2
- A running instance of the Pickup & Drop Laravel backend (see the backend's
  own README)

## Setup

1. Copy `.env.example` to `.env` and fill in your values:
   ```
   API_BASE_URL=http://your-backend-host/api
   GOOGLE_MAPS_API_KEY=your-google-maps-key
   APP_ENV=local
   ```
2. Install dependencies:
   ```
   flutter pub get
   ```
3. Run the app:
   ```
   flutter run
   ```

## Tech stack

Flutter, Riverpod (state management), GoRouter (navigation), Dio (networking),
flutter_secure_storage (token storage), easy_localization (i18n, incl. Arabic
RTL), Geolocator, Stripe/Razorpay (payments, both optional/admin-toggleable),
OneSignal (push notifications), image_picker.

## Configuration note

Nearly everything user-facing — categories, welcome screen content, Privacy
Policy/Terms URLs, payment methods, support contact details — is configured
from the Admin Panel, not hardcoded in this app.

## Web sürümü (izmirimexpress.com)

Aynı kod web için de derlenir ve domain kökünde yayınlanır
(`izmirimexpress.com/` → Sanayi-Express reposundaki `app/` klasörü; API
`izmirimexpress.com/admin/api`).

```
tool/build_web.sh ../sanayi-express
```

Web'e özel farklar:

- API adresi `.env` yerine sayfanın kendi domaininden alınır
  (`/admin/api`); gerekirse `--dart-define=API_BASE_URL=...` ile değişir.
- Google adres arama/rota istekleri backend'in `/maps` aracısından geçer,
  harita JS'i `/admin/api/maps/js` üzerinden panelde girilen anahtarla yüklenir.
- Stripe ve Razorpay web'de gizlenir; Paystack/Flutterwave yeni sekmede açılır.
- OneSignal push bildirimleri web'de devre dışıdır (uygulama içi bildirimler çalışır).
- Geniş ekranda uygulama telefon genişliğinde (480px) ortalanır.

Not: Android `res/` ikonları ve iOS klasörü bu repoya alınmadı; APK
derlemeden önce `flutter create --platforms=android,ios .` ve
`dart run flutter_launcher_icons` / `dart run flutter_native_splash:create`
ile yeniden üretilebilir.
