#!/bin/bash

# Скрипт для обновления версии Flutter приложения
# Использование:
# ./update_version.sh patch   -> увеличивает patch
# ./update_version.sh minor   -> увеличивает minor
# ./update_version.sh major   -> увеличивает major
# Если не указан аргумент, по умолчанию увеличивается patch

PUBSPEC_FILE="pubspec.yaml"

# Проверка аргумента
UPDATE_TYPE=${1:-patch}
if [[ ! "$UPDATE_TYPE" =~ ^(major|minor|patch)$ ]]; then
    echo "Неверный аргумент: $UPDATE_TYPE"
    echo "Использование: ./update_version.sh [major|minor|patch]"
    exit 1
fi

# Получаем текущую версию и build number
CURRENT_VERSION=$(grep "^version:" $PUBSPEC_FILE | awk '{print $2}')
APP_VERSION=${CURRENT_VERSION%%+*}   # 1.2.3
BUILD_NUMBER=${CURRENT_VERSION##*+}  # 4

# Разбиваем на части
IFS='.' read -r MAJOR MINOR PATCH <<< "$APP_VERSION"

# Увеличиваем нужную часть версии
case $UPDATE_TYPE in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
esac

# Увеличиваем build number
BUILD_NUMBER=$((BUILD_NUMBER + 1))

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}+${BUILD_NUMBER}"
echo "Обновляем версию с $CURRENT_VERSION на $NEW_VERSION"

# Обновляем pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VERSION/" $PUBSPEC_FILE

# Обновляем зависимости
flutter pub get

# Пересборка приложения
flutter clean
flutter build apk --release   # Android
# flutter build ios --release  # iOS на macOS

# --- ДЕПЛОЙ НА СЕРВЕР ---
SSH_TARGET="eom1"
REMOTE_DIR="/home/eom/eom_backendl/uploads/app"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

echo "🚀 Отправка APK на сервер $SSH_TARGET..."
if [ -f "$APK_PATH" ]; then
    # Создаем директорию на сервере если ее вдруг нет
    ssh "$SSH_TARGET" "mkdir -p $REMOTE_DIR"
    
    # Отправляем сам файл APK
    scp "$APK_PATH" "$SSH_TARGET:$REMOTE_DIR/app-release.apk"
    
    # Обновляем version.txt на сервере
    ssh "$SSH_TARGET" "echo -n '$NEW_VERSION' > $REMOTE_DIR/version.txt"
    
    echo "✅ APK успешно загружен на сервер!"
    echo "🌐 Ссылка: https://start.eom.kz/uploads/app/app-release.apk"
else
    echo "❌ Ошибка: Сборка провалилась, файл APK не найден ($APK_PATH)"
    exit 1
fi
# ------------------------

# Создаём git tag для версии
git add $PUBSPEC_FILE
git commit -m "Обновление версии до $NEW_VERSION"
git tag "v$NEW_VERSION"
git push origin --tags

echo "Сборка и деплой завершены. Новая версия: $NEW_VERSION"
