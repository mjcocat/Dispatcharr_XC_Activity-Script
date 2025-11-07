# Dispatcharr_XC_Activity-Script
Bash script to view XC API activity

# Copy to your server and make executable
chmod +x parse_xc_activity.sh

# Usage
+ Default: last 7 days, all users

./parse_xc_activity.sh

+ Last 30 days

./parse_xc_activity.sh 30

+ Last 1 day, filter for user "joe"

./parse_xc_activity.sh 1 joe

+ Last 14 days, filter for user "randy"

./parse_xc_activity.sh 14 randy

# Sample Output

```
==================================================
Data Consumption by User:
==================================================
  joe:                 6.16GB (45 requests)
  randy:                  36MB (1 requests)
  bob:                    23MB (1 requests)

==================================================
Summary by User (Request Count):
==================================================
  joe: 45 requests
  randy: 1 requests
  bob: 1 requests

==================================================
Summary by Request Type:
==================================================
  STREAM: Live TV: 16 requests
  EPG: Guide Data: 7 requests
  API: Get Series: 6 requests
  API: Authentication: 6 requests
  API: Get VOD Streams: 3 requests
  API: Get VOD Categories: 3 requests
  API: Get Live Streams: 3 requests
  API: Get Live Categories: 3 requests

==================================================
Active IPs by User:
==================================================
  bob -> 10.19.170.24
  joe -> 10.18.10.15
  joe -> 24.10.15.3
  joe -> 172.56.25.68
  joe -> 24.10.15.3
  randy -> 10.29.170.15

==================================================
Summary:
==================================================
  Time period: Last 3 day(s)
  Total entries: 47
  Unique users: 3
  Unique IPs: 6
  Total data: 6.22GB

Done!
==================================================
