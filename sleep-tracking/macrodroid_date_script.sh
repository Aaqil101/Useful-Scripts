#!/system/bin/sh

# ============================================
# Sleep Tracking Date Script for MacroDroid
# ============================================
# Purpose: Returns the appropriate date for sleep tracking based on current time
#
# Logic:
#   - Evening (6 PM - 11:59 PM): Returns tomorrow's date (going to bed)
#   - Night (12 AM - 5:59 AM): Returns tomorrow's date (still in same sleep session)
#   - Day (6 AM - 5:59 PM): Returns today's date (awake, new day started)
#
# Example:
#   10:00 PM Dec 28 → Dec 29 (bedtime)
#   02:30 AM Dec 29 → Dec 29 (still sleeping)
#   07:00 AM Dec 29 → Dec 29 (awake)
# ============================================

# Get current hour in 24-hour format (00-23)
current_hour=$(date +%H)

# Remove leading zero to avoid octal interpretation in shell comparisons
# (e.g., "08" becomes "8", "00" becomes empty string)
current_hour=$(echo $current_hour | sed 's/^0*//')

# Handle midnight case where removing zeros leaves empty string
if [ -z "$current_hour" ]; then
    current_hour=0
fi

# Determine which date to return based on current hour
if [ $current_hour -ge 18 ] && [ $current_hour -le 23 ]; then
    # Between 6:00 PM (18:00) and 11:59 PM (23:59)
    # User is going to bed - log as tomorrow's sleep session
    date -d "@$(( $(date +%s) + 86400 ))" +%Y-%m-%d
    
elif [ $current_hour -ge 0 ] && [ $current_hour -le 5 ]; then
    # Between 12:00 AM (00:00) and 5:59 AM (05:59)
    # User is still sleeping - keep same date as bedtime (tomorrow)
    date -d "@$(( $(date +%s) + 86400 ))" +%Y-%m-%d
    
else
    # Between 6:00 AM (06:00) and 5:59 PM (17:59)
    # User is awake - return today's date
    date +%Y-%m-%d
fi