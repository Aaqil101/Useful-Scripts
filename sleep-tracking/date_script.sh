#!/bin/bash

# Test script for the MacroDroid sleep tracking date script
# Usage: ./test_script.sh [HH:MM]
# Example: ./test_script.sh 22:30

echo "========================================="
echo "Sleep Tracking Date Script Test Suite"
echo "========================================="
echo ""

# Function to test a specific time
test_time() {
    local test_hour=$1
    local test_minute=$2
    local formatted_time=$(printf "%02d:%02d" $test_hour $test_minute)
    
    # Convert hour to integer for comparison
    hour_int=$((test_hour))
    
    # Determine expected result based on sleep tracking logic
    local expected
    if [ $hour_int -ge 18 ] && [ $hour_int -le 23 ]; then
        expected="Tomorrow (bedtime - evening)"
        result=$(date -d "tomorrow" +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d 2>/dev/null)
    elif [ $hour_int -ge 0 ] && [ $hour_int -le 5 ]; then
        expected="Tomorrow (still sleeping - early morning)"
        result=$(date -d "tomorrow" +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d 2>/dev/null)
    else
        expected="Today (awake - daytime)"
        result=$(date +%Y-%m-%d)
    fi
    
    echo "Testing time: $formatted_time"
    echo "Expected: $expected"
    echo "Result: $result"
    echo ""
}

# If parameter provided, test that specific time
if [ $# -eq 1 ]; then
    # Parse HH:MM format
    IFS=':' read -r hour minute <<< "$1"
    
    if [ -z "$minute" ]; then
        echo "Error: Please provide time in HH:MM format"
        echo "Example: ./test_script.sh 22:30"
        exit 1
    fi
    
    test_time $hour $minute
else
    # Run comprehensive test suite
    echo "Running comprehensive test suite for sleep tracking..."
    echo ""
    
    echo "--- Early Morning (12 AM - 5:59 AM) - Returns TOMORROW ---"
    test_time 0 0    # Midnight (still sleeping)
    test_time 2 30   # 2:30 AM (middle of night)
    test_time 5 59   # 5:59 AM (early morning)
    
    echo "--- Morning (6 AM - 11:59 AM) - Returns TODAY ---"
    test_time 6 0    # 6:00 AM (wake up time)
    test_time 9 0    # 9:00 AM (morning)
    test_time 11 59  # 11:59 AM
    
    echo "--- Afternoon (12 PM - 5:59 PM) - Returns TODAY ---"
    test_time 12 1   # 12:01 PM
    test_time 14 30  # 2:30 PM
    test_time 17 59  # 5:59 PM
    
    echo "--- Evening/Bedtime (6 PM - 11:59 PM) - Returns TOMORROW ---"
    test_time 18 0   # 6:00 PM (bedtime start)
    test_time 22 0   # 10:00 PM (typical bedtime)
    test_time 23 59  # 11:59 PM (late bedtime)
    
    echo "========================================="
    echo "Test suite complete!"
    echo ""
    echo "LOGIC SUMMARY:"
    echo "• 6:00 PM - 11:59 PM → TOMORROW (going to bed)"
    echo "• 12:00 AM - 5:59 AM → TOMORROW (still in same sleep session)"
    echo "• 6:00 AM - 5:59 PM → TODAY (awake, new day)"
    echo ""
    echo "To test a specific time, run:"
    echo "./test_script.sh HH:MM"
    echo "Example: ./test_script.sh 22:30"
fi
