#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

BUILD_DIR="$DIR/build"
APP_NAME="Yasno.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
WIDGET_APPEX="$PLUGINS_DIR/YasnoWidgetExtension.appex"
WIDGET_CONTENTS="$WIDGET_APPEX/Contents"
WIDGET_MACOS="$WIDGET_CONTENTS/MacOS"

echo "🛑 Зупиняємо попередні процеси Yasno..."
killall YasnoWidget 2>/dev/null || true

echo "🧹 Очищуємо попередню збірку..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$WIDGET_MACOS" /tmp/clang-cache

echo "⚙️ Компілюємо основний застосунок..."
CORE_SOURCES=(
    "Sources/YasnoCore/YasnoModels.swift"
    "Sources/YasnoCore/ScheduleCalculator.swift"
    "Sources/YasnoCore/YasnoAPIService.swift"
    "Sources/YasnoCore/LiveMonitorService.swift"
    "Sources/YasnoCore/ScheduleManager.swift"
    "Sources/Views/StatusBadgeView.swift"
    "Sources/Views/DailyTimelineBarView.swift"
    "Sources/Views/ScheduleSlotsListView.swift"
    "Sources/Views/SettingsView.swift"
    "Sources/Views/DesktopWidgetView.swift"
    "Sources/App/DesktopWidgetController.swift"
    "Sources/App/AppDelegate.swift"
    "Sources/App/YasnoApp.swift"
)

swiftc -module-cache-path /tmp/clang-cache \
       -parse-as-library \
       -O \
       "${CORE_SOURCES[@]}" \
       -o "$MACOS_DIR/YasnoWidget"

echo "⚙️ Компілюємо розширення WidgetKit..."
WIDGET_SOURCES=(
    "Sources/YasnoCore/YasnoModels.swift"
    "Sources/YasnoCore/ScheduleCalculator.swift"
    "Sources/YasnoCore/YasnoAPIService.swift"
    "Sources/YasnoCore/LiveMonitorService.swift"
    "Sources/Views/StatusBadgeView.swift"
    "Sources/Views/DailyTimelineBarView.swift"
    "Sources/Views/ScheduleSlotsListView.swift"
    "Sources/WidgetExtension/YasnoWidgetExtension.swift"
)

swiftc -module-cache-path /tmp/clang-cache \
       -application-extension \
       -Xlinker -e -Xlinker _NSExtensionMain \
       -parse-as-library \
       -O \
       "${WIDGET_SOURCES[@]}" \
       -o "$WIDGET_MACOS/YasnoWidgetExtension"

echo "📦 Формуємо пакет програми (App Bundle)..."
cp Resources/Info.plist "$CONTENTS_DIR/Info.plist"
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"
cp Resources/WidgetInfo.plist "$WIDGET_CONTENTS/Info.plist"

echo "🔐 Підписуємо програму (Ad-hoc Code Signing)..."
codesign -f -s - --entitlements Resources/Widget.entitlements "$WIDGET_APPEX" 2>/dev/null || true
codesign -f -s - --entitlements Resources/App.entitlements "$APP_DIR" 2>/dev/null || true

USER_APPS="$HOME/Applications"
mkdir -p "$USER_APPS"

if [ -w "/Applications" ]; then
    TARGET_APP="/Applications/Yasno.app"
    rm -rf "/Applications/Yasno.app" "$USER_APPS/Yasno.app" 2>/dev/null || true
    cp -R "$APP_DIR" "$TARGET_APP"
else
    TARGET_APP="$USER_APPS/Yasno.app"
    rm -rf "$TARGET_APP" 2>/dev/null || true
    cp -R "$APP_DIR" "$TARGET_APP"
fi

echo "🔌 Реєструємо програму та віджет у macOS..."
xattr -cr "$TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET_APP" 2>/dev/null || true
pluginkit -a "$TARGET_APP/Contents/PlugIns/YasnoWidgetExtension.appex" 2>/dev/null || true
killall chronod 2>/dev/null || true

echo "🚀 Запускаємо Yasno..."
open "$TARGET_APP"

echo ""
echo "✅ Встановлення та запуск успішно завершено! ($TARGET_APP)"
