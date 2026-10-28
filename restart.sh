#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ -d "/Applications/Yasno.app" ]; then
    TARGET_APP="/Applications/Yasno.app"
elif [ -d "$HOME/Applications/Yasno.app" ]; then
    TARGET_APP="$HOME/Applications/Yasno.app"
elif [ -d "$DIR/build/Yasno.app" ]; then
    TARGET_APP="$DIR/build/Yasno.app"
else
    echo "⚙️ Програму ще не встановлено, запускаємо install.sh..."
    exec "$DIR/install.sh"
fi

echo "🛑 Перезапускаємо Yasno..."
killall YasnoWidget 2>/dev/null || true
sleep 0.5

if [ -d "$DIR/build/Yasno.app" ] && [ "$TARGET_APP" != "$DIR/build/Yasno.app" ]; then
    rm -rf "$TARGET_APP" 2>/dev/null || true
    cp -R "$DIR/build/Yasno.app" "$TARGET_APP" 2>/dev/null || true
fi

xattr -cr "$TARGET_APP" 2>/dev/null || true
pluginkit -a "$TARGET_APP/Contents/PlugIns/YasnoWidgetExtension.appex" 2>/dev/null || true
killall chronod 2>/dev/null || true

open "$TARGET_APP"
echo "✅ Yasno перезапущено!"
