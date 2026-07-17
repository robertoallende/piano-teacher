#!/usr/bin/env bash
# piano-teacher-log — Beautiful real-time logger for the piano-teacher demo.
#
# Polls CloudWatch logs and formats them for presentation.
# Usage: ./piano-teacher-log.sh [SINCE]
#   SINCE: how far back to look (default: 5m). Examples: 5m, 1h, 90m

set -uo pipefail

# --- Configuration ---
LOG_GROUP="/aws/lambda/piano-teacher-handler"
REGION="us-east-1"
SINCE="${1:-5m}"
POLL_INTERVAL=3

# --- Colors ---
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
RED="\033[31m"
WHITE="\033[97m"

# --- Header ---
clear
echo ""
printf "${BOLD}${CYAN}"
cat << 'EOF'
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║          🎹  p i a n o - t e a c h e r  🎹           ║
    ║                                                       ║
    ║       Always-On Agent • AWS Bedrock + Strands         ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
EOF
printf "${RESET}\n"
printf "  ${DIM}Watching: ${LOG_GROUP}${RESET}\n"
printf "  ${DIM}Region: ${REGION} • Polling every ${POLL_INTERVAL}s${RESET}\n"
echo ""
printf "  ${DIM}────────────────────────────────────────────────────${RESET}\n"
echo ""

# --- Format a single log line ---
format_line() {
    local line="$1"
    local now
    now=$(date +"%H:%M:%S")

    # Skip noise
    case "$line" in
        *INIT_START*|*"END Request"*|*"REPORT Request"*|*"START Request"*|""|*LAMBDA_WARNING*)
            return
            ;;
    esac

    if [[ "$line" == *"Received event"* ]]; then
        printf "  ⚡ ${BOLD}${CYAN}[${now}]${RESET}  ${WHITE}S3 event received → board.md modified${RESET}\n"
    elif [[ "$line" == *"Found"*"card(s) to process"* ]]; then
        local cards
        cards=$(echo "$line" | grep -oE "\[.*\]")
        printf "  🎹 ${BOLD}${GREEN}[${now}]${RESET}  ${GREEN}Matched: ${BOLD}${cards}${RESET}\n"
    elif [[ "$line" == *"Flipping card"* ]]; then
        local title
        title=$(echo "$line" | grep -oE "'[^']+'" | head -1)
        printf "  ⚡ ${DIM}[${now}]  Loop guard: ${title} → done${RESET}\n"
    elif [[ "$line" == *"Board updated: matched cards"* ]]; then
        printf "  ✓ ${DIM}[${now}]  Board updated (loop guard active)${RESET}\n"
    elif [[ "$line" == *"Processing card:"*"docs:"* ]]; then
        local title docs
        title=$(echo "$line" | grep -oE "'[^']+'" | head -1)
        docs=$(echo "$line" | grep -oE "docs: [^ ]+" | sed 's/docs: //')
        echo ""
        printf "  🧠 ${BOLD}${MAGENTA}[${now}]${RESET}  ${MAGENTA}Analyzing score: ${BOLD}${title}${RESET}\n"
        printf "     ${DIM}Reading ${docs}...${RESET}\n"
    elif [[ "$line" == *"PDF read:"* ]]; then
        local size
        size=$(echo "$line" | grep -oE "[0-9]+ bytes")
        printf "     ${DIM}✓ PDF loaded (${size})${RESET}\n"
        printf "     ${DIM}⏱ Sending to Bedrock Claude Sonnet 4.5...${RESET}\n"
    elif [[ "$line" == *"Analysis complete:"* ]]; then
        local count
        count=$(echo "$line" | grep -oE "[0-9]+ lessons")
        printf "     ✨ ${BOLD}${MAGENTA}Analysis complete: ${count}${RESET}\n"
        echo ""
    elif [[ "$line" == *"Written: lessons/"* ]]; then
        local path
        path=$(echo "$line" | grep -oE "lessons/[^ ]+" | sed 's/lessons\///')
        printf "  📖 ${YELLOW}[${now}]${RESET}  ${YELLOW}✓ ${path}${RESET}\n"
    elif [[ "$line" == *"Prepended"* ]]; then
        local info
        info=$(echo "$line" | sed 's/.*Prepended //')
        echo ""
        printf "  ✓ ${GREEN}[${now}]${RESET}  ${GREEN}Lessons.md updated: ${info}${RESET}\n"
    elif [[ "$line" == *"Done:"*"lessons generated"* ]]; then
        local info
        info=$(echo "$line" | sed 's/.*Done: //')
        printf "  ✨ ${BOLD}${GREEN}[${now}]${RESET}  ${BOLD}${GREEN}${info}${RESET}\n"
        echo ""
        printf "  ${DIM}────────────────────────────────────────────────────${RESET}\n"
        echo ""
    elif [[ "$line" == *"No cards with status=doing"* ]]; then
        printf "  ${DIM}[${now}]  Loop guard: no matching cards → exit${RESET}\n"
    elif [[ "$line" == *"ERROR"* ]]; then
        local msg
        msg=$(echo "$line" | sed 's/.*ERROR[: ]*//')
        printf "  ✗ ${RED}[${now}]${RESET}  ${RED}${msg}${RESET}\n"
    elif [[ "$line" == *"WARNING"* ]]; then
        local msg
        msg=$(echo "$line" | sed 's/.*WARNING[: ]*//')
        printf "  ${YELLOW}[${now}]${RESET}  ${YELLOW}⚠ ${msg}${RESET}\n"
    fi
}

# --- Main: poll loop ---
LAST_TOKEN=""

# Initial dump of recent logs
aws logs tail "${LOG_GROUP}" \
    --region "${REGION}" \
    --since "${SINCE}" \
    --format short 2>/dev/null | \
while IFS= read -r raw; do
    line="${raw#* }"
    format_line "$line"
done

printf "  ${DIM}Waiting for new events...${RESET}\n"
echo ""

# Follow: poll every N seconds for new logs
while true; do
    sleep "${POLL_INTERVAL}"
    aws logs tail "${LOG_GROUP}" \
        --region "${REGION}" \
        --since "${POLL_INTERVAL}s" \
        --format short 2>/dev/null | \
    while IFS= read -r raw; do
        line="${raw#* }"
        format_line "$line"
    done
done
