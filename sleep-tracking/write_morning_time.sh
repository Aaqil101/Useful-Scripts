#!/system/bin/sh

# ============================================
# Write Morning Time to Obsidian
# ============================================
# Appends " - {lv=current_morning_time}" to the last line
# of Time.md in Obsidian vault
# ============================================

# Define the file path
FILE_PATH="/storage/emulated/0/GitHub/Obsidian/Zettelkasten/Time.md"

# Check if file exists and has content
if [ -f "$FILE_PATH" ] && [ -s "$FILE_PATH" ]; then
    # File exists and has content
    # Use sed to append to the last line without adding a newline
    sed -i '$ s/$/ - {lv=current_morning_time}/' "$FILE_PATH"
else
    # File doesn't exist or is empty - create with just the morning time
    echo " - {lv=current_morning_time}" > "$FILE_PATH"
fi