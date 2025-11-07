# Dispatcharr_XC_Activity-Script
Bash script to view XC API activity

# Copy to your server and make executable
chmod +x parse_xc_activity.sh

# Run it
sudo ./parse_xc_activity.sh

sudo ./parse_xc_activity.sh 5000 (Analyze more entries)

sudo ./parse_xc_activity.sh 1000 joe (Filter for specific user)

# Sample Output

```Time:     07/Nov/2025:03:04:03 +0000
User:     Joe
IP:       24.10.15.3
Type:     STREAM: Live TV
Status:   200
Data:     1MB
Device:   libmpv
---
Time:     07/Nov/2025:03:04:19 +0000
User:     Joe
IP:       24.10.15.3
Type:     STREAM: Live TV
Status:   200
Data:     30MB
Device:   libmpv

==================================================
Summary by User:
==================================================
  mike: 5 requests

==================================================
Summary by Request Type:
==================================================
  STREAM: Live TV: 5 requests

==================================================
Active IPs by User:
==================================================
  joe -> 10.18.10.15
  joe -> 24.10.15.3
  joe -> 172.56.25.68
  joe -> 24.10.15.3

Done!
==================================================
