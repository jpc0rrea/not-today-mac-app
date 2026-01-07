#!/bin/bash
#
# NotToday Uninstallation Script
#
# This script removes NotToday and all its components

set -e

APP_SUPPORT_DIR="$HOME/Library/Application Support/NotToday"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$LAUNCH_AGENTS_DIR/com.nottoday.scheduler.plist"

echo "========================================"
echo "  NotToday Uninstallation"
echo "========================================"
echo ""

# First, deactivate any active blocking
echo "Removing any active blocking from hosts file..."
sudo sed -i '' '/# NotToday START/,/# NotToday END/d' /etc/hosts 2>/dev/null || true
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

# Unload LaunchAgent
if [ -f "$PLIST_FILE" ]; then
    echo "Unloading LaunchAgent..."
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm -f "$PLIST_FILE"
fi

# Remove symlink
if [ -L "/usr/local/bin/nottoday" ]; then
    echo "Removing symlink..."
    sudo rm -f /usr/local/bin/nottoday
fi

# Ask about config
echo ""
read -p "Do you want to remove your configuration and blocked sites list? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing application support directory..."
    rm -rf "$APP_SUPPORT_DIR"
else
    echo "Keeping configuration at: $APP_SUPPORT_DIR"
fi

# Remove log files
rm -f /tmp/nottoday.log /tmp/nottoday.error.log 2>/dev/null || true

echo ""
echo "========================================"
echo "  Uninstallation Complete!"
echo "========================================"
echo ""
echo "NotToday has been removed from your system."
echo "If you built the GUI app, please remove it from /Applications manually."
echo ""
