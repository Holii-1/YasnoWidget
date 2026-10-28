#!/bin/bash

echo "🛑 Зупиняємо процеси Yasno..."
pkill -f "YasnoWidget" 2>/dev/null || true
pkill -f "Yasno.app" 2>/dev/null || true

echo "🔌 Знімаємо з реєстрації розширення WidgetKit..."
USER_APPS="$HOME/Applications"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pluginkit -r "/Applications/Yasno.app/Contents/PlugIns/YasnoWidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$USER_APPS/Yasno.app/Contents/PlugIns/YasnoWidgetExtension.appex" 2>/dev/null || true
pluginkit -r "$DIR/build/Yasno.app/Contents/PlugIns/YasnoWidgetExtension.appex" 2>/dev/null || true

echo "🗑 Видаляємо встановлену програму та білди..."
rm -rf "/Applications/Yasno.app" "$USER_APPS/Yasno.app" "$DIR/build"

echo "🧹 Очищуємо налаштування користувача та системний кеш..."
defaults delete ua.yasno.mac.widget 2>/dev/null || true
defaults delete group.ua.yasno.mac.widget 2>/dev/null || true
rm -rf "$HOME/Library/Containers/ua.yasno.mac.widget"* 2>/dev/null || true
rm -rf "$HOME/Library/Group Containers/group.ua.yasno.mac.widget"* 2>/dev/null || true
rm -rf "$HOME/Library/Preferences/ua.yasno.mac.widget"* 2>/dev/null || true
rm -rf "$HOME/Library/Preferences/group.ua.yasno.mac.widget"* 2>/dev/null || true
rm -f /private/tmp/yasno_* /tmp/yasno_* 2>/dev/null || true
killall cfpreferencesd 2>/dev/null || true
killall chronod 2>/dev/null || true

echo "✅ Програму Yasno та всі налаштування повністю видалено!"
