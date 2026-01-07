#!/bin/bash
#
# NotToday Installation Script
#
# This script sets up the CLI tool and LaunchAgent for automatic scheduling.
# The GUI app should be built separately using Xcode.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/NotToday"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

echo "========================================"
echo "  NotToday Installation"
echo "========================================"
echo ""

# Create app support directory
echo "Creating application support directory..."
mkdir -p "$APP_SUPPORT_DIR"

# Copy CLI script
echo "Installing CLI tool..."
cp "$SCRIPT_DIR/nottoday-cli.sh" "$APP_SUPPORT_DIR/"
chmod +x "$APP_SUPPORT_DIR/nottoday-cli.sh"

# Create symlink in /usr/local/bin for easy access
if [ -d "/usr/local/bin" ]; then
    echo "Creating symlink in /usr/local/bin..."
    sudo ln -sf "$APP_SUPPORT_DIR/nottoday-cli.sh" /usr/local/bin/nottoday
    echo "  You can now use 'nottoday' command from anywhere"
fi

# Create default config if it doesn't exist
if [ ! -f "$APP_SUPPORT_DIR/config.json" ]; then
    echo "Creating default configuration..."
    cat > "$APP_SUPPORT_DIR/config.json" << 'EOF'
{
  "enabled": true,
  "blockedSites": [
    "twitter.com",
    "www.twitter.com",
    "x.com",
    "www.x.com",
    "facebook.com",
    "www.facebook.com",
    "instagram.com",
    "www.instagram.com",
    "reddit.com",
    "www.reddit.com",
    "youtube.com",
    "www.youtube.com",
    "tiktok.com",
    "www.tiktok.com",
    "netflix.com",
    "www.netflix.com"
  ],
  "schedule": {
    "days": ["monday", "tuesday", "wednesday", "thursday", "friday"],
    "startHour": 9,
    "startMinute": 0,
    "endHour": 19,
    "endMinute": 0
  }
}
EOF
fi

# Install LaunchAgent for automatic scheduling
echo "Installing LaunchAgent for automatic scheduling..."
mkdir -p "$LAUNCH_AGENTS_DIR"

# Update the plist to use the correct path
cat > "$LAUNCH_AGENTS_DIR/com.nottoday.scheduler.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nottoday.scheduler</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_SUPPORT_DIR/nottoday-cli.sh</string>
        <string>check</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/nottoday.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/nottoday.error.log</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

# Load the LaunchAgent
echo "Loading LaunchAgent..."
launchctl unload "$LAUNCH_AGENTS_DIR/com.nottoday.scheduler.plist" 2>/dev/null || true
launchctl load "$LAUNCH_AGENTS_DIR/com.nottoday.scheduler.plist"

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Config file: $APP_SUPPORT_DIR/config.json"
echo "  CLI tool: /usr/local/bin/nottoday (or $APP_SUPPORT_DIR/nottoday-cli.sh)"
echo ""
echo "Default Schedule:"
echo "  Days: Monday - Friday"
echo "  Hours: 09:00 - 19:00"
echo ""
echo "Commands:"
echo "  nottoday status     - Check current status"
echo "  nottoday activate   - Manually activate blocking"
echo "  nottoday deactivate - Manually deactivate blocking"
echo "  nottoday list       - List blocked sites"
echo "  nottoday add <site> - Add a site"
echo ""
echo "Edit the config file to customize blocked sites and schedule."
echo ""
echo "To build the GUI app:"
echo "  cd $(dirname "$SCRIPT_DIR")"
echo "  open NotToday.xcodeproj"
echo "  (or run: swift build)"
echo ""
