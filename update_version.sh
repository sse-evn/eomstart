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

# Создаём git tag для версии
git add $PUBSPEC_FILE
git commit -m "Обновление версии до $NEW_VERSION"
git tag "v$NEW_VERSION"
git push origin --tags

echo "Сборка завершена. Новая версия: $NEW_VERSION"
