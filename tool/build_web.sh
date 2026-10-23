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

# main.dart.js gibi dosyaların adı her derlemede aynı kaldığı için tarayıcı
# her açılışta güncel mi diye sorsun; .wasm ve .mjs türleri de tanıtılsın.
cat > "$target/app/.htaccess" <<'HTACCESS'
AddType application/wasm .wasm
AddType text/javascript .mjs

<IfModule mod_headers.c>
    <FilesMatch "\.(html|js|mjs|json|wasm)$">
        Header set Cache-Control "no-cache"
    </FilesMatch>
</IfModule>
HTACCESS
echo "Web sürümü $target/app klasörüne kopyalandı."
