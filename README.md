# NotToday

Block distractions. Not today.

A macOS app that automatically blocks distracting websites during scheduled focus times. Works like SelfControl but with automatic scheduling.

## Features

- **Automatic Scheduling**: Set your focus hours (default: 9:00 - 19:00, weekdays)
- **Menu Bar App**: Quick access to status and controls
- **Easy Configuration**: Add/remove sites via GUI or JSON config
- **CLI Tool**: Full command-line control for automation
- **Works Immediately**: No restart required after changing blocks

## Quick Start (CLI Only)

If you just want the command-line tool with automatic scheduling:

```bash
cd Scripts
chmod +x install.sh
./install.sh
```

This will:
1. Install the CLI tool (`nottoday` command)
2. Set up automatic scheduling via LaunchAgent
3. Create a default config with common distracting sites

## Building the GUI App

### Option 1: Using XcodeGen (Recommended)

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open and build
open NotToday.xcodeproj
```

### Option 2: Using Swift Package Manager

```bash
swift build -c release
```

The built binary will be at `.build/release/NotToday`

## Configuration

The config file is located at:
```
~/Library/Application Support/NotToday/config.json
```

### Example Configuration

```json
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
```

### Customizing the Schedule

Edit `schedule` in the config:

- **days**: Array of day names (lowercase): `sunday`, `monday`, `tuesday`, `wednesday`, `thursday`, `friday`, `saturday`
- **startHour/startMinute**: When blocking begins (24-hour format)
- **endHour/endMinute**: When blocking ends (24-hour format)

#### Examples:

**Weekdays 9 AM - 7 PM:**
```json
"schedule": {
  "days": ["monday", "tuesday", "wednesday", "thursday", "friday"],
  "startHour": 9,
  "startMinute": 0,
  "endHour": 19,
  "endMinute": 0
}
```

**Every day 8 AM - 6 PM:**
```json
"schedule": {
  "days": ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
  "startHour": 8,
  "startMinute": 0,
  "endHour": 18,
  "endMinute": 0
}
```

**Only weekends 10 AM - 5 PM:**
```json
"schedule": {
  "days": ["saturday", "sunday"],
  "startHour": 10,
  "startMinute": 0,
  "endHour": 17,
  "endMinute": 0
}
```

## CLI Commands

```bash
# Check status and schedule
nottoday status

# Manually activate blocking (ignores schedule)
nottoday activate

# Manually deactivate blocking
nottoday deactivate

# Check schedule and apply appropriate state
nottoday check

# List all blocked sites
nottoday list

# Add a new site to block
nottoday add linkedin.com

# Remove a site from block list
nottoday remove youtube.com

# Show current schedule
nottoday schedule
```

## How It Works

NotToday uses the macOS hosts file (`/etc/hosts`) to block websites by redirecting them to `127.0.0.1`. This is a system-level block that works across all browsers and apps.

The LaunchAgent runs every minute to check if blocking should be active based on your schedule.

## Permissions

The app requires administrator privileges to modify `/etc/hosts`. You'll be prompted for your password when:
- Activating blocking
- Deactivating blocking

## Uninstalling

```bash
cd Scripts
chmod +x uninstall.sh
./uninstall.sh
```

This will:
1. Remove any active blocking from hosts file
2. Unload and remove the LaunchAgent
3. Optionally remove your configuration

## Troubleshooting

### Blocking not working?

1. Check if the LaunchAgent is running:
   ```bash
   launchctl list | grep nottoday
   ```

2. Check the logs:
   ```bash
   cat /tmp/nottoday.log
   cat /tmp/nottoday.error.log
   ```

3. Manually run the check:
   ```bash
   nottoday check
   ```

### Sites still accessible?

1. Flush your DNS cache:
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```

2. Clear your browser cache and restart the browser

3. Check if the site has subdomains you need to block (e.g., `m.facebook.com`)

### Need to emergency unblock?

```bash
nottoday deactivate
```

Or manually edit `/etc/hosts` and remove the NotToday section.

## Files

```
~/Library/Application Support/NotToday/
├── config.json              # Your configuration
└── nottoday-cli.sh          # CLI tool

~/Library/LaunchAgents/
└── com.nottoday.scheduler.plist  # LaunchAgent for scheduling
```

## License

MIT License - Feel free to modify and distribute.
