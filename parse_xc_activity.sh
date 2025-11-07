#!/bin/bash

# Parse XC API activity from nginx logs and display to stdout
# Usage: ./parse_xc_activity.sh [days_back] [username_filter]

DAYS_BACK=${1:-7}
USERNAME_FILTER=${2:-""}

echo "=================================================="
echo "XC API Activity Parser"
echo "=================================================="
echo "Analyzing last $DAYS_BACK day(s) of activity"
if [ -n "$USERNAME_FILTER" ]; then
    echo "Filtering for username: $USERNAME_FILTER"
fi
echo ""

# Calculate cutoff date (current time minus DAYS_BACK days)
CUTOFF_TIMESTAMP=$(date -d "$DAYS_BACK days ago" +%s)
echo "Cutoff date: $(date -d "@$CUTOFF_TIMESTAMP" '+%Y-%m-%d %H:%M:%S')"
echo ""

# Function to convert nginx timestamp to epoch
nginx_to_epoch() {
    local nginx_date="$1"
    # nginx format: 06/Nov/2025:19:22:38 +0000
    date -d "$(echo $nginx_date | sed 's|/|-|g; s|:| |; s| +.*||')" +%s 2>/dev/null
}

# Function to parse timestamp in readable format
parse_timestamp() {
    echo "$1" | sed 's/\[//g' | sed 's/\]//g' | awk '{print $1, $2}'
}

# Function to categorize request type
get_request_type() {
    local path="$1"
    if echo "$path" | grep -q "player_api.*action=get_live_streams"; then
        echo "API: Get Live Streams"
    elif echo "$path" | grep -q "player_api.*action=get_live_categories"; then
        echo "API: Get Live Categories"
    elif echo "$path" | grep -q "player_api.*action=get_vod_streams"; then
        echo "API: Get VOD Streams"
    elif echo "$path" | grep -q "player_api.*action=get_vod_categories"; then
        echo "API: Get VOD Categories"
    elif echo "$path" | grep -q "player_api.*action=get_series"; then
        echo "API: Get Series"
    elif echo "$path" | grep -q "player_api.*action=get_series_categories"; then
        echo "API: Get Series Categories"
    elif echo "$path" | grep -q "player_api"; then
        echo "API: Authentication"
    elif echo "$path" | grep -q "/live/.*\.ts"; then
        echo "STREAM: Live TV"
    elif echo "$path" | grep -q "/movie/.*\."; then
        echo "STREAM: Movie"
    elif echo "$path" | grep -q "/series/.*\."; then
        echo "STREAM: Series"
    elif echo "$path" | grep -q "xmltv.php"; then
        echo "EPG: Guide Data"
    else
        echo "Other"
    fi
}

# Function to extract username from path
get_username() {
    local path="$1"
    # Try player_api pattern
    if echo "$path" | grep -q "username="; then
        echo "$path" | grep -oP 'username=\K[^&\s]+'
    # Try /live/ or /movie/ or /series/ pattern
    elif echo "$path" | grep -qE '/(live|movie|series)/[^/]+/'; then
        echo "$path" | grep -oP '/(live|movie|series)/\K[^/]+'
    fi
}

# Function to extract stream ID
get_stream_id() {
    local path="$1"
    if echo "$path" | grep -qE '/live/[^/]+/[^/]+/(\d+)\.ts'; then
        echo "$path" | grep -oP '/live/[^/]+/[^/]+/\K\d+(?=\.ts)'
    elif echo "$path" | grep -qE '/movie/[^/]+/[^/]+/(\d+)\.'; then
        echo "$path" | grep -oP '/movie/[^/]+/[^/]+/\K\d+(?=\.)'
    fi
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(($bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(($bytes / 1048576))MB"
    else
        printf "%.2fGB" $(echo "scale=2; $bytes / 1073741824" | bc)
    fi
}

# Pre-filter by username if specified
if [ -n "$USERNAME_FILTER" ]; then
    GREP_FILTER="username=$USERNAME_FILTER|/(live|movie|series)/$USERNAME_FILTER/"
else
    GREP_FILTER="player_api|/live/.*\.ts|/movie/|/series/|xmltv.php"
fi

# Create temp file for storing parsed data
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Parse all logs and filter by date
echo "Parsing logs..."
docker exec dispatcharr cat /var/log/nginx/access.log | grep -E "$GREP_FILTER" | while IFS= read -r line; do
    # Extract timestamp
    TIMESTAMP=$(echo "$line" | grep -oP '\[\K[^\]]+')
    
    # Convert to epoch
    LOG_EPOCH=$(nginx_to_epoch "$TIMESTAMP")
    
    # Skip if we couldn't parse the date or if it's older than cutoff
    if [ -z "$LOG_EPOCH" ] || [ $LOG_EPOCH -lt $CUTOFF_TIMESTAMP ]; then
        continue
    fi
    
    # Extract fields
    IP=$(echo "$line" | awk '{print $1}')
    REQUEST=$(echo "$line" | grep -oP '"(GET|POST)\s+\K[^"]+' | head -1)
    STATUS=$(echo "$line" | awk '{print $9}')
    BYTES=$(echo "$line" | awk '{print $10}')
    USER_AGENT=$(echo "$line" | grep -oP '"[^"]*"\s+"\K[^"]+' | tail -1)
    
    # Extract username
    USERNAME=$(get_username "$REQUEST")
    
    # Store in temp file
    echo "$TIMESTAMP|$USERNAME|$IP|$REQUEST|$STATUS|$BYTES|$USER_AGENT" >> $TEMP_FILE
done

# Count total entries
TOTAL_ENTRIES=$(wc -l < $TEMP_FILE)
echo "Found $TOTAL_ENTRIES matching entries"
echo ""

# Parse logs
echo "Recent XC API Activity:"
echo "=================================================="

# Show last 50 entries
tail -50 $TEMP_FILE | while IFS='|' read -r TIMESTAMP USERNAME IP REQUEST STATUS BYTES USER_AGENT; do
    # Get request type
    REQ_TYPE=$(get_request_type "$REQUEST")
    
    # Get stream ID if applicable
    STREAM_ID=$(get_stream_id "$REQUEST")
    
    # Format bytes
    BYTES_FORMATTED=$(format_bytes ${BYTES:-0})
    
    # Shorten user agent
    USER_AGENT_SHORT=$(echo "$USER_AGENT" | cut -c1-30)
    
    # Output formatted line
    echo "---"
    echo "Time:     $TIMESTAMP"
    echo "User:     $USERNAME"
    echo "IP:       $IP"
    echo "Type:     $REQ_TYPE"
    if [ -n "$STREAM_ID" ]; then
        echo "Stream:   $STREAM_ID"
    fi
    echo "Status:   $STATUS"
    echo "Data:     $BYTES_FORMATTED"
    echo "Device:   $USER_AGENT_SHORT"
done

echo ""
echo "=================================================="
echo "Data Consumption by User:"
echo "=================================================="

# Calculate total bytes per user
declare -A user_bytes
declare -A user_counts

while IFS='|' read -r TIMESTAMP USERNAME IP REQUEST STATUS BYTES USER_AGENT; do
    if [ -n "$USERNAME" ] && [ -n "$BYTES" ] && [ "$BYTES" != "-" ]; then
        user_bytes[$USERNAME]=$((${user_bytes[$USERNAME]:-0} + BYTES))
        user_counts[$USERNAME]=$((${user_counts[$USERNAME]:-0} + 1))
    fi
done < $TEMP_FILE

# Sort by bytes consumed and display
for user in "${!user_bytes[@]}"; do
    bytes=${user_bytes[$user]}
    count=${user_counts[$user]}
    formatted=$(format_bytes $bytes)
    echo "$bytes|$user|$count|$formatted"
done | sort -t'|' -k1 -rn | while IFS='|' read -r bytes user count formatted; do
    printf "  %-15s %12s (%d requests)\n" "$user:" "$formatted" "$count"
done

echo ""
echo "=================================================="
echo "Summary by User (Request Count):"
echo "=================================================="

# Count requests per user
cat $TEMP_FILE | cut -d'|' -f2 | grep -v '^$' | sort | uniq -c | sort -rn | while read count user; do
    echo "  $user: $count requests"
done

echo ""
echo "=================================================="
echo "Summary by Request Type:"
echo "=================================================="

# Count by request type
cat $TEMP_FILE | cut -d'|' -f4 | while read request; do
    get_request_type "$request"
done | sort | uniq -c | sort -rn | while read count type; do
    echo "  $type: $count requests"
done

echo ""
echo "=================================================="
echo "Active IPs by User:"
echo "=================================================="

# List unique IPs per user
cat $TEMP_FILE | awk -F'|' '{print $2 "|" $3}' | sort -u | awk -F'|' '{if ($1) print "  " $1 " -> " $2}'

echo ""
echo "=================================================="
echo "Summary:"
echo "=================================================="
echo "  Time period: Last $DAYS_BACK day(s)"
echo "  Total entries: $TOTAL_ENTRIES"
echo "  Unique users: $(cat $TEMP_FILE | cut -d'|' -f2 | grep -v '^$' | sort -u | wc -l)"
echo "  Unique IPs: $(cat $TEMP_FILE | cut -d'|' -f3 | sort -u | wc -l)"

# Calculate total data transferred
TOTAL_BYTES=$(cat $TEMP_FILE | cut -d'|' -f6 | grep -v '^$' | grep -v '^-$' | awk '{sum+=$1} END {print sum}')
if [ -n "$TOTAL_BYTES" ]; then
    echo "  Total data: $(format_bytes $TOTAL_BYTES)"
fi

echo ""
echo "Done!"
echo "=================================================="
