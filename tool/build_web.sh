#!/usr/bin/env bash
# Web sürümünü derler ve Sanayi-Express reposunun app/ klasörüne kopyalar.
# Kullanım: tool/build_web.sh ../sanayi-express
set -euo pipefail

target="${1:?Sanayi-Express reposunun yolunu verin, örn: tool/build_web.sh ../sanayi-express}"
cd "$(dirname "$0")/.."

# pubspec .env dosyasını asset olarak istediği için derlemede bulunmalı;
# web sürümü onu okumaz (bkz. lib/config/env.dart).
[ -f .env ] || cp .env.example .env

# --wasm: tarayıcı destekliyorsa daha hızlı WebAssembly sürümü (skwasm)
# yüklenir, desteklemiyorsa otomatik olarak JavaScript sürümüne düşer.
flutter build web --release --wasm --base-href /app/

# .env yayına gitmesin.
rm -f build/web/assets/.env

rm -rf "$target/app"
cp -r build/web "$target/app"

# Dosya adları her derlemede aynı kaldığı için tarayıcı her açılışta güncel
# mi diye sorsun; .wasm ve .mjs türleri de tanıtılsın.
cat > "$target/app/.htaccess" <<'HTACCESS'
AddType application/wasm .wasm
AddType text/javascript .mjs

<IfModule mod_headers.c>
    # Her dosya (simge yazı tipi, logolar dahil) her açılışta güncel mi diye
    # sorulsun: adları derlemeden derlemeye değişmediği için aksi halde
    # tarayıcı eski logoyu / yeni simgeleri içermeyen eski yazı tipini
    # önbellekten göstermeye devam ediyordu. Değişmeyen dosyalar için cevap
    # kısa bir "304 Not Modified" olur.
    Header set Cache-Control "no-cache"
    # sw.js (uygulama yükleme) /app/ yerine tüm siteyi kapsayabilsin.
    <Files "sw.js">
        Header set Service-Worker-Allowed "/"
    </Files>
    # Cross-origin isolation: lets Flutter draw on a background thread
    # (multi-threaded skwasm) instead of the page's main thread, which is
    # what made scrolling stutter on phones. "credentialless" still loads
    # Google Maps and other cross-origin images/scripts, just without
    # cookies. The root .htaccess sends the same pair for "/".
    Header set Cross-Origin-Opener-Policy "same-origin"
    Header set Cross-Origin-Embedder-Policy "credentialless"
</IfModule>
HTACCESS
echo "Web sürümü $target/app klasörüne kopyalandı."
