#!/bin/bash
#
# Agent Council - Collect opinions from multiple AI Agents
#
# Usage: council.sh "question or prompt"
#
# LLM Council (Karpathy) concept:
# - Stage 1: Send same question to each Agent
# - Stage 2: Collect and output responses
# - Stage 3: Claude synthesizes as Chairman (handled externally)
#

set -e

# Get script directory and find config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Allow config override via environment variable
if [ -n "$COUNCIL_CONFIG" ]; then
    CONFIG_FILE="$COUNCIL_CONFIG"
else
    CONFIG_FILE="$SKILL_DIR/council.config.yaml"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Color name to code mapping
get_color_code() {
    case "$1" in
        RED) echo "$RED" ;;
        GREEN) echo "$GREEN" ;;
        BLUE) echo "$BLUE" ;;
        YELLOW) echo "$YELLOW" ;;
        CYAN) echo "$CYAN" ;;
        MAGENTA) echo "$MAGENTA" ;;
        *) echo "$NC" ;;
    esac
}

# Mode flags
VERBOSE=false
DRY_RUN=false

# Help text
show_help() {
    cat << 'EOF'
Agent Council - Collect opinions from multiple AI Agents

USAGE:
    council.sh [OPTIONS] "question or prompt"

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Show detailed error output
    -n, --dry-run   Show what would be executed without running

DESCRIPTION:
    Implements Karpathy's LLM Council concept:
    - Stage 1: Send the same question to each configured AI agent
    - Stage 2: Collect and display responses
    - Stage 3: Claude synthesizes as Chairman (handled externally)

EXAMPLES:
    council.sh "What's the best approach for error handling?"
    council.sh -v "Compare React vs Vue for dashboards"
    council.sh --dry-run "test prompt"

CONFIGURATION:
    Edit council.config.yaml to add/remove council members.
    Override config path: COUNCIL_CONFIG=/path/to/config.yaml council.sh "prompt"

EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo -e "${RED}Error: Unknown option: $1${NC}" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: Please provide a prompt${NC}"
    echo "Usage: $0 [OPTIONS] \"question or prompt\""
    echo "Use --help for more information"
    exit 1
fi

PROMPT="$1"
TEMP_DIR=$(mktemp -d)

# Cleanup handler - runs on EXIT, INT, TERM
cleanup() {
    local exit_code=$?
    # Kill any remaining background processes
    for pid in "${PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    # Remove temp directory
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    exit $exit_code
}
trap cleanup EXIT INT TERM

# Parse YAML config (simple parser for our structure - macOS compatible)
parse_members() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Warning: Config file not found at $CONFIG_FILE${NC}" >&2
        echo -e "${YELLOW}Using default configuration (codex, gemini)${NC}" >&2
        echo "codex|codex exec|🤖|BLUE"
        echo "gemini|gemini|💎|GREEN"
        return
    fi

    # Extract members using awk (macOS/BSD compatible)
    awk '
    /^  members:/ { in_members=1; next }
    /^  [a-z]/ && in_members { in_members=0 }
    in_members && /- name:/ {
        name=$3
        gsub(/"/, "", name)
    }
    in_members && /command:/ {
        cmd = $0
        sub(/.*command: *"?/, "", cmd)
        sub(/".*$/, "", cmd)
    }
    in_members && /emoji:/ {
        emoji = $2
        gsub(/"/, "", emoji)
    }
    in_members && /color:/ {
        color = $2
        gsub(/"/, "", color)
        if (name && cmd) {
            print name "|" cmd "|" emoji "|" color
            name=""; cmd=""; emoji=""; color=""
        }
    }
    ' "$CONFIG_FILE"
}

# Parse timeout from config with validation
parse_timeout() {
    local default_timeout=120
    if [ -f "$CONFIG_FILE" ]; then
        local val
        val=$(awk '/timeout:/ {print $2}' "$CONFIG_FILE" | head -1)
        if [ -n "$val" ]; then
            # Validate it's a positive integer
            if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ]; then
                echo "$val"
                return
            else
                echo -e "${YELLOW}Warning: Invalid timeout value '$val' in config, using default ${default_timeout}s${NC}" >&2
            fi
        fi
    fi
    echo "$default_timeout"
}
TIMEOUT_SECONDS=$(parse_timeout)

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🏛️  Agent Council - Gathering Opinions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📝 Question:${NC} $PROMPT"
echo ""

# Function to call an agent (secure version - no eval)
call_agent() {
    local name="$1"
    local command="$2"
    local output_file="$TEMP_DIR/${name}.txt"
    local stderr_file="$TEMP_DIR/${name}_stderr.txt"
    local color_code="$3"

    # Safe command parsing - split into array (prevents injection)
    read -ra cmd_array <<< "$command"
    local base_cmd="${cmd_array[0]}"

    # Dry-run mode - just show what would be executed
    if $DRY_RUN; then
        echo -e "${color_code}[$name]${NC} Would execute: ${cmd_array[*]} \"<prompt>\"" >&2
        if command -v "$base_cmd" &> /dev/null; then
            echo "[DRY-RUN] $name: Command '${cmd_array[*]}' is available" > "$output_file"
        else
            echo "[DRY-RUN] $name: Command '$base_cmd' NOT FOUND" > "$output_file"
        fi
        return
    fi

    echo -e "${color_code}[$name]${NC} Thinking..." >&2

    if ! command -v "$base_cmd" &> /dev/null; then
        echo "$name CLI not installed (command: $base_cmd)" > "$output_file"
        echo -e "${YELLOW}[$name]${NC} Skipped (not installed)" >&2
        return
    fi

    # Execute with timeout (portable approach using a marker file)
    local timeout_marker="$TEMP_DIR/${name}_timeout"

    # Run command in background
    ( "${cmd_array[@]}" "$PROMPT" ) > "$output_file" 2>"$stderr_file" &
    local cmd_pid=$!

    # Timeout watchdog - exits immediately if marker file exists
    (
        local elapsed=0
        while [ $elapsed -lt "$TIMEOUT_SECONDS" ]; do
            sleep 1
            elapsed=$((elapsed + 1))
            # Check if command already finished
            if ! kill -0 "$cmd_pid" 2>/dev/null; then
                exit 0
            fi
        done
        # Timeout reached - kill command and create marker
        touch "$timeout_marker"
        kill "$cmd_pid" 2>/dev/null
    ) &
    local watchdog_pid=$!

    # Wait for command to finish
    local exit_status=0
    wait "$cmd_pid" 2>/dev/null || exit_status=$?

    # Kill watchdog (it should exit on its own, but be safe)
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    if [ $exit_status -ne 0 ]; then
        # Check if timeout occurred (marker file exists or killed by signal)
        if [ -f "$timeout_marker" ] || [ $exit_status -eq 137 ] || [ $exit_status -eq 143 ]; then
            echo "Error: $name timed out after ${TIMEOUT_SECONDS}s" > "$output_file"
        else
            echo "Error calling $name (exit code: $exit_status)" > "$output_file"
        fi
        # Append stderr details if available
        if [ -s "$stderr_file" ]; then
            echo "" >> "$output_file"
            echo "Details:" >> "$output_file"
            head -10 "$stderr_file" >> "$output_file"
        fi
    fi

    # Verbose mode - show stderr
    if $VERBOSE && [ -s "$stderr_file" ]; then
        echo -e "${YELLOW}[$name stderr]:${NC}" >&2
        cat "$stderr_file" >&2
    fi

    echo -e "${GREEN}[$name]${NC} Done" >&2
}

# Stage 1: Collect members and call in parallel
echo -e "${YELLOW}Stage 1: Collecting opinions from council members...${NC}"
echo ""

# Read members and start parallel calls
declare -a PIDS
declare -a MEMBERS

while IFS='|' read -r name cmd emoji color; do
    [ -z "$name" ] && continue
    MEMBERS+=("$name|$emoji|$color")
    color_code=$(get_color_code "$color")
    call_agent "$name" "$cmd" "$color_code" &
    PIDS+=("$!")
done < <(parse_members)

# Validate that we have at least one member
if [ ${#MEMBERS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No council members configured${NC}" >&2
    echo "Check your council.config.yaml file or use defaults by removing it" >&2
    exit 1
fi

echo -e "${CYAN}Querying ${#MEMBERS[@]} council member(s)...${NC}"

# Wait for all agents
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Stage 2: Council Opinions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Display each member's response
for member_info in "${MEMBERS[@]}"; do
    IFS='|' read -r name emoji color <<< "$member_info"
    color_code=$(get_color_code "$color")
    output_file="$TEMP_DIR/${name}.txt"

    echo -e "${color_code}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${color_code}│ ${emoji} ${name}${NC}"
    echo -e "${color_code}└─────────────────────────────────────────────────────────┘${NC}"

    if [ -f "$output_file" ]; then
        cat "$output_file"
    else
        echo "No response"
    fi
    echo ""
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Stage 3: Claude (Chairman) will synthesize above opinions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Cleanup handled by trap
