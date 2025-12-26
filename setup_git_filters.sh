#!/bin/bash
# ==================================================
# Git Filter Setup Script (Local Filters)
# ==================================================
# Filters:
#   - ignorehistory_np_findhistory
#   - ignore_vscode_workspaces
#   - ignore_settings_paths
#   - ignore_explorer_quick_links
#   - ignore_shell_history
#   - ignore_blenderlauncher
#   - ignoretime_np_program
#   - ignore_user_settings
# ==================================================

set -e  # Exit if any command fails

reset_git_filter() {
    local name="$1"
    local clean_cmd="$2"
    local smudge_cmd="$3"

    echo "🔍 Checking for existing filter: $name"
    if git config --local --get-regexp "^filter\.${name}\." >/dev/null 2>&1; then
        echo "🧹 Removing existing '$name' filter..."
        git config --local --remove-section "filter.${name}" || true
    else
        echo "✅ No existing filter found for '$name'"
    fi

    echo "⚙️ Adding new '$name' filter..."
    git config --local "filter.${name}.clean" "$clean_cmd"
    git config --local "filter.${name}.smudge" "$smudge_cmd"
    echo "✨ Filter '$name' configured successfully."
    echo
}

# --- 1️⃣ Notepad++ Filter ---
reset_git_filter \
    "ignorehistory_np_findhistory" \
    "python scripts/git-filters/notepad++/clean-config.py" \
    "cat"

# --- 2️⃣ Blender Launcher Filter ---
reset_git_filter \
    "ignore_blenderlauncher" \
    "sed '/^favorite_path=/d; /^last_time_checked_utc=/d; /^library_folder=/d; /^user_id=/d'" \
    "cat"

# --- 3️⃣ Flow Launcher Filter ---
reset_git_filter \
    "ignoretime_np_program" \
    "sed -E '/(LastIndexTime|ProgramSources|DisabledProgramSources)/,/^[[:space:]]*\\]/d'" \
    "cat"
reset_git_filter \
    "ignore_vscode_workspaces" \
    "python scripts/git-filters/flow-launcher/clean-vscode-workspaces.py" \
    "cat"
reset_git_filter \
    "ignore_settings_paths" \
    "python scripts/git-filters/flow-launcher/clean-settings.py" \
    "python scripts/git-filters/flow-launcher/smudge-settings.py"
reset_git_filter \
    "ignore_shell_history" \
    "python scripts/git-filters/flow-launcher/clean-shell-history.py" \
    "cat"
reset_git_filter \
    "ignore_explorer_quick_links" \
    "python scripts/git-filters/flow-launcher/clean-explorer.py" \
    "python scripts/git-filters/flow-launcher/smudge-explorer.py"

# --- 4️⃣ VS Code User Settings Filter ---
reset_git_filter \
    "ignore_user_settings" \
    "python scripts/git-filters/vscode/clean-settings.py" \
    "python scripts/git-filters/vscode/smudge-settings.py"

echo "✅ All filters created/updated successfully!"
