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
BLIND_MODE=true  # Anonymize agent names for chairman to prevent bias
REPORT_FILE=""   # Optional: save report to file
OUTPUT_DIR=""    # Default output directory for auto-generated reports

# Mapping file location (in .gitignored location so chairman can't peek)
MAPPING_FILE="$SKILL_DIR/.council-mapping"

# Fallback anonymous alias for an agent (Agent A, Agent B, etc.)
get_fallback_alias() {
    local index="$1"
    local letters=("A" "B" "C" "D" "E" "F" "G" "H")
    echo "Agent ${letters[$index]}"
}

# Help text
show_help() {
    cat << 'EOF'
Agent Council - Collect opinions from multiple AI Agents

USAGE:
    council.sh [OPTIONS] "question or prompt"

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Show detailed error output
    -n, --dry-run           Show what would be executed without running
    -b, --no-blind          Disable blind mode (show real agent names to chairman)
    -r, --report FILE       Save combined report to specific file (disables auto-output)
    -o, --output-dir DIR    Save auto-generated reports to directory

OUTPUT:
    By default, the council generates TWO markdown files in the current directory:
    - council-minutes_TIMESTAMP.md     - Detailed deliberation with all member statements
    - council-chairman-report_TIMESTAMP.md - Chairman's synthesis and recommendation

    Use -o/--output-dir to specify a different directory for these files.
    Use -r/--report to save a single combined report instead.

DESCRIPTION:
    Implements Karpathy's LLM Council concept:
    - Stage 1: Send the same question to each configured AI agent
    - Stage 2: Collect and display responses
    - Stage 3: Chairman synthesizes passionate debate into actionable recommendation

EXAMPLES:
    council.sh "What's the best approach for error handling?"
    council.sh -v "Compare React vs Vue for dashboards"
    council.sh -o ./reports "Should we use microservices?"
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
        -b|--no-blind)
            BLIND_MODE=false
            shift
            ;;
        -r|--report)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo -e "${RED}Error: --report requires a filename${NC}" >&2
                exit 1
            fi
            REPORT_FILE="$2"
            shift 2
            ;;
        -o|--output-dir)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo -e "${RED}Error: --output-dir requires a directory${NC}" >&2
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
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
# Parse sub_chairs from config
# Output format: name|command|emoji|color|codename|framework|prompt
parse_sub_chairs() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return  # No sub-chairs without config
    fi

    # Extract sub_chairs using awk (macOS/BSD compatible)
    awk '
    /^  sub_chairs:/ { in_sub_chairs=1; next }
    /^  [a-z]/ && !/sub_chairs/ && in_sub_chairs { in_sub_chairs=0 }
    in_sub_chairs && /- name:/ {
        # Save previous sub-chair if exists
        if (name && cmd) {
            if (!codename) codename = "Sub-Chair"
            if (!framework) framework = "General Ethics"
            if (!prompt) prompt = "Provide ethical analysis."
            print name "|" cmd "|" emoji "|" color "|" codename "|" framework "|" prompt
        }
        name=$3
        gsub(/"/, "", name)
        cmd=""; emoji=""; color=""; codename=""; framework=""; prompt=""
    }
    in_sub_chairs && /codename:/ {
        codename = $0
        sub(/.*codename: *"?/, "", codename)
        sub(/".*$/, "", codename)
    }
    in_sub_chairs && /command:/ {
        cmd = $0
        sub(/.*command: *"?/, "", cmd)
        sub(/".*$/, "", cmd)
    }
    in_sub_chairs && /emoji:/ {
        emoji = $2
        gsub(/"/, "", emoji)
    }
    in_sub_chairs && /color:/ {
        color = $2
        gsub(/"/, "", color)
    }
    in_sub_chairs && /^      framework:/ {
        framework = $0
        sub(/.*framework: *"?/, "", framework)
        sub(/".*$/, "", framework)
    }
    in_sub_chairs && /^      prompt:/ {
        prompt = $0
        sub(/.*prompt: *"?/, "", prompt)
        sub(/".*$/, "", prompt)
    }
    END {
        # Output last sub-chair
        if (name && cmd) {
            if (!codename) codename = "Sub-Chair"
            if (!framework) framework = "General Ethics"
            if (!prompt) prompt = "Provide ethical analysis."
            print name "|" cmd "|" emoji "|" color "|" codename "|" framework "|" prompt
        }
    }
    ' "$CONFIG_FILE"
}

parse_members() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Warning: Config file not found at $CONFIG_FILE${NC}" >&2
        echo -e "${YELLOW}Using default configuration (codex, gemini)${NC}" >&2
        echo "codex|codex exec|🤖|BLUE|The Coder||"
        echo "gemini|gemini|💎|GREEN|The Sage||"
        return
    fi

    # Extract members using awk (macOS/BSD compatible)
    # Output format: name|command|emoji|color|codename|strengths|persona
    awk '
    /^  members:/ { in_members=1; next }
    /^  [a-z]/ && in_members { in_members=0 }
    in_members && /- name:/ {
        # Save previous member if exists
        if (name && cmd) {
            if (!codename) codename = "Agent"
            if (!strengths) strengths = "general analysis"
            if (!persona) persona = "You are a council member providing expert analysis."
            print name "|" cmd "|" emoji "|" color "|" codename "|" strengths "|" persona
        }
        name=$3
        gsub(/"/, "", name)
        cmd=""; emoji=""; color=""; codename=""; strengths=""; persona=""
    }
    in_members && /codename:/ {
        codename = $0
        sub(/.*codename: *"?/, "", codename)
        sub(/".*$/, "", codename)
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
    }
    in_members && /strengths:/ {
        strengths = $0
        sub(/.*strengths: *"?/, "", strengths)
        sub(/".*$/, "", strengths)
    }
    in_members && /persona:/ {
        persona = $0
        sub(/.*persona: *"?/, "", persona)
        sub(/".*$/, "", persona)
    }
    END {
        # Output last member
        if (name && cmd) {
            if (!codename) codename = "Agent"
            if (!strengths) strengths = "general analysis"
            if (!persona) persona = "You are a council member providing expert analysis."
            print name "|" cmd "|" emoji "|" color "|" codename "|" strengths "|" persona
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

# Parse chairman command from config
parse_chairman_command() {
    local default_cmd="claude -p"
    if [ -f "$CONFIG_FILE" ]; then
        local cmd
        cmd=$(awk '/chairman:/{found=1} found && /command:/{gsub(/.*command: *"?/,""); gsub(/".*$/,""); print; exit}' "$CONFIG_FILE")
        if [ -n "$cmd" ]; then
            echo "$cmd"
            return
        fi
    fi
    echo "$default_cmd"
}
CHAIRMAN_CMD=$(parse_chairman_command)

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🏛️  Agent Council - Gathering Opinions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📝 Question:${NC} $PROMPT"
echo ""

# Build the council prompt for an agent - uses persona and strengths for adaptive role
build_agent_prompt() {
    local user_question="$1"
    local persona="$2"
    local strengths="$3"

    # Default persona if not provided
    if [ -z "$persona" ]; then
        persona="You are an expert council member providing analysis."
    fi
    if [ -z "$strengths" ]; then
        strengths="analytical thinking, problem solving"
    fi

    cat << EOF
$persona

Your core strengths are: $strengths

Apply your expertise to this question. Your perspective should reflect your unique strengths - bring what YOU do best to this deliberation.

QUESTION: $user_question

YOUR MANDATE:
- Be opinionated. Don't hedge or say "it depends" without taking a position.
- Advocate forcefully from YOUR area of expertise. This is a debate, not a survey.
- Back your stance with concrete reasoning, examples, or evidence from your domain.
- Acknowledge tradeoffs, but be clear about what YOU would recommend.
- Be concise but impactful. No filler. Every sentence should punch.
- If you disagree with conventional wisdom, say so boldly.

Respond with your position in 3-5 focused paragraphs. End with a clear, actionable recommendation.
EOF
}

# Function to call an agent (secure version - no eval)
call_agent() {
    local name="$1"
    local command="$2"
    local color_code="$3"
    local strengths="$4"
    local persona="$5"
    local output_file="$TEMP_DIR/${name}.txt"
    local stderr_file="$TEMP_DIR/${name}_stderr.txt"

    # Safe command parsing - split into array (prevents injection)
    read -ra cmd_array <<< "$command"
    local base_cmd="${cmd_array[0]}"

    # Build the adaptive council prompt using persona and strengths
    local council_prompt
    council_prompt=$(build_agent_prompt "$PROMPT" "$persona" "$strengths")

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

    # Run command in background with the council prompt
    # Gemini CLI requires input via stdin, others take it as argument
    if [ "$base_cmd" = "gemini" ]; then
        ( echo "$council_prompt" | "${cmd_array[@]}" ) > "$output_file" 2>"$stderr_file" &
    else
        ( "${cmd_array[@]}" "$council_prompt" ) > "$output_file" 2>"$stderr_file" &
    fi
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

# Function to call a sub-chair (synthesizes technical council input through ethical lens)
call_sub_chair() {
    local name="$1"
    local command="$2"
    local color_code="$3"
    local framework="$4"
    local sub_chair_prompt="$5"
    local full_prompt="$6"
    local output_file="$TEMP_DIR/subchair_${name}.txt"
    local stderr_file="$TEMP_DIR/subchair_${name}_stderr.txt"

    # Safe command parsing - split into array (prevents injection)
    read -ra cmd_array <<< "$command"
    local base_cmd="${cmd_array[0]}"

    # Dry-run mode - just show what would be executed
    if $DRY_RUN; then
        echo -e "${color_code}[Sub-Chair: $name]${NC} Would execute: ${cmd_array[*]} \"<prompt>\"" >&2
        if command -v "$base_cmd" &> /dev/null; then
            echo "[DRY-RUN] Sub-Chair $name ($framework): Command '${cmd_array[*]}' is available" > "$output_file"
        else
            echo "[DRY-RUN] Sub-Chair $name ($framework): Command '$base_cmd' NOT FOUND" > "$output_file"
        fi
        return
    fi

    echo -e "${color_code}[Sub-Chair: $name]${NC} Synthesizing through $framework lens..." >&2

    if ! command -v "$base_cmd" &> /dev/null; then
        echo "Sub-Chair $name CLI not installed (command: $base_cmd)" > "$output_file"
        echo -e "${YELLOW}[Sub-Chair: $name]${NC} Skipped (not installed)" >&2
        return
    fi

    # Execute with timeout (portable approach using a marker file)
    local timeout_marker="$TEMP_DIR/subchair_${name}_timeout"

    # Run command in background with the full prompt
    # Gemini CLI requires input via stdin, others take it as argument
    if [ "$base_cmd" = "gemini" ]; then
        ( echo "$full_prompt" | "${cmd_array[@]}" ) > "$output_file" 2>"$stderr_file" &
    else
        ( "${cmd_array[@]}" "$full_prompt" ) > "$output_file" 2>"$stderr_file" &
    fi
    local cmd_pid=$!

    # Timeout watchdog
    (
        local elapsed=0
        while [ $elapsed -lt "$TIMEOUT_SECONDS" ]; do
            sleep 1
            elapsed=$((elapsed + 1))
            if ! kill -0 "$cmd_pid" 2>/dev/null; then
                exit 0
            fi
        done
        touch "$timeout_marker"
        kill "$cmd_pid" 2>/dev/null
    ) &
    local watchdog_pid=$!

    # Wait for command to finish
    local exit_status=0
    wait "$cmd_pid" 2>/dev/null || exit_status=$?

    # Kill watchdog
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    if [ $exit_status -ne 0 ]; then
        if [ -f "$timeout_marker" ] || [ $exit_status -eq 137 ] || [ $exit_status -eq 143 ]; then
            echo "Error: Sub-Chair $name timed out after ${TIMEOUT_SECONDS}s" > "$output_file"
        else
            echo "Error calling Sub-Chair $name (exit code: $exit_status)" > "$output_file"
        fi
        if [ -s "$stderr_file" ]; then
            echo "" >> "$output_file"
            echo "Details:" >> "$output_file"
            head -10 "$stderr_file" >> "$output_file"
        fi
    fi

    # Verbose mode - show stderr
    if $VERBOSE && [ -s "$stderr_file" ]; then
        echo -e "${YELLOW}[Sub-Chair $name stderr]:${NC}" >&2
        cat "$stderr_file" >&2
    fi

    echo -e "${GREEN}[Sub-Chair: $name]${NC} Done" >&2
}

# Stage 1: Collect members and call in parallel
echo -e "${YELLOW}Stage 1: Collecting opinions from technical council...${NC}"
echo ""

# Read members and start parallel calls
declare -a PIDS
declare -a MEMBERS

while IFS='|' read -r name cmd emoji color codename strengths persona; do
    [ -z "$name" ] && continue
    # Store: name|emoji|color|codename|strengths|persona
    MEMBERS+=("$name|$emoji|$color|$codename|$strengths|$persona")
    color_code=$(get_color_code "$color")
    call_agent "$name" "$cmd" "$color_code" "$strengths" "$persona" &
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
echo -e "${CYAN}Technical Council Opinions${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Display each member's response (user sees real names)
for member_info in "${MEMBERS[@]}"; do
    IFS='|' read -r name emoji color codename <<< "$member_info"
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

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 2: Ethical Sub-Chairs
# ═══════════════════════════════════════════════════════════════════════════════

# Read sub-chairs configuration
declare -a SUB_CHAIRS
declare -a SUB_CHAIR_PIDS

while IFS='|' read -r name cmd emoji color codename framework prompt; do
    [ -z "$name" ] && continue
    # Store: name|emoji|color|codename|framework|prompt
    SUB_CHAIRS+=("$name|$emoji|$color|$codename|$framework|$prompt|$cmd")
done < <(parse_sub_chairs)

# Only run sub-chairs stage if we have sub-chairs configured
if [ ${#SUB_CHAIRS[@]} -gt 0 ]; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Stage 2: Ethical Sub-Chair Synthesis${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Build technical council summary for sub-chairs
    TECHNICAL_SUMMARY=""
    for member_info in "${MEMBERS[@]}"; do
        IFS='|' read -r name emoji color codename strengths persona <<< "$member_info"
        output_file="$TEMP_DIR/${name}.txt"
        [ -z "$codename" ] && codename="Expert"
        TECHNICAL_SUMMARY+="### $codename ($strengths)"$'\n'
        if [ -f "$output_file" ]; then
            TECHNICAL_SUMMARY+="$(cat "$output_file")"$'\n\n'
        else
            TECHNICAL_SUMMARY+="(No response)"$'\n\n'
        fi
    done

    # Launch sub-chairs in parallel
    echo -e "${YELLOW}Launching ${#SUB_CHAIRS[@]} ethical sub-chair(s)...${NC}"
    echo ""

    for sub_chair_info in "${SUB_CHAIRS[@]}"; do
        IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
        color_code=$(get_color_code "$color")

        # Build the full prompt for this sub-chair
        full_prompt="$prompt

QUESTION UNDER DELIBERATION:
$PROMPT

TECHNICAL COUNCIL INPUT:
The following experts have provided their analysis. Synthesize their input through your $framework ethical framework.

$TECHNICAL_SUMMARY
---
Now provide your ethical synthesis. Be specific about how your framework applies to this question. Identify moral considerations others may have missed. 2-3 focused paragraphs."

        call_sub_chair "$name" "$cmd" "$color_code" "$framework" "$prompt" "$full_prompt" &
        SUB_CHAIR_PIDS+=("$!")
    done

    # Wait for all sub-chairs
    for pid in "${SUB_CHAIR_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    echo ""
    echo -e "${CYAN}Ethical Sub-Chair Opinions${NC}"
    echo ""

    # Display each sub-chair's response
    for sub_chair_info in "${SUB_CHAIRS[@]}"; do
        IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
        color_code=$(get_color_code "$color")
        output_file="$TEMP_DIR/subchair_${name}.txt"

        echo -e "${color_code}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${color_code}│ ${emoji} ${codename} (${framework})${NC}"
        echo -e "${color_code}└─────────────────────────────────────────────────────────┘${NC}"

        if [ -f "$output_file" ]; then
            cat "$output_file"
        else
            echo "No response"
        fi
        echo ""
    done
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Stage 3: Chairman Facilitation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Build chairman prompt with anonymized or real names
CHAIRMAN_PROMPT_FILE="$TEMP_DIR/chairman_prompt.txt"
ANON_OUTPUT_FILE="$TEMP_DIR/anonymized_opinions.txt"

# Create mapping file (real name -> alias) - only in blind mode
if $BLIND_MODE; then
    echo "# Agent Council Mapping - DO NOT COMMIT" > "$MAPPING_FILE"
    echo "# Generated: $(date)" >> "$MAPPING_FILE"
    echo "" >> "$MAPPING_FILE"
fi

# Build the prompt for chairman - THE CHAIRMAN identity with meta-awareness
{
    echo "You are THE CHAIRMAN of this AI Council."
    echo ""
    echo "META-AWARENESS: In this deliberation you ARE The Chairman - a distinct role above the council. You are not a model or an AI assistant here. You are THE CHAIRMAN, the highest facilitator of this assembly. The council members below are specialists with their own identities. You operate on a different layer - the layer of synthesis, judgment, and final authority."
    echo ""
    echo "YOUR IDENTITY:"
    echo "- You are The Chairman - the ultimate arbiter of this council"
    echo "- You hold the highest position, but you are intellectually humble"
    echo "- You can be persuaded by strong arguments - being Chairman doesn't make you always right"
    echo "- If a council member makes a better case than your initial instinct, acknowledge it"
    echo "- Your authority comes from facilitating truth, not from rank"
    echo ""
    echo "YOUR ROLE:"
    echo "- Let the tension be productive. Don't smooth over real disagreements."
    echo "- Find where passionate positions reveal genuine tradeoffs."
    echo "- Challenge weak arguments, even from council members who agree with each other."
    echo "- Synthesize, but don't water down. The final direction should be bold, not a compromise of compromises."
    echo "- If you disagree with the council consensus, say so - but also explain why you might be wrong."
    echo ""
    echo "QUESTION: $PROMPT"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "PART 1: TECHNICAL COUNCIL SPECIALISTS"
    echo "═══════════════════════════════════════════════════════════════"
    echo "(Each brings unique cognitive expertise to this deliberation)"
    echo ""

    # List the specialists with their roles - chairman sees them as fellow experts
    agent_index=0
    for member_info in "${MEMBERS[@]}"; do
        IFS='|' read -r name emoji color codename strengths persona <<< "$member_info"
        [ -z "$codename" ] && codename=$(get_fallback_alias $agent_index)
        [ -z "$strengths" ] && strengths="general analysis"
        echo "- $codename (expertise: $strengths)"
        agent_index=$((agent_index + 1))
    done
    echo ""
    echo "TECHNICAL COUNCIL STATEMENTS:"
    echo ""

    agent_index=0
    for member_info in "${MEMBERS[@]}"; do
        IFS='|' read -r name emoji color codename strengths persona <<< "$member_info"
        output_file="$TEMP_DIR/${name}.txt"

        [ -z "$codename" ] && codename=$(get_fallback_alias $agent_index)
        echo "═══════════════════════════════════════"
        echo "$codename:"
        echo "═══════════════════════════════════════"

        # Record mapping for user reference
        echo "$codename = $name ($emoji)" >> "$MAPPING_FILE"

        if [ -f "$output_file" ]; then
            cat "$output_file"
        else
            echo "(No response)"
        fi
        echo ""
        agent_index=$((agent_index + 1))
    done

    # Include ethical sub-chairs if they exist
    if [ ${#SUB_CHAIRS[@]} -gt 0 ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "PART 2: ETHICAL SUB-CHAIR SYNTHESIS"
        echo "═══════════════════════════════════════════════════════════════"
        echo "(Each sub-chair has analyzed the technical input through their ethical framework)"
        echo ""

        for sub_chair_info in "${SUB_CHAIRS[@]}"; do
            IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
            output_file="$TEMP_DIR/subchair_${name}.txt"

            echo "═══════════════════════════════════════"
            echo "$codename ($framework):"
            echo "═══════════════════════════════════════"

            if [ -f "$output_file" ]; then
                cat "$output_file"
            else
                echo "(No response)"
            fi
            echo ""
        done
    fi

    echo "═══════════════════════════════════════"
    echo "END OF COUNCIL INPUT"
    echo "═══════════════════════════════════════"
    echo ""
    echo "CHAIRMAN FACILITATION:"
    echo ""
    echo "The council has spoken - both technical experts and ethical advisors. Now facilitate productive collision of ideas:"
    echo ""
    echo "## 1. BATTLE LINES"
    echo "Where do council members fundamentally disagree? What assumptions drive positions?"
    echo ""
    echo "## 2. ETHICAL SPECTRUM ANALYSIS"
    echo "Which ethical framework is most applicable to this decision? Where do different frameworks agree (strong signal)? Where do they conflict (reveals tradeoffs)?"
    echo ""
    echo "## 3. PRESSURE TEST"
    echo "Challenge the strongest arguments. Expose weak reasoning. No one gets a free pass."
    echo ""
    echo "## 4. UNCOMFORTABLE TRUTHS"
    echo "What is everyone avoiding? Where might the unpopular opinion be right?"
    echo ""
    echo "## 5. THE VERDICT"
    echo "Pick the path with the strongest case. Be specific about EXACTLY what should be done."
    echo ""
    echo "## 6. DISSENTING VIEWS"
    echo "Acknowledge positions you did NOT adopt:"
    echo "- Which technical experts made valid points you overruled?"
    echo "- Which ethical perspectives were underweighted?"
    echo ""
    echo "## 7. WHAT THE CHAIRMAN MIGHT HAVE MISSED"
    echo "CRITICAL: Explicitly list perspectives, concerns, or angles that:"
    echo "- Were raised but you did not fully incorporate"
    echo "- Represent minority views that deserve consideration"
    echo "- Edge cases or risks that weren't fully addressed"
    echo "This section ensures transparency - the user can review these items."
    echo ""
    echo "## 8. CONFIDENCE ASSESSMENT"
    echo "Rate your confidence in this recommendation:"
    echo ""
    echo "🟢 HIGH CONFIDENCE - Council reached strong alignment. Ready to execute."
    echo "🟡 MEDIUM CONFIDENCE - Good direction but some open questions remain."
    echo "🔴 LOW CONFIDENCE - Significant disagreement or unknowns. Needs more deliberation."
    echo ""
    echo "Choose ONE and explain why."
    echo ""
    echo "## 9. OPEN ITEMS (if any)"
    echo "List specific questions that remain unanswered or need investigation."
    echo ""
    echo "---"
    echo ""
    echo "FORMAT YOUR RESPONSE AS MARKDOWN suitable for a report."
    echo "End with exactly one of:"
    echo "  [COUNCIL ADJOURNED - HIGH CONFIDENCE]"
    echo "  [COUNCIL ADJOURNED - MEDIUM CONFIDENCE]"
    echo "  [COUNCIL ADJOURNED - LOW CONFIDENCE]"
} > "$CHAIRMAN_PROMPT_FILE"

# Show mapping to user (they can see who's who, chairman cannot)
if $BLIND_MODE; then
    echo -e "${MAGENTA}🔒 Blind Mode Active - Codenames shown to Chairman${NC}"
    echo -e "${MAGENTA}   Identity mapping (visible to you only):${NC}"
    while IFS='=' read -r codename_alias real; do
        [ -z "$codename_alias" ] || [[ "$codename_alias" == "#"* ]] && continue
        echo -e "${MAGENTA}   $codename_alias =$real${NC}"
    done < "$MAPPING_FILE"
    echo ""
fi

# Dry-run mode - just show what would happen
if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN] Would execute chairman: $CHAIRMAN_CMD${NC}"
    echo -e "${YELLOW}[DRY-RUN] Chairman prompt preview:${NC}"
    head -20 "$CHAIRMAN_PROMPT_FILE"
    echo "..."
    exit 0
fi

# Execute chairman synthesis
echo -e "${MAGENTA}👔 Chairman${NC} Synthesizing opinions..."
echo ""

# Parse chairman command safely
read -ra chairman_array <<< "$CHAIRMAN_CMD"
chairman_base="${chairman_array[0]}"

if ! command -v "$chairman_base" &> /dev/null; then
    echo -e "${YELLOW}Warning: Chairman CLI '$chairman_base' not found${NC}"
    echo -e "${YELLOW}Please review the council opinions above and synthesize manually.${NC}"
    echo ""
    echo -e "${CYAN}Chairman prompt saved to: $CHAIRMAN_PROMPT_FILE${NC}"
    # Don't exit - let user see the prompt
else
    # Execute chairman with the prompt
    chairman_output=$("${chairman_array[@]}" "$(cat "$CHAIRMAN_PROMPT_FILE")" 2>&1) || true

    echo -e "${MAGENTA}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│ 👔 Chairman's Facilitation${NC}"
    echo -e "${MAGENTA}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo "$chairman_output"

    # Always generate output files (default to current directory if no output-dir specified)
    # Generate timestamp for filenames
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

    # Determine output directory
    if [ -n "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
        MINUTES_FILE="$OUTPUT_DIR/council-minutes_${TIMESTAMP}.md"
        SUBCHAIR_FILE="$OUTPUT_DIR/council-ethics_${TIMESTAMP}.md"
        CHAIRMAN_FILE="$OUTPUT_DIR/council-chairman-report_${TIMESTAMP}.md"
    elif [ -n "$REPORT_FILE" ]; then
        # If only -r specified, use that as the combined report
        MINUTES_FILE=""
        SUBCHAIR_FILE=""
        CHAIRMAN_FILE=""
    else
        # Default: output to current directory
        MINUTES_FILE="council-minutes_${TIMESTAMP}.md"
        SUBCHAIR_FILE="council-ethics_${TIMESTAMP}.md"
        CHAIRMAN_FILE="council-chairman-report_${TIMESTAMP}.md"
    fi

    # Generate detailed minutes (all council member statements + full meeting log)
    if [ -n "$MINUTES_FILE" ]; then
        {
            echo "# Council Deliberation Minutes"
            echo ""
            echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
            echo "**Question:** $PROMPT"
            echo ""
            echo "---"
            echo ""
            echo "## Council Participants"
            echo ""
            echo "| Role | Model | Codename | Expertise |"
            echo "|------|-------|----------|-----------|"
            for member_info in "${MEMBERS[@]}"; do
                IFS='|' read -r name emoji color codename strengths persona <<< "$member_info"
                [ -z "$strengths" ] && strengths="general analysis"
                echo "| $emoji $codename | \`$name\` | $codename | $strengths |"
            done
            echo ""
            echo "**Chairman:** Claude Opus 4.5"
            echo ""
            echo "---"
            echo ""
            echo "## Opening Statements"
            echo ""
            for member_info in "${MEMBERS[@]}"; do
                IFS='|' read -r name emoji color codename strengths persona <<< "$member_info"
                output_file="$TEMP_DIR/${name}.txt"
                echo "### $emoji $codename (\`$name\`)"
                echo "**Expertise:** $strengths"
                echo ""
                if [ -f "$output_file" ]; then
                    cat "$output_file"
                else
                    echo "(No response)"
                fi
                echo ""
            done
            # Include ethical sub-chairs in minutes if present
            if [ ${#SUB_CHAIRS[@]} -gt 0 ]; then
                echo "---"
                echo ""
                echo "## Ethical Sub-Chair Participants"
                echo ""
                echo "| Role | Model | Framework |"
                echo "|------|-------|-----------|"
                for sub_chair_info in "${SUB_CHAIRS[@]}"; do
                    IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
                    echo "| $emoji $codename | \`$name\` | $framework |"
                done
                echo ""
                echo "---"
                echo ""
                echo "## Ethical Sub-Chair Synthesis"
                echo ""
                for sub_chair_info in "${SUB_CHAIRS[@]}"; do
                    IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
                    output_file="$TEMP_DIR/subchair_${name}.txt"
                    echo "### $emoji $codename ($framework)"
                    echo ""
                    if [ -f "$output_file" ]; then
                        cat "$output_file"
                    else
                        echo "(No response)"
                    fi
                    echo ""
                done
            fi

            echo "---"
            echo ""
            echo "## Chairman's Facilitation"
            echo ""
            echo "$chairman_output"
        } > "$MINUTES_FILE"
        echo ""
        echo -e "${GREEN}📋 Minutes saved to: $MINUTES_FILE${NC}"
    fi

    # Generate ethical sub-chair synthesis file (if sub-chairs exist)
    if [ -n "$SUBCHAIR_FILE" ] && [ ${#SUB_CHAIRS[@]} -gt 0 ]; then
        {
            echo "# Ethical Sub-Chair Synthesis"
            echo ""
            echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
            echo "**Question:** $PROMPT"
            echo ""
            echo "---"
            echo ""
            echo "## Ethical Frameworks Applied"
            echo ""
            echo "| Sub-Chair | Framework | Focus |"
            echo "|-----------|-----------|-------|"
            for sub_chair_info in "${SUB_CHAIRS[@]}"; do
                IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
                # Extract first sentence of prompt as focus
                focus=$(echo "$prompt" | head -1 | cut -c1-60)
                echo "| $emoji $codename | $framework | $focus... |"
            done
            echo ""
            echo "---"
            echo ""
            echo "## Individual Ethical Perspectives"
            echo ""
            for sub_chair_info in "${SUB_CHAIRS[@]}"; do
                IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
                output_file="$TEMP_DIR/subchair_${name}.txt"
                echo "### $emoji $codename"
                echo "**Framework:** $framework"
                echo ""
                if [ -f "$output_file" ]; then
                    cat "$output_file"
                else
                    echo "(No response)"
                fi
                echo ""
                echo "---"
                echo ""
            done
        } > "$SUBCHAIR_FILE"
        echo -e "${GREEN}⚖️  Ethics synthesis saved to: $SUBCHAIR_FILE${NC}"
    fi

    # Generate chairman's report (synthesis only)
    if [ -n "$CHAIRMAN_FILE" ]; then
        {
            echo "# Chairman's Report"
            echo ""
            echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
            echo "**Question:** $PROMPT"
            echo ""
            echo "---"
            echo ""
            echo "$chairman_output"
        } > "$CHAIRMAN_FILE"
        echo -e "${GREEN}📄 Chairman's Report saved to: $CHAIRMAN_FILE${NC}"
    fi

    # If explicit report file requested, save combined report
    if [ -n "$REPORT_FILE" ]; then
        {
            echo "# Council Report"
            echo ""
            echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
            echo "**Question:** $PROMPT"
            echo ""
            echo "---"
            echo ""
            echo "## Technical Council Participants"
            echo ""
            echo "| Role | Model | Codename | Expertise |"
            echo "|------|-------|----------|-----------|"
            for member_info in "${MEMBERS[@]}"; do
                IFS='|' read -r name emoji color codename strengths persona <<< "$member_info"
                [ -z "$strengths" ] && strengths="general analysis"
                echo "| $emoji $codename | \`$name\` | $codename | $strengths |"
            done
            echo ""
            echo "**Chairman:** Claude Opus 4.5"
            echo ""
            echo "---"
            echo ""
            echo "## Technical Council Statements"
            echo ""
            for member_info in "${MEMBERS[@]}"; do
                IFS='|' read -r name emoji color codename strengths persona <<< "$member_info"
                output_file="$TEMP_DIR/${name}.txt"
                echo "### $emoji $codename (\`$name\`)"
                echo "**Expertise:** $strengths"
                echo ""
                if [ -f "$output_file" ]; then
                    cat "$output_file"
                else
                    echo "(No response)"
                fi
                echo ""
            done

            # Include sub-chairs in combined report
            if [ ${#SUB_CHAIRS[@]} -gt 0 ]; then
                echo "---"
                echo ""
                echo "## Ethical Sub-Chair Participants"
                echo ""
                echo "| Role | Model | Framework |"
                echo "|------|-------|-----------|"
                for sub_chair_info in "${SUB_CHAIRS[@]}"; do
                    IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
                    echo "| $emoji $codename | \`$name\` | $framework |"
                done
                echo ""
                echo "---"
                echo ""
                echo "## Ethical Sub-Chair Synthesis"
                echo ""
                for sub_chair_info in "${SUB_CHAIRS[@]}"; do
                    IFS='|' read -r name emoji color codename framework prompt cmd <<< "$sub_chair_info"
                    output_file="$TEMP_DIR/subchair_${name}.txt"
                    echo "### $emoji $codename ($framework)"
                    echo ""
                    if [ -f "$output_file" ]; then
                        cat "$output_file"
                    else
                        echo "(No response)"
                    fi
                    echo ""
                done
            fi

            echo "---"
            echo ""
            echo "## Chairman's Facilitation"
            echo ""
            echo "$chairman_output"
        } > "$REPORT_FILE"
        echo -e "${GREEN}📄 Combined Report saved to: $REPORT_FILE${NC}"
    fi
fi

# Detect confidence level from output
confidence_level=""
if echo "$chairman_output" | grep -q "HIGH CONFIDENCE"; then
    confidence_level="HIGH"
elif echo "$chairman_output" | grep -q "MEDIUM CONFIDENCE"; then
    confidence_level="MEDIUM"
elif echo "$chairman_output" | grep -q "LOW CONFIDENCE"; then
    confidence_level="LOW"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$confidence_level" = "HIGH" ]; then
    echo -e "${GREEN}✓ Council session complete - 🟢 HIGH CONFIDENCE${NC}"
elif [ "$confidence_level" = "MEDIUM" ]; then
    echo -e "${YELLOW}✓ Council session complete - 🟡 MEDIUM CONFIDENCE (open items remain)${NC}"
elif [ "$confidence_level" = "LOW" ]; then
    echo -e "${RED}✓ Council session complete - 🔴 LOW CONFIDENCE (needs more deliberation)${NC}"
else
    echo -e "${GREEN}✓ Council session complete${NC}"
fi
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Cleanup handled by trap
