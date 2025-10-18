#!/bin/bash

# Путь к собранному APK (может отличаться)
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

# Проверяем, существует ли файл
if [ ! -f "$APK_PATH" ]; then
  echo "❌ APK не найден: $APK_PATH"
  exit 1
fi

# Загружаем на сервер
echo "📤 Загружаю APK на сервер..."
scp "$APK_PATH" root@start.eom.kz:/root/eom/uploads/app/app-release.apk

if [ $? -eq 0 ]; then
  echo "✅ Успешно загружено: https://start.eom.kz/uploads/app/app-release.apk"
else
  echo "❌ Ошибка при загрузке"
  exit 1
fi