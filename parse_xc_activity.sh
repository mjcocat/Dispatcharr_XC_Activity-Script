#!/bin/bash

# Parse XC API activity from nginx logs and display to stdout
# Usage: ./parse_xc_activity.sh [number_of_lines] [username_filter]

LINES=${1:-1000}
USERNAME_FILTER=${2:-""}

echo "=================================================="
echo "XC API Activity Parser"
echo "=================================================="
echo "Analyzing last $LINES nginx log entries"
if [ -n "$USERNAME_FILTER" ]; then
    echo "Filtering for username: $USERNAME_FILTER"
fi
echo ""

# Function to extract timestamp in readable format
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
        echo "$(($bytes / 1073741824))GB"
    fi
}

# Parse logs
echo "Recent XC API Activity:"
echo "=================================================="

# Pre-filter by username if specified
if [ -n "$USERNAME_FILTER" ]; then
    GREP_FILTER="username=$USERNAME_FILTER|/(live|movie|series)/$USERNAME_FILTER/"
else
    GREP_FILTER="player_api|/live/.*\.ts|/movie/|/series/|xmltv.php"
fi

docker exec dispatcharr tail -n $LINES /var/log/nginx/access.log | grep -E "$GREP_FILTER" | while IFS= read -r line; do
    # Extract fields
    IP=$(echo "$line" | awk '{print $1}')
    TIMESTAMP=$(echo "$line" | grep -oP '\[\K[^\]]+')
    REQUEST=$(echo "$line" | grep -oP '"(GET|POST)\s+\K[^"]+' | head -1)
    STATUS=$(echo "$line" | awk '{print $9}')
    BYTES=$(echo "$line" | awk '{print $10}')
    USER_AGENT=$(echo "$line" | grep -oP '"[^"]*"\s+"\K[^"]+' | tail -1)
    
    # Extract username
    USERNAME=$(get_username "$REQUEST")
    
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
echo "Summary by User:"
echo "=================================================="

# Create summary
docker exec dispatcharr tail -n $LINES /var/log/nginx/access.log | grep -E "$GREP_FILTER" | while IFS= read -r line; do
    REQUEST=$(echo "$line" | grep -oP '"(GET|POST)\s+\K[^"]+' | head -1)
    USERNAME=$(get_username "$REQUEST")
    if [ -n "$USERNAME" ]; then
        echo "$USERNAME"
    fi
done | sort | uniq -c | sort -rn | while read count user; do
    echo "  $user: $count requests"
done

echo ""
echo "=================================================="
echo "Summary by Request Type:"
echo "=================================================="

docker exec dispatcharr tail -n $LINES /var/log/nginx/access.log | grep -E "$GREP_FILTER" | while IFS= read -r line; do
    REQUEST=$(echo "$line" | grep -oP '"(GET|POST)\s+\K[^"]+' | head -1)
    get_request_type "$REQUEST"
done | sort | uniq -c | sort -rn | while read count type; do
    echo "  $type: $count requests"
done

echo ""
echo "=================================================="
echo "Active IPs by User:"
echo "=================================================="

docker exec dispatcharr tail -n $LINES /var/log/nginx/access.log | grep -E "$GREP_FILTER" | while IFS= read -r line; do
    IP=$(echo "$line" | awk '{print $1}')
    REQUEST=$(echo "$line" | grep -oP '"(GET|POST)\s+\K[^"]+' | head -1)
    USERNAME=$(get_username "$REQUEST")
    if [ -n "$USERNAME" ]; then
        echo "$USERNAME|$IP"
    fi
done | sort -u | awk -F'|' '{print "  " $1 " -> " $2}'

echo ""
echo "Done!"
echo "=================================================="