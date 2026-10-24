# İzmirim Kurye

İzmirim Express'in kurye (Android) uygulaması. Flutter ile yazıldı ve müşteri
uygulamasıyla aynı Laravel backend'ini kullanır
(`https://izmirimexpress.com/admin/api`, `/rider/*` uçları).

## Test APK'sı

`rider/` altında yapılan her değişiklik GitHub Actions'ta otomatik derlenir
(`.github/workflows/rider-apk.yml`) ve son sürüm hep aynı linkte olur:

https://github.com/narinalbayrak90-alt/izmirimexpress/releases/latest/download/izmirim-kurye.apk

Telefondaki uygulama açılışta yeni sürüm olup olmadığına bakar ve varsa
"Yeni sürüm var" diye sorar; tekrar link aramaya gerek kalmaz.

## Yerelde çalıştırma

```
cp .env.example .env   # API_BASE_URL=https://izmirimexpress.com/admin/api
flutter pub get
flutter run
```

## İmza anahtarı

Test sürümleri repodaki `android/signing/test-release.jks` ile imzalanır, sadece
sürümlerin birbirinin üstüne kurulabilmesi için. Kuryelere dağıtmadan önce
gerçek bir anahtar oluşturulup repo secret'larına (`RIDER_KEYSTORE_BASE64`,
`RIDER_KEYSTORE_PASSWORD`, `RIDER_KEY_ALIAS`) eklenmeli; workflow o varsa onu
kullanır.

## Logo ve açılış ekranı

`assets/icon.png` ve `assets/splash.png` değişince:

```
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
