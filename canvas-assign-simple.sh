#!/bin/bash

# Simple Canvas Assignment Creator
# A streamlined tool for creating assignments in Canvas LMS via API

# Configuration
readonly SCRIPT_NAME="Simple Canvas Assignment Creator"
readonly VERSION="1.0.0"
readonly CONFIG_DIR="$HOME/.canvas-config"
readonly CONFIG_FILE="$CONFIG_DIR/config"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Global variables
CANVAS_URL=""
API_TOKEN=""

# Output functions
info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warning() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }

# Check dependencies
check_dependencies() {
    for cmd in curl jq; do
        if ! command -v $cmd >/dev/null 2>&1; then
            error "Missing dependency: $cmd"
            echo "Please install: $cmd"
            exit 1
        fi
    done
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# Save configuration
save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
CANVAS_URL="$CANVAS_URL"
API_TOKEN="$API_TOKEN"
EOF
    chmod 600 "$CONFIG_FILE"
}

# Make Canvas API request
canvas_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local curl_args=(
        -s -w "%{http_code}"
        -H "Authorization: Bearer $API_TOKEN"
        -H "Content-Type: application/json"
        -X "$method"
    )
    
    [[ -n "$data" ]] && curl_args+=(-d "$data")
    
    local response_file=$(mktemp)
    local http_code
    http_code=$(curl "${curl_args[@]}" "$CANVAS_URL/api/v1$endpoint" -o "$response_file")
    
    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        cat "$response_file"
        rm -f "$response_file"
        return 0
    else
        error "API Error ($http_code)"
        rm -f "$response_file"
        return 1
    fi
}

# Test API connection
test_api_connection() {
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $API_TOKEN" \
        "$CANVAS_URL/api/v1/users/self" -o /dev/null)
    [[ "$response" == "200" ]]
}

# Setup Canvas connection
setup_canvas() {
    echo -e "\n${BOLD}${CYAN}Canvas Setup${NC}"
    echo "============"
    
    read -r -p "Canvas URL: " CANVAS_URL
    CANVAS_URL="${CANVAS_URL%/}"
    
    read -r -s -p "API Token: " API_TOKEN
    echo
    
    if test_api_connection; then
        success "Connection successful!"
        save_config
        return 0
    else
        error "Connection failed"
        return 1
    fi
}

# Get favorited courses
get_courses() {
    info "Fetching your courses..."
    
    local courses_data
    if ! courses_data=$(canvas_api GET "/courses?enrollment_state=active&include[]=favorites&per_page=20"); then
        error "Failed to fetch courses"
        return 1
    fi
    
    # Try favorited courses first
    local favorited_courses
    favorited_courses=$(echo "$courses_data" | jq '[.[] | select(.is_favorite == true)]')
    local favorite_count=$(echo "$favorited_courses" | jq length)
    
    if [[ "$favorite_count" -gt 0 ]]; then
        echo "$favorited_courses"
        success "Found $favorite_count favorited courses"
    else
        echo "$courses_data"
        success "Found $(echo "$courses_data" | jq length) courses"
    fi
}

# Select course
select_course() {
    local courses_data="$1"
    local course_count=$(echo "$courses_data" | jq length)
    
    echo -e "\n${BOLD}Select a Course:${NC}"
    echo "$courses_data" | jq -r 'to_entries[] | "\(.key + 1). \(.value.name) (\(.value.course_code))"'
    
    while true; do
        read -r -p "Enter course number (1-$course_count): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 && "$choice" -le "$course_count" ]]; then
            local index=$((choice - 1))
            echo "$courses_data" | jq -r ".[$index].id"
            return 0
        else
            error "Please enter a valid number between 1 and $course_count"
        fi
    done
}

# Create assignment
create_assignment() {
    local course_id="$1"
    
    echo -e "\n${BOLD}Assignment Details:${NC}"
    echo "==================="
    
    read -r -p "Assignment name: " assignment_name
    [[ -z "$assignment_name" ]] && { error "Assignment name required"; return 1; }
    
    read -r -p "Points possible (default: 10): " points_possible
    points_possible="${points_possible:-10}"
    
    echo -e "\nSubmission Types:"
    echo "1. Online text entry"
    echo "2. Online upload" 
    echo "3. Both text and upload"
    
    read -r -p "Choose submission type (1-3): " sub_choice
    case $sub_choice in
        1) submission_types="online_text_entry" ;;
        2) submission_types="online_upload" ;;
        3) submission_types="online_text_entry,online_upload" ;;
        *) submission_types="online_text_entry" ;;
    esac
    
    read -r -p "Publish immediately? (Y/n): " publish
    published="true"
    [[ "$publish" == "n" || "$publish" == "N" ]] && published="false"
    
    # Build assignment data
    local assignment_data="{
        \"assignment\": {
            \"name\": \"$assignment_name\",
            \"points_possible\": $points_possible,
            \"grading_type\": \"points\",
            \"submission_types\": [\"$(echo "$submission_types" | sed 's/,/","/g')\"],
            \"published\": $published
        }
    }"
    
    echo -e "\n${BOLD}Creating assignment...${NC}"
    
    local response
    if response=$(canvas_api POST "/courses/$course_id/assignments" "$assignment_data"); then
        local assignment_id assignment_url
        assignment_id=$(echo "$response" | jq -r '.id')
        assignment_url="$CANVAS_URL/courses/$course_id/assignments/$assignment_id"
        
        success "Assignment '$assignment_name' created!"
        info "URL: $assignment_url"
        return 0
    else
        error "Failed to create assignment"
        return 1
    fi
}

# Main function
main() {
    echo -e "${BOLD}${CYAN}$SCRIPT_NAME v$VERSION${NC}\n"
    
    check_dependencies
    load_config
    
    # Setup if needed
    if [[ -z "$CANVAS_URL" || -z "$API_TOKEN" ]] || ! test_api_connection; then
        setup_canvas || exit 1
    fi
    
    # Get courses
    local courses_data
    if ! courses_data=$(get_courses); then
        exit 1
    fi
    
    # Select course
    local course_id
    if ! course_id=$(select_course "$courses_data"); then
        exit 1
    fi
    
    # Create assignment
    create_assignment "$course_id"
}

main "$@"