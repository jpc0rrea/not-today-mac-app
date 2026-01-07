#!/bin/bash
#
# NotToday CLI - Standalone command-line interface
#
# This script can be used independently of the GUI app to control blocking.
# It reads configuration from ~/Library/Application Support/NotToday/config.json
#
# Usage:
#   ./nottoday-cli.sh status       - Check if blocking is active
#   ./nottoday-cli.sh activate     - Manually activate blocking
#   ./nottoday-cli.sh deactivate   - Manually deactivate blocking
#   ./nottoday-cli.sh check        - Check schedule and activate/deactivate accordingly
#   ./nottoday-cli.sh list         - List blocked sites
#   ./nottoday-cli.sh add <site>   - Add a site to block list
#   ./nottoday-cli.sh remove <site>- Remove a site from block list

set -e

HOSTS_FILE="/etc/hosts"
CONFIG_DIR="$HOME/Library/Application Support/NotToday"
CONFIG_FILE="$CONFIG_DIR/config.json"
MARKER_START="# NotToday START - DO NOT EDIT THIS SECTION"
MARKER_END="# NotToday END"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Create default config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'DEFAULTCONFIG'
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
DEFAULTCONFIG
    echo "Created default config at: $CONFIG_FILE"
fi

# Function to check if blocking is currently active
check_status() {
    if grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
        echo -e "${RED}Blocking is ACTIVE${NC}"
        return 0
    else
        echo -e "${GREEN}Blocking is INACTIVE${NC}"
        return 1
    fi
}

# Function to get blocked sites from config
get_blocked_sites() {
    python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    for site in config['blockedSites']:
        print(site)
"
}

# Function to activate blocking
activate_blocking() {
    echo "Activating blocking..."

    # First, remove any existing NotToday entries
    sudo sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

    # Add new entries
    {
        echo ""
        echo "$MARKER_START"
        get_blocked_sites | while read -r site; do
            echo "127.0.0.1 $site"
        done
        echo "$MARKER_END"
    } | sudo tee -a "$HOSTS_FILE" > /dev/null

    # Flush DNS cache
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true

    echo -e "${RED}Blocking ACTIVATED${NC}"
}

# Function to deactivate blocking
deactivate_blocking() {
    echo "Deactivating blocking..."

    # Remove NotToday entries
    sudo sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"

    # Flush DNS cache
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null || true

    echo -e "${GREEN}Blocking DEACTIVATED${NC}"
}

# Function to check if current time is within schedule
should_be_blocking() {
    python3 << 'PYTHONSCRIPT'
import json
from datetime import datetime

config_path = "$CONFIG_FILE".replace("$HOME", __import__("os").environ["HOME"])

with open(config_path) as f:
    config = json.load(f)

if not config.get("enabled", True):
    print("disabled")
    exit(0)

schedule = config["schedule"]
now = datetime.now()

# Map weekday names
day_map = {
    0: "monday",
    1: "tuesday",
    2: "wednesday",
    3: "thursday",
    4: "friday",
    5: "saturday",
    6: "sunday"
}

current_day = day_map[now.weekday()]
scheduled_days = [d.lower() for d in schedule["days"]]

if current_day not in scheduled_days:
    print("outside_days")
    exit(0)

current_minutes = now.hour * 60 + now.minute
start_minutes = schedule["startHour"] * 60 + schedule.get("startMinute", 0)
end_minutes = schedule["endHour"] * 60 + schedule.get("endMinute", 0)

if start_minutes <= current_minutes < end_minutes:
    print("should_block")
else:
    print("outside_hours")
PYTHONSCRIPT
}

# Function to check schedule and apply appropriate state
check_schedule() {
    result=$(should_be_blocking)
    currently_blocking=false

    if grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
        currently_blocking=true
    fi

    case "$result" in
        "should_block")
            if [ "$currently_blocking" = false ]; then
                echo "Schedule says we should be blocking. Activating..."
                activate_blocking
            else
                echo -e "${YELLOW}Already blocking as scheduled${NC}"
            fi
            ;;
        "outside_hours"|"outside_days")
            if [ "$currently_blocking" = true ]; then
                echo "Outside scheduled time. Deactivating..."
                deactivate_blocking
            else
                echo -e "${GREEN}Outside scheduled time, blocking inactive${NC}"
            fi
            ;;
        "disabled")
            echo -e "${YELLOW}Scheduling is disabled in config${NC}"
            ;;
    esac
}

# Function to list blocked sites
list_sites() {
    echo "Blocked sites from config:"
    echo "=========================="
    get_blocked_sites | while read -r site; do
        echo "  - $site"
    done
    echo ""
    echo "Config file: $CONFIG_FILE"
}

# Function to add a site
add_site() {
    local site="$1"

    # Normalize the site
    site=$(echo "$site" | tr '[:upper:]' '[:lower:]' | sed 's|https\?://||' | sed 's|/$||')

    python3 << PYTHONSCRIPT
import json

with open('$CONFIG_FILE') as f:
    config = json.load(f)

site = "$site"
if site not in config['blockedSites']:
    config['blockedSites'].append(site)
    # Also add www variant if not present
    if not site.startswith('www.'):
        www_site = 'www.' + site
        if www_site not in config['blockedSites']:
            config['blockedSites'].append(www_site)

    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Added: {site}")
else:
    print(f"Site already in block list: {site}")
PYTHONSCRIPT
}

# Function to remove a site
remove_site() {
    local site="$1"

    python3 << PYTHONSCRIPT
import json

with open('$CONFIG_FILE') as f:
    config = json.load(f)

site = "$site"
if site in config['blockedSites']:
    config['blockedSites'].remove(site)
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Removed: {site}")
else:
    print(f"Site not in block list: {site}")
PYTHONSCRIPT
}

# Function to show schedule info
show_schedule() {
    python3 << 'PYTHONSCRIPT'
import json
from datetime import datetime

config_path = "$CONFIG_FILE".replace("$HOME", __import__("os").environ["HOME"])

with open(config_path) as f:
    config = json.load(f)

schedule = config["schedule"]
enabled = config.get("enabled", True)

print(f"Scheduling enabled: {enabled}")
print(f"Days: {', '.join(d.capitalize() for d in schedule['days'])}")
print(f"Hours: {schedule['startHour']:02d}:{schedule.get('startMinute', 0):02d} - {schedule['endHour']:02d}:{schedule.get('endMinute', 0):02d}")
PYTHONSCRIPT
}

# Main command handler
case "${1:-}" in
    status)
        check_status
        echo ""
        show_schedule
        ;;
    activate)
        activate_blocking
        ;;
    deactivate)
        deactivate_blocking
        ;;
    check)
        check_schedule
        ;;
    list)
        list_sites
        ;;
    add)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 add <site>"
            exit 1
        fi
        add_site "$2"
        ;;
    remove)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 remove <site>"
            exit 1
        fi
        remove_site "$2"
        ;;
    schedule)
        show_schedule
        ;;
    *)
        echo "NotToday CLI"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  status      - Check if blocking is active"
        echo "  activate    - Manually activate blocking"
        echo "  deactivate  - Manually deactivate blocking"
        echo "  check       - Check schedule and apply appropriate state"
        echo "  list        - List blocked sites"
        echo "  add <site>  - Add a site to block list"
        echo "  remove <site> - Remove a site from block list"
        echo "  schedule    - Show current schedule"
        echo ""
        echo "Config file: $CONFIG_FILE"
        exit 1
        ;;
esac
