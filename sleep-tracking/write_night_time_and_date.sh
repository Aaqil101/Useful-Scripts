#!/system/bin/sh

# ============================================
# Write MacroDroid Variables to Obsidian
# ============================================
# Appends local variables {lv=date} and {lv=current_night_time} 
# to Time.md in Obsidian vault
# Each entry on a new line, but no leading newline if file is empty
# ============================================

# Define the file path
FILE_PATH="/storage/emulated/0/GitHub/Obsidian/Zettelkasten/Time.md"

# Check if file exists and has content
if [ -f "$FILE_PATH" ] && [ -s "$FILE_PATH" ]; then
    # File exists and is not empty - add newline before appending
    echo "" >> "$FILE_PATH"
    echo "{lv=date}: {lv=current_night_time}" >> "$FILE_PATH"
else
    # File is empty or doesn't exist - write without leading newline
    echo "{lv=date}: {lv=current_night_time}" > "$FILE_PATH"
fi