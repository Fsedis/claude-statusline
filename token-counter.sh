#!/bin/bash

# Add bun to PATH
export PATH="$HOME/.bun/bin:$PATH"

# ANSI Colors
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
MAGENTA='\033[35m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# Icons (Nerd Font)
ICON_FOLDER="󰉋"
ICON_GIT="󰊢"
ICON_MODEL="󰧑"
ICON_COST="󰄴"
ICON_CONTEXT="󰍛"
ICON_CPU="󰘚"
ICON_RAM=""
ICON_COMMIT="󰜘"

# Read JSON input from stdin
input=$(cat)

# Extract basic info from statusline JSON
current_dir="$(echo "$input" | jq -r '.workspace.current_dir')"
model="$(echo "$input" | jq -r '.model.display_name')"
dir_name="$(basename "$current_dir")"

# Shorten model names
shorten_model() {
    case "$1" in
        "Claude Opus 4.5"*|"Opus 4.5"*) echo "O4.5" ;;
        "Claude Sonnet 4.5"*|"Sonnet 4.5"*) echo "S4.5" ;;
        "Claude Sonnet 4"*|"Sonnet 4"*) echo "S4" ;;
        "Claude Haiku 4"*|"Haiku 4"*) echo "H4" ;;
        *) echo "$1" ;;
    esac
}
model_short=$(shorten_model "$model")

# Extract context window data
context_size="$(echo "$input" | jq -r '.context_window.context_window_size // 0')"
current_usage="$(echo "$input" | jq '.context_window.current_usage')"

# Calculate context usage percentage
context_pct=0
if [ "$current_usage" != "null" ] && [ "$context_size" != "0" ] && [ "$context_size" != "null" ]; then
    current_tokens=$(echo "$current_usage" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
    if [ "$current_tokens" != "null" ] && [ "$current_tokens" != "0" ]; then
        context_pct=$(echo "scale=0; ($current_tokens * 100) / $context_size" | bc 2>/dev/null || echo "0")
    fi
fi

# Get session data
session_cost="$(echo "$input" | jq -r '.cost.total_cost_usd // 0')"

# Get git branch if in a git repo
git_branch="$(cd "$current_dir" 2>/dev/null && git branch --show-current 2>/dev/null || echo '')"

# Get time since last commit
last_commit_time=""
if [ -n "$git_branch" ]; then
    last_commit_ts=$(cd "$current_dir" 2>/dev/null && git log -1 --format=%ct 2>/dev/null)
    if [ -n "$last_commit_ts" ]; then
        now_ts=$(date +%s)
        diff_sec=$((now_ts - last_commit_ts))

        if [ "$diff_sec" -lt 60 ]; then
            last_commit_time="${diff_sec}s"
        elif [ "$diff_sec" -lt 3600 ]; then
            last_commit_time="$((diff_sec / 60))m"
        elif [ "$diff_sec" -lt 86400 ]; then
            last_commit_time="$((diff_sec / 3600))h"
        else
            last_commit_time="$((diff_sec / 86400))d"
        fi
    fi
fi

# Function to format cost
format_cost() {
    local cost="$1"
    if [ "$cost" = "null" ] || [ -z "$cost" ] || [ "$cost" = "0" ]; then
        echo "0.00"
    else
        LC_NUMERIC=C printf "%.2f" "$cost" 2>/dev/null || echo "0.00"
    fi
}

# Function to create progress bar
progress_bar() {
    local pct=$1
    local width=10
    local filled=$((pct * width / 100))
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    echo "$bar"
}

# Get CPU usage (1-minute load average / number of cores = percentage)
cpu_cores=$(nproc 2>/dev/null || echo 1)
load_avg=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1)
cpu_pct=$(echo "scale=0; ($load_avg * 100) / $cpu_cores" | bc 2>/dev/null || echo "0")

# Get RAM usage
mem_info=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%.0f", $3/$2*100}')
ram_pct=${mem_info:-0}

# Get usage data
today_date=$(date +%Y%m%d)
today_cost=$(bun x ccusage daily --since "$today_date" --until "$today_date" --json 2>/dev/null | jq -r '.totals.totalCost' 2>/dev/null)
total_cost=$(bun x ccusage daily --since 20240101 --json 2>/dev/null | jq -r '.totals.totalCost' 2>/dev/null)

# Format costs
session_fmt=$(format_cost "$session_cost")
today_fmt=$(format_cost "$today_cost")
total_fmt=$(format_cost "$total_cost")

# Build progress bar with color
bar=$(progress_bar "$context_pct")
if [ "$context_pct" -lt 30 ]; then
    bar_color="${GREEN}"
elif [ "$context_pct" -lt 60 ]; then
    bar_color="${YELLOW}"
else
    bar_color="${RED}"
fi

# Build output
output=""

# Directory
output+="${BLUE}${ICON_FOLDER} ${dir_name}${RESET}"

# Git branch + last commit
if [ -n "$git_branch" ]; then
    output+=" ${MAGENTA}${ICON_GIT} ${git_branch}${RESET}"
    if [ -n "$last_commit_time" ]; then
        output+=" ${DIM}${ICON_COMMIT} ${last_commit_time}${RESET}"
    fi
fi

# Model
output+=" ${DIM}│${RESET} ${CYAN}${ICON_MODEL} ${model_short}${RESET}"

# Cost: session • today / total
output+=" ${DIM}│${RESET} ${ICON_COST} ${GREEN}\$${session_fmt}${RESET} ${DIM}•${RESET} \$${today_fmt} ${DIM}/ \$${total_fmt}${RESET}"

# Context bar
output+=" ${DIM}│${RESET} ${ICON_CONTEXT} ${bar_color}${bar}${RESET} ${DIM}${context_pct}%${RESET}"

# CPU with color
if [ "$cpu_pct" -lt 50 ]; then
    cpu_color="${GREEN}"
elif [ "$cpu_pct" -lt 80 ]; then
    cpu_color="${YELLOW}"
else
    cpu_color="${RED}"
fi
output+=" ${DIM}│${RESET} ${ICON_CPU} ${cpu_color}${cpu_pct}%${RESET}"

# RAM with color
if [ "$ram_pct" -lt 50 ]; then
    ram_color="${GREEN}"
elif [ "$ram_pct" -lt 80 ]; then
    ram_color="${YELLOW}"
else
    ram_color="${RED}"
fi
output+=" ${ICON_RAM} ${ram_color}${ram_pct}%${RESET}"

printf "%b" "$output"
