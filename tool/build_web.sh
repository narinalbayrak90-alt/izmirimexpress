#!/usr/bin/env bash
# Web sürümünü derler ve Sanayi-Express reposunun app/ klasörüne kopyalar.
# Kullanım: tool/build_web.sh ../sanayi-express
set -euo pipefail

target="${1:?Sanayi-Express reposunun yolunu verin, örn: tool/build_web.sh ../sanayi-express}"
cd "$(dirname "$0")/.."

# pubspec .env dosyasını asset olarak istediği için derlemede bulunmalı;
# web sürümü onu okumaz (bkz. lib/config/env.dart).
[ -f .env ] || cp .env.example .env

flutter build web --release --base-href /app/ --no-wasm-dry-run

# .env yayına gitmesin.
rm -f build/web/assets/.env

rm -rf "$target/app"
cp -r build/web "$target/app"
echo "Web sürümü $target/app klasörüne kopyalandı."
