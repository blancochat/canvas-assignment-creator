#!/bin/bash

# Canvas LMS Assignment Creator
# A comprehensive tool for creating assignments in Canvas LMS via API
# Author: Generated with Claude Code
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="Canvas Assignment Creator"
readonly VERSION="1.0.0"
readonly CONFIG_DIR="$HOME/.canvas-config"
readonly CONFIG_FILE="$CONFIG_DIR/config"
readonly COURSES_CACHE="$CONFIG_DIR/courses_cache"
readonly LOG_FILE="$CONFIG_DIR/canvas-assign.log"
readonly IMAGES_DIR="$CONFIG_DIR/images"
readonly FILES_DIR="$CONFIG_DIR/files"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Global variables
CANVAS_URL=""
API_TOKEN=""
SELECTED_COURSE_IDS=()
SELECTED_COURSE_NAMES=()
VERBOSE=false
DRY_RUN=false

# Dependency check
check_dependencies() {
    local missing_deps=()
    
    command -v curl >/dev/null 2>&1 || missing_deps+=("curl")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo -e "${YELLOW}Please install the missing dependencies:${NC}"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                curl) echo "  - curl: sudo apt-get install curl (Ubuntu/Debian) or brew install curl (macOS)" ;;
                jq) echo "  - jq: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)" ;;
            esac
        done
        exit 1
    fi
}

# Logging functions
log() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2
    fi
}

info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO: $*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS: $*"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARNING: $*"
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
    log "ERROR: $*"
}

progress() {
    echo -e "${PURPLE}▶${NC} $*"
    log "PROGRESS: $*"
}

# Create configuration directory
init_config() {
    mkdir -p "$CONFIG_DIR" || { echo "Failed to create CONFIG_DIR"; return 1; }
    mkdir -p "$IMAGES_DIR" || { echo "Failed to create IMAGES_DIR"; return 1; }
    mkdir -p "$FILES_DIR" || { echo "Failed to create FILES_DIR"; return 1; }
    touch "$LOG_FILE" || { echo "Failed to create LOG_FILE"; return 1; }
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            # Skip empty lines and comments
            [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
            
            case $key in
                CANVAS_URL) CANVAS_URL="$value" ;;
                API_TOKEN) API_TOKEN="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

# Save configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
CANVAS_URL=$CANVAS_URL
API_TOKEN=$API_TOKEN
EOF
    chmod 600 "$CONFIG_FILE"
    success "Configuration saved"
}

# Validate Canvas URL
validate_canvas_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        url="https://$url"
    fi
    
    # Enforce HTTPS for Canvas URLs
    if [[ "$url" =~ ^http://(.*)$ ]]; then
        url="https://${BASH_REMATCH[1]}"
        info "🔒 Automatically upgraded Canvas URL to HTTPS for security"
    fi
    
    url="${url%/}"
    
    if ! curl -s --head "$url" > /dev/null 2>&1; then
        return 1
    fi
    
    echo "$url"
}

# Test API connection
test_api_connection() {
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $API_TOKEN" \
        "$CANVAS_URL/api/v1/users/self" -o /dev/null)
    
    if [[ "$response" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

# Setup Canvas connection
setup_canvas() {
    echo -e "\n${BOLD}${CYAN}Canvas LMS Setup${NC}"
    echo "=================================="
    
    if [[ -z "$CANVAS_URL" ]]; then
        echo -e "\nEnter your Canvas instance URL:"
        echo -e "${YELLOW}Example: https://university.instructure.com${NC}"
        read -r -p "Canvas URL: " input_url
        
        progress "Validating Canvas URL..."
        if CANVAS_URL=$(validate_canvas_url "$input_url"); then
            success "Canvas URL validated: $CANVAS_URL"
        else
            error "Invalid Canvas URL or unreachable"
            return 1
        fi
    fi
    
    if [[ -z "$API_TOKEN" ]]; then
        echo -e "\nEnter your Canvas API token:"
        echo -e "${YELLOW}You can generate one in Canvas: Account → Settings → Approved Integrations${NC}"
        read -r -s -p "API Token: " API_TOKEN
        echo
    fi
    
    progress "Testing API connection..."
    if test_api_connection; then
        success "API connection successful"
        
        read -r -p "Save these settings? (Y/n): " save_choice
        if [[ "$save_choice" != "n" && "$save_choice" != "N" ]]; then
            save_config
        fi
        return 0
    else
        error "API connection failed. Please check your token and try again."
        API_TOKEN=""
        return 1
    fi
}

# Make Canvas API request
canvas_api() {
    local method="${1:-GET}"
    local endpoint="$2"
    local data="${3:-}"
    
    local response_file error_file
    response_file=$(mktemp)
    error_file=$(mktemp)
    
    local curl_args=(
        -s -w "%{http_code}"
        -H "Authorization: Bearer $API_TOKEN"
        -H "Content-Type: application/json"
        -X "$method"
    )
    
    [[ -n "$data" ]] && curl_args+=(-d "$data")
    
    # DEBUG: Log comprehensive request details
    log "========== Canvas API Debug =========="
    log "Method: $method"
    log "Endpoint: $endpoint"
    log "Full URL: $CANVAS_URL/api/v1$endpoint"
    log "Headers: Authorization: Bearer [REDACTED], Content-Type: application/json"
    
    if [[ -n "$data" ]]; then
        log "Request Body (first 1000 chars):"
        log "${data:0:1000}..."
        log "Request Body Length: ${#data}"
        
        # Validate JSON before sending
        if echo "$data" | jq . > /dev/null 2>&1; then
            log "✓ Request JSON is valid"
        else
            log "✗ Request JSON is INVALID:"
            echo "$data" | jq . 2>&1 | head -10 | while read -r line; do
                log "JSON Error: $line"
            done
        fi
    fi
    
    local http_code
    http_code=$(curl "${curl_args[@]}" "$CANVAS_URL/api/v1$endpoint" -o "$response_file" 2>"$error_file")
    
    log "HTTP Response Code: $http_code"
    
    # Log curl errors if any
    if [[ -s "$error_file" ]]; then
        log "cURL Errors:"
        cat "$error_file" | while read -r line; do
            log "cURL: $line"
        done
    fi
    
    # Log response details
    if [[ -f "$response_file" ]] && [[ -s "$response_file" ]]; then
        local response_size
        response_size=$(wc -c < "$response_file")
        log "Response Size: $response_size bytes"
        log "Response Body (first 500 chars):"
        head -c 500 "$response_file" | while read -r line; do
            log "Response: $line"
        done
    else
        log "No response body received"
    fi
    
    log "======================================"
    
    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        cat "$response_file"
        rm -f "$response_file" "$error_file"
        return 0
    else
        local error_msg response_content
        response_content=$(cat "$response_file" 2>/dev/null)
        
        # Try to parse structured error messages
        error_msg=$(echo "$response_content" | jq -r '.errors[]?.message // .message // "Unknown error"' 2>/dev/null)
        
        if [[ "$error_msg" == "Unknown error" ]] && [[ -n "$response_content" ]]; then
            error_msg="$response_content"
        fi
        
        # Log detailed error information
        log "API Error Details:"
        log "HTTP Code: $http_code"
        log "Error Message: $error_msg"
        log "Full Response: $response_content"
        
        error "API Error ($http_code): $error_msg"
        rm -f "$response_file" "$error_file"
        return 1
    fi
}

# Get favorited courses only
get_favorited_courses() {
    progress "Fetching your favorited courses..."
    
    local courses_data favorited_courses
    
    # Get courses with favorites information
    if ! courses_data=$(canvas_api GET "/courses?enrollment_state=active&include[]=favorites&per_page=100"); then
        error "Failed to fetch courses"
        return 1
    fi
    
    # Filter for favorited courses only
    favorited_courses=$(echo "$courses_data" | jq '[.[] | select(.is_favorite == true)]')
    local favorite_count
    favorite_count=$(echo "$favorited_courses" | jq length)
    
    if [[ "$favorite_count" -gt 0 ]]; then
        echo "$favorited_courses" > "$COURSES_CACHE"
        success "Fetched $favorite_count favorited courses"
        return 0
    else
        warning "No favorited courses found"
        info "To favorite courses, visit Canvas and star the courses you use most often."
        return 1
    fi
}

# Get all active courses
get_all_courses() {
    progress "Fetching all active courses..."
    
    local courses_data
    if ! courses_data=$(canvas_api GET "/courses?enrollment_state=active&per_page=20"); then
        error "Failed to fetch courses"
        return 1
    fi
    
    echo "$courses_data" > "$COURSES_CACHE"
    local total_count
    total_count=$(echo "$courses_data" | jq length)
    success "Fetched $total_count active courses"
}

# Get user's courses (favorited first, then all if no favorites)
get_courses() {
    if get_favorited_courses; then
        return 0
    else
        info "Showing all active courses instead"
        get_all_courses
    fi
}

# Display courses menu
display_courses() {
    local courses_data
    if [[ ! -f "$COURSES_CACHE" ]] || ! courses_data=$(cat "$COURSES_CACHE"); then
        get_courses || return 1
        courses_data=$(cat "$COURSES_CACHE")
    fi
    
    local course_count
    course_count=$(echo "$courses_data" | jq length)
    
    # Check if these are favorited courses or all courses
    local has_favorites
    has_favorites=$(echo "$courses_data" | jq -r '.[0].is_favorite // false')
    
    if [[ "$has_favorites" == "true" ]]; then
        echo -e "\n${BOLD}${CYAN}Select a Favorited Course${NC}"
        echo "========================="
        info "Showing your starred/favorited courses only"
    else
        echo -e "\n${BOLD}${CYAN}Select a Course${NC}"
        echo "==============="
        warning "Showing all active courses (no favorites set)"
    fi
    
    if [[ "$course_count" -eq 0 ]]; then
        warning "No active courses found"
        return 1
    fi
    
    echo
    echo "$courses_data" | jq -r 'to_entries[] | "\(.key + 1). \(.value.name) (\(.value.course_code))"'
    
    echo -e "\nOptions:"
    if [[ "$has_favorites" == "true" ]]; then
        echo "a) Show all active courses"
    else
        echo "f) Show favorited courses only"
    fi
    echo "r) Refresh course list"
    echo "q) Quit"
    
    while true; do
        read -r -p "Enter choice: " choice
        
        case $choice in
            [1-9]|[1-9][0-9]|[1-9][0-9][0-9])
                local index=$((choice - 1))
                if [[ "$index" -lt "$course_count" ]]; then
                    SELECTED_COURSE_ID=$(echo "$courses_data" | jq -r ".[$index].id")
                    SELECTED_COURSE_NAME=$(echo "$courses_data" | jq -r ".[$index].name")
                    success "Selected: $SELECTED_COURSE_NAME"
                    return 0
                else
                    error "Invalid course number. Please try again."
                fi
                ;;
            a|A)
                if [[ "$has_favorites" == "true" ]]; then
                    get_all_courses || return 1
                    display_courses
                    return $?
                else
                    error "Invalid choice. Please try again."
                fi
                ;;
            f|F)
                if [[ "$has_favorites" != "true" ]]; then
                    if get_favorited_courses; then
                        display_courses
                        return $?
                    else
                        error "No favorited courses found"
                    fi
                else
                    error "Invalid choice. Please try again."
                fi
                ;;
            r|R)
                get_courses || return 1
                display_courses
                return $?
                ;;
            q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid choice. Please enter a course number or use the available options."
                ;;
        esac
    done
}

# Multi-course selection menu
select_multiple_courses() {
    local courses_data
    if [[ ! -f "$COURSES_CACHE" ]] || ! courses_data=$(cat "$COURSES_CACHE"); then
        get_courses || return 1
        courses_data=$(cat "$COURSES_CACHE")
    fi
    
    local course_count
    course_count=$(echo "$courses_data" | jq length)
    
    # Check if these are favorited courses or all courses
    local has_favorites
    has_favorites=$(echo "$courses_data" | jq -r '.[0].is_favorite // false')
    
    if [[ "$has_favorites" == "true" ]]; then
        echo -e "\n${BOLD}${CYAN}Select Multiple Favorited Courses${NC}"
        echo "=================================="
        info "Select one or more starred/favorited courses"
    else
        echo -e "\n${BOLD}${CYAN}Select Multiple Courses${NC}"
        echo "======================="
        warning "Select one or more active courses"
    fi
    
    if [[ "$course_count" -eq 0 ]]; then
        warning "No active courses found"
        return 1
    fi
    
    echo -e "\nAvailable courses:"
    echo "$courses_data" | jq -r 'to_entries[] | "\(.key + 1). \(.value.name) (\(.value.course_code))"'
    
    local selected_indices=()
    local selected_display=()
    
    echo -e "\n${BOLD}Instructions:${NC}"
    echo "• Enter course numbers separated by spaces (e.g., 1 3 5)"
    echo "• Enter ranges with hyphens (e.g., 1-3 for courses 1, 2, 3)"
    echo "• Type 'all' to select all courses"
    echo "• Type 'done' when finished, or 'clear' to start over"
    
    while true; do
        echo -e "\n${BOLD}Currently selected courses:${NC}"
        if [[ ${#selected_indices[@]} -eq 0 ]]; then
            echo "None selected"
        else
            for display in "${selected_display[@]}"; do
                echo "  ✓ $display"
            done
        fi
        
        echo -e "\nOptions:"
        if [[ "$has_favorites" == "true" ]]; then
            echo "a) Show all active courses"
        else
            echo "f) Show favorited courses only"
        fi
        echo "r) Refresh course list"
        echo "clear) Clear selections"
        echo "done) Finish selection"
        echo "q) Quit"
        
        read -r -p "Enter selection: " selection
        
        case $selection in
            all|ALL)
                selected_indices=()
                selected_display=()
                for ((i=0; i<course_count; i++)); do
                    selected_indices+=($i)
                    local course_name course_code
                    course_name=$(echo "$courses_data" | jq -r ".[$i].name")
                    course_code=$(echo "$courses_data" | jq -r ".[$i].course_code")
                    selected_display+=("$course_name ($course_code)")
                done
                success "Selected all $course_count courses"
                ;;
            clear|CLEAR)
                selected_indices=()
                selected_display=()
                info "Cleared all selections"
                ;;
            done|DONE)
                if [[ ${#selected_indices[@]} -eq 0 ]]; then
                    error "No courses selected. Please select at least one course."
                    continue
                fi
                
                # Populate global arrays
                SELECTED_COURSE_IDS=()
                SELECTED_COURSE_NAMES=()
                for index in "${selected_indices[@]}"; do
                    local course_id course_name
                    course_id=$(echo "$courses_data" | jq -r ".[$index].id")
                    course_name=$(echo "$courses_data" | jq -r ".[$index].name")
                    SELECTED_COURSE_IDS+=("$course_id")
                    SELECTED_COURSE_NAMES+=("$course_name")
                done
                
                success "Selected ${#SELECTED_COURSE_IDS[@]} courses for assignment creation"
                return 0
                ;;
            a|A)
                if [[ "$has_favorites" == "true" ]]; then
                    get_all_courses || return 1
                    select_multiple_courses
                    return $?
                else
                    error "Invalid choice."
                fi
                ;;
            f|F)
                if [[ "$has_favorites" != "true" ]]; then
                    if get_favorited_courses; then
                        select_multiple_courses
                        return $?
                    else
                        error "No favorited courses found"
                    fi
                else
                    error "Invalid choice."
                fi
                ;;
            r|R)
                get_courses || return 1
                select_multiple_courses
                return $?
                ;;
            q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                # Parse number selections and ranges
                local new_selections=()
                local valid_selection=true
                
                # Split input by spaces and process each token
                IFS=' ' read -ra tokens <<< "$selection"
                for token in "${tokens[@]}"; do
                    if [[ "$token" =~ ^[0-9]+$ ]]; then
                        # Single number
                        local num=$((token - 1))
                        if [[ $num -ge 0 && $num -lt $course_count ]]; then
                            new_selections+=($num)
                        else
                            error "Course number $token is out of range (1-$course_count)"
                            valid_selection=false
                            break
                        fi
                    elif [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
                        # Range (e.g., 1-3)
                        local start_num end_num
                        start_num=$(echo "$token" | cut -d'-' -f1)
                        end_num=$(echo "$token" | cut -d'-' -f2)
                        start_num=$((start_num - 1))
                        end_num=$((end_num - 1))
                        
                        if [[ $start_num -ge 0 && $end_num -lt $course_count && $start_num -le $end_num ]]; then
                            for ((i=start_num; i<=end_num; i++)); do
                                new_selections+=($i)
                            done
                        else
                            error "Range $token is invalid or out of range"
                            valid_selection=false
                            break
                        fi
                    else
                        error "Invalid selection format: $token"
                        valid_selection=false
                        break
                    fi
                done
                
                if [[ "$valid_selection" == true && ${#new_selections[@]} -gt 0 ]]; then
                    # Add new selections (avoid duplicates)
                    for new_sel in "${new_selections[@]}"; do
                        local already_selected=false
                        for existing_sel in "${selected_indices[@]}"; do
                            if [[ $existing_sel -eq $new_sel ]]; then
                                already_selected=true
                                break
                            fi
                        done
                        
                        if [[ "$already_selected" == false ]]; then
                            selected_indices+=($new_sel)
                            local course_name course_code
                            course_name=$(echo "$courses_data" | jq -r ".[$new_sel].name")
                            course_code=$(echo "$courses_data" | jq -r ".[$new_sel].course_code")
                            selected_display+=("$course_name ($course_code)")
                        fi
                    done
                    success "Added ${#new_selections[@]} course(s) to selection"
                fi
                ;;
        esac
    done
}

# Get assignment groups for first selected course
get_assignment_groups() {
    local course_id
    if [[ ${#SELECTED_COURSE_IDS[@]} -gt 0 ]]; then
        course_id="${SELECTED_COURSE_IDS[0]}"
    else
        echo "[]"
        return 1
    fi
    
    local groups_data
    if groups_data=$(canvas_api GET "/courses/$course_id/assignment_groups"); then
        echo "$groups_data"
    else
        echo "[]"
    fi
}

# Validate date format
validate_date() {
    local date_str="$1"
    if [[ -z "$date_str" ]]; then
        return 0
    fi
    
    if date -d "$date_str" >/dev/null 2>&1 || date -j -f "%Y-%m-%d %H:%M" "$date_str" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Format date for Canvas API
format_date() {
    local date_str="$1"
    [[ -z "$date_str" ]] && return 0
    
    # Canvas API expects ISO 8601 format in UTC with Z suffix
    if command -v gdate >/dev/null 2>&1; then
        # GNU date (available via coreutils on macOS)
        gdate -d "$date_str" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
    else
        # Try BSD date (macOS default) or fall back to GNU date  
        if date -j -f "%Y-%m-%d %H:%M" "$date_str" "+%Y-%m-%dT%H:%M:00Z" 2>/dev/null; then
            return 0
        else
            # Fallback: try to parse with GNU date if available
            date -d "$date_str" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
        fi
    fi
}

# Convert HTTP to HTTPS and validate URL format
validate_and_enforce_https() {
    local url="$1"
    
    # First check if it's a valid URL format
    if [[ ! "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        return 1
    fi
    
    # Convert HTTP to HTTPS if needed
    if [[ "$url" =~ ^http://(.*)$ ]]; then
        url="https://${BASH_REMATCH[1]}"
        echo "🔒 Automatically upgraded HTTP to HTTPS: $url" >&2
    fi
    
    # Return the (potentially modified) URL
    echo "$url"
    return 0
}

# Validate URL format (legacy function for backward compatibility)
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Detect content type from URL
detect_content_type() {
    local url="$1"
    local url_lower=$(echo "$url" | tr '[:upper:]' '[:lower:]')
    
    # YouTube detection
    if [[ "$url_lower" =~ youtube\.com|youtu\.be ]]; then
        echo "youtube"
        return 0
    fi
    
    # Google Slides detection
    if [[ "$url_lower" =~ docs\.google\.com/presentation ]]; then
        echo "google_slides"
        return 0
    fi
    
    # File extension detection
    if [[ "$url_lower" =~ \.(pptx?|ppt)(\?|$) ]]; then
        echo "powerpoint"
    elif [[ "$url_lower" =~ \.(mov|mp4|avi|webm|mkv)(\?|$) ]]; then
        echo "video"
    elif [[ "$url_lower" =~ \.(pdf)(\?|$) ]]; then
        echo "pdf"
    elif [[ "$url_lower" =~ \.(jpe?g|png|gif|webp|svg)(\?|$) ]]; then
        echo "image"
    elif [[ "$url_lower" =~ \.(docx?|doc)(\?|$) ]]; then
        echo "word"
    elif [[ "$url_lower" =~ \.(xlsx?|xls)(\?|$) ]]; then
        echo "excel"
    else
        echo "generic"
    fi
}

# Convert YouTube URL to embed format
convert_youtube_url() {
    local url="$1"
    local video_id=""
    
    # Extract video ID from various YouTube URL formats
    if [[ "$url" =~ youtube\.com/watch.*[?\&]v=([^\&]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ youtu\.be/([^?]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    elif [[ "$url" =~ youtube\.com/embed/([^?]+) ]]; then
        video_id="${BASH_REMATCH[1]}"
    fi
    
    if [[ -n "$video_id" ]]; then
        echo "https://www.youtube.com/embed/$video_id"
    else
        echo "$url"  # Return original if can't parse
    fi
}

# Convert PowerPoint to Office Online embed
convert_powerpoint_url() {
    local url="$1"
    # Use Microsoft Office Online viewer for PowerPoint files
    echo "https://view.officeapps.live.com/op/embed.aspx?src=$(echo "$url" | sed 's/&/%26/g')"
}

# Generate optimized iframe based on content type
generate_smart_iframe() {
    local url="$1"
    local content_type="$2"
    local alt_text="$3"
    local size_option="$4"
    
    # DEBUG: Log function inputs
    echo "DEBUG: generate_smart_iframe called with:" >&2
    echo "  URL: $url" >&2
    echo "  Content Type: $content_type" >&2
    echo "  Alt Text: $alt_text" >&2
    echo "  Size Option: $size_option" >&2
    
    local embed_url="$url"
    local iframe_tag=""
    
    case "$content_type" in
        "youtube")
            embed_url=$(convert_youtube_url "$url")
            case $size_option in
                1) # Standard
                    iframe_tag="<iframe src=\"$embed_url\" style=\"width: 100%; height: 315px; border: 1px solid #ccc;\""
                    ;;
                2) # Responsive 16:9
                    local container_style="width: 100%; max-width: 800px;"
                    local wrapper_style="position: relative; width: 100%; overflow: hidden; padding-top: 56.25%;"
                    local iframe_style="position: absolute; top: 0; left: 0; right: 0; width: 100%; height: 100%; border: 1px solid #ccc;"
                    iframe_tag="<div style=\"$container_style\"><div style=\"$wrapper_style\"><iframe src=\"$embed_url\" style=\"$iframe_style\""
                    [[ -n "$alt_text" ]] && iframe_tag="$iframe_tag title=\"$alt_text\""
                    iframe_tag="$iframe_tag allowfullscreen></iframe></div></div>"
                    return 0
                    ;;
                3) # Custom size
                    read -r -p "Enter width (default: 100%): " custom_width
                    custom_width="${custom_width:-100%}"
                    read -r -p "Enter height in pixels (default: 315): " custom_height
                    custom_height="${custom_height:-315}"
                    [[ "$custom_height" =~ ^[0-9]+$ ]] && custom_height="${custom_height}px"
                    iframe_tag="<iframe src=\"$embed_url\" style=\"width: $custom_width; height: $custom_height; border: 1px solid #ccc;\""
                    ;;
            esac
            ;;
        "powerpoint")
            echo "DEBUG: Processing PowerPoint..." >&2
            embed_url=$(convert_powerpoint_url "$url")
            echo "DEBUG: Converted URL: $embed_url" >&2
            
            # Always use responsive for PowerPoint
            local container_style="width: 100%; max-width: 1000px;"
            local wrapper_style="position: relative; width: 100%; overflow: hidden; padding-top: 66.67%;" # 3:2 aspect ratio for presentations
            local iframe_style="position: absolute; top: 0; left: 0; right: 0; width: 100%; height: 100%; border: 1px solid #ccc;"
            iframe_tag="<div style=\"$container_style\"><div style=\"$wrapper_style\"><iframe src=\"$embed_url\" style=\"$iframe_style\""
            [[ -n "$alt_text" ]] && iframe_tag="$iframe_tag title=\"$alt_text\""
            iframe_tag="$iframe_tag allowfullscreen></iframe></div></div>"
            
            echo "DEBUG: Generated PowerPoint iframe (length: ${#iframe_tag})" >&2
            echo "DEBUG: iframe_tag: $iframe_tag" >&2
            echo "$iframe_tag"
            return 0
            ;;
        "google_slides")
            echo "DEBUG: Processing Google Slides..." >&2
            # Convert to embed format
            embed_url=$(echo "$url" | sed 's|/edit.*|/embed?start=false\&loop=false\&delayms=3000|')
            echo "DEBUG: Converted URL: $embed_url" >&2
            
            local container_style="width: 100%; max-width: 1000px;"
            local wrapper_style="position: relative; width: 100%; overflow: hidden; padding-top: 66.67%;"
            local iframe_style="position: absolute; top: 0; left: 0; right: 0; width: 100%; height: 100%; border: 1px solid #ccc;"
            iframe_tag="<div style=\"$container_style\"><div style=\"$wrapper_style\"><iframe src=\"$embed_url\" style=\"$iframe_style\""
            [[ -n "$alt_text" ]] && iframe_tag="$iframe_tag title=\"$alt_text\""
            iframe_tag="$iframe_tag allowfullscreen></iframe></div></div>"
            
            echo "DEBUG: Generated Google Slides iframe (length: ${#iframe_tag})" >&2
            echo "DEBUG: iframe_tag: $iframe_tag" >&2
            echo "$iframe_tag"
            return 0
            ;;
        "video")
            echo "DEBUG: Processing video file..." >&2
            case $size_option in
                1) 
                    iframe_tag="<video controls style=\"width: 100%; max-width: 800px; height: auto; border: 1px solid #ccc;\"><source src=\"$embed_url\" type=\"video/mp4\">Your browser does not support the video tag.</video>"
                    echo "DEBUG: Generated video tag (option 1, length: ${#iframe_tag})" >&2
                    echo "$iframe_tag"
                    return 0
                    ;;
                2) 
                    local container_style="width: 100%; max-width: 800px;"
                    local wrapper_style="position: relative; width: 100%; overflow: hidden; padding-top: 56.25%;"
                    local video_style="position: absolute; top: 0; left: 0; right: 0; width: 100%; height: 100%; border: 1px solid #ccc;"
                    iframe_tag="<div style=\"$container_style\"><div style=\"$wrapper_style\"><video controls style=\"$video_style\"><source src=\"$embed_url\" type=\"video/mp4\">Your browser does not support the video tag.</video></div></div>"
                    echo "DEBUG: Generated responsive video (option 2, length: ${#iframe_tag})" >&2
                    echo "$iframe_tag"
                    return 0
                    ;;
                3) 
                    read -r -p "Enter max width (default: 800px): " custom_width
                    custom_width="${custom_width:-800px}"
                    iframe_tag="<video controls style=\"width: 100%; max-width: $custom_width; height: auto; border: 1px solid #ccc;\"><source src=\"$embed_url\" type=\"video/mp4\">Your browser does not support the video tag.</video>"
                    echo "DEBUG: Generated custom video (option 3, length: ${#iframe_tag})" >&2
                    echo "$iframe_tag"
                    return 0
                    ;;
            esac
            ;;
        *)
            # Generic iframe handling
            case $size_option in
                1) iframe_tag="<iframe src=\"$embed_url\" style=\"width: 100%; height: 400px; border: 1px solid #ccc; overflow: hidden;\"" ;;
                2) 
                    local container_style="width: 100%; max-width: 800px;"
                    local wrapper_style="position: relative; width: 100%; overflow: hidden; padding-top: 56.25%;"
                    local iframe_style="position: absolute; top: 0; left: 0; right: 0; width: 100%; height: 100%; border: 1px solid #ccc;"
                    iframe_tag="<div style=\"$container_style\"><div style=\"$wrapper_style\"><iframe src=\"$embed_url\" style=\"$iframe_style\""
                    [[ -n "$alt_text" ]] && iframe_tag="$iframe_tag title=\"$alt_text\""
                    iframe_tag="$iframe_tag allowfullscreen></iframe></div></div>"
                    return 0
                    ;;
                3) 
                    read -r -p "Enter width (default: 100%): " custom_width
                    custom_width="${custom_width:-100%}"
                    read -r -p "Enter height in pixels (default: 400): " custom_height
                    custom_height="${custom_height:-400}"
                    [[ "$custom_height" =~ ^[0-9]+$ ]] && custom_height="${custom_height}px"
                    iframe_tag="<iframe src=\"$embed_url\" style=\"width: $custom_width; height: $custom_height; border: 1px solid #ccc; overflow: hidden;\""
                    ;;
            esac
            ;;
    esac
    
    # Add title and close tag for standard iframes
    [[ -n "$alt_text" ]] && iframe_tag="$iframe_tag title=\"$alt_text\""
    if [[ "$iframe_tag" == *"<iframe"* ]] && [[ "$iframe_tag" != *"</iframe>"* ]]; then
        iframe_tag="$iframe_tag></iframe>"
    fi
    
    echo "$iframe_tag"
}

# Validate Google Docs URL
validate_google_docs_url() {
    local url="$1"
    if [[ "$url" =~ ^https://docs\.google\.com/(document|spreadsheets|presentation)/d/[a-zA-Z0-9_-]+/?.*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Extract Google Docs ID from URL
extract_google_docs_id() {
    local url="$1"
    # Extract the document ID between /d/ and the next /
    if [[ "$url" =~ /d/([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        # Fallback: try to extract using sed
        echo "$url" | sed -n 's|.*/d/\([a-zA-Z0-9_-]\+\).*|\1|p'
    fi
}

# Create Google Docs template URLs
create_google_docs_template_url() {
    local doc_id="$1"
    local doc_type="$2"
    
    case $doc_type in
        document)
            echo "https://docs.google.com/document/d/$doc_id/copy"
            ;;
        spreadsheets)
            echo "https://docs.google.com/spreadsheets/d/$doc_id/copy"
            ;;
        presentation)
            echo "https://docs.google.com/presentation/d/$doc_id/copy"
            ;;
        *)
            echo "https://docs.google.com/document/d/$doc_id/copy"
            ;;
    esac
}

# Get Google Docs type from URL
get_google_docs_type() {
    local url="$1"
    if [[ "$url" =~ /document/ ]]; then
        echo "document"
    elif [[ "$url" =~ /spreadsheets/ ]]; then
        echo "spreadsheets"
    elif [[ "$url" =~ /presentation/ ]]; then
        echo "presentation"
    else
        echo "document"
    fi
}

# Upload file to Canvas
upload_file_to_canvas() {
    local file_path="$1"
    local filename="$2"
    local content_type="$3"
    
    if [[ ! -f "$file_path" ]]; then
        error "File not found: $file_path"
        return 1
    fi
    
    local file_size
    file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
    
    progress "Uploading file: $filename ($file_size bytes)"
    
    # Step 1: Request upload URL from Canvas
    local upload_request="{
        \"name\": \"$filename\",
        \"size\": $file_size,
        \"content_type\": \"$content_type\",
        \"parent_folder_path\": \"/uploaded_images\"
    }"
    
    local course_id
    if [[ ${#SELECTED_COURSE_IDS[@]} -gt 0 ]]; then
        course_id="${SELECTED_COURSE_IDS[0]}"
    else
        error "No course selected for file upload"
        return 1
    fi
    
    local upload_response
    if ! upload_response=$(canvas_api POST "/courses/$course_id/files" "$upload_request"); then
        error "Failed to initialize file upload"
        return 1
    fi
    
    # Step 2: Extract upload URL and parameters
    local upload_url upload_params file_param
    upload_url=$(echo "$upload_response" | jq -r '.upload_url')
    upload_params=$(echo "$upload_response" | jq -r '.upload_params')
    file_param=$(echo "$upload_params" | jq -r 'to_entries[] | "\(.key)=\(.value)"' | tr '\n' '&')
    
    # Step 3: Upload the actual file
    local upload_result
    upload_result=$(curl -s -w "%{http_code}" \
        -F "file=@$file_path" \
        -F "$file_param" \
        "$upload_url" -o /dev/null)
    
    if [[ "$upload_result" == "201" || "$upload_result" == "200" ]]; then
        local file_id
        file_id=$(echo "$upload_response" | jq -r '.id // empty')
        success "File uploaded successfully"
        echo "$file_id"
        return 0
    else
        error "File upload failed (HTTP $upload_result)"
        return 1
    fi
}

# Download image from URL to local directory
download_image() {
    local image_url="$1"
    local filename="$2"
    local local_path="$IMAGES_DIR/$filename"
    
    progress "Downloading image from URL..."
    
    if curl -s -L -o "$local_path" "$image_url"; then
        if [[ -f "$local_path" && -s "$local_path" ]]; then
            success "Image downloaded: $filename"
            echo "$local_path"
            return 0
        else
            error "Downloaded file is empty or invalid"
            rm -f "$local_path"
            return 1
        fi
    else
        error "Failed to download image from URL"
        return 1
    fi
}

# Get content type from file extension
get_content_type() {
    local filename="$1"
    local ext="${filename##*.}"
    ext="${ext,,}" # Convert to lowercase
    
    case "$ext" in
        jpg|jpeg) echo "image/jpeg" ;;
        png) echo "image/png" ;;
        gif) echo "image/gif" ;;
        webp) echo "image/webp" ;;
        svg) echo "image/svg+xml" ;;
        pdf) echo "application/pdf" ;;
        doc) echo "application/msword" ;;
        docx) echo "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ;;
        *) echo "application/octet-stream" ;;
    esac
}

# Collect images for assignment
collect_assignment_images() {
    local images_html=""
    
    echo -e "\n${BOLD}${CYAN}Assignment Content${NC}" >&2
    echo "==================" >&2
    echo "You can embed various types of content in your assignment description." >&2
    echo "" >&2
    echo -e "${BOLD}Supported content types:${NC}" >&2
    echo "• 📊 PowerPoint presentations (.pptx, .ppt)" >&2
    echo "• 📊 Google Slides presentations" >&2
    echo "• 🎥 YouTube videos & playlists" >&2
    echo "• 🎬 Video files (.mov, .mp4, .avi, .webm)" >&2
    echo "• 📄 PDF documents" >&2
    echo "• 🖼️  Images (.jpg, .png, .gif, .webp, .svg)" >&2
    echo "• 🌐 Any web content (embedded as iframe)" >&2
    echo "" >&2
    echo -e "${BOLD}Options:${NC}" >&2
    echo "1. External URLs (PowerPoint, Google Slides, YouTube, etc.)" >&2
    echo "2. Local image files (will be uploaded to Canvas)" >&2
    echo "" >&2
    
    read -r -p "Do you want to add content to this assignment? (y/N): " add_images
    if [[ "$add_images" != "y" && "$add_images" != "Y" ]]; then
        return 0
    fi
    
    local image_count=0
    while true; do
        echo "" >&2
        echo "Content Item $((image_count + 1)):" >&2
        echo "1. Add content URL (PowerPoint, YouTube, Google Slides, etc.)" >&2
        echo "2. Upload local image file" >&2
        echo "3. Done adding content" >&2
        echo "" >&2
        read -r -p "Choose option (1-3): " image_option
        
        case $image_option in
            1)
                read -r -p "Enter content URL (http/https - will be upgraded to HTTPS): " image_url
                if [[ -z "$image_url" ]]; then
                    echo -e "${YELLOW}⚠${NC} No URL entered, skipping..." >&2
                    continue
                else
                    # Validate and enforce HTTPS
                    local https_url
                    if https_url=$(validate_and_enforce_https "$image_url"); then
                        # Update the URL to the HTTPS version
                        image_url="$https_url"
                        
                        # Detect content type automatically
                        local content_type=$(detect_content_type "$image_url")
                    
                    echo "" >&2
                    case "$content_type" in
                        "youtube")
                            echo -e "${BLUE}🎥 Detected: YouTube Video${NC}" >&2
                            echo "Embedding options for YouTube:" >&2
                            echo "1. Standard player (315px height)" >&2
                            echo "2. Responsive player (16:9 aspect ratio)" >&2
                            echo "3. Custom size" >&2
                            ;;
                        "powerpoint")
                            echo -e "${BLUE}📊 Detected: PowerPoint Presentation${NC}" >&2
                            echo "Will embed using Microsoft Office Online viewer (responsive)" >&2
                            ;;
                        "google_slides")
                            echo -e "${BLUE}📊 Detected: Google Slides Presentation${NC}" >&2
                            echo "Will embed as interactive slideshow (responsive)" >&2
                            ;;
                        "video")
                            echo -e "${BLUE}🎬 Detected: Video File${NC}" >&2
                            echo "Embedding options for video:" >&2
                            echo "1. Standard player" >&2
                            echo "2. Responsive player (16:9)" >&2
                            echo "3. Custom size" >&2
                            ;;
                        "pdf")
                            echo -e "${BLUE}📄 Detected: PDF Document${NC}" >&2
                            echo "Will embed as iframe viewer" >&2
                            ;;
                        "image")
                            echo -e "${BLUE}🖼️  Detected: Image File${NC}" >&2
                            echo "Embedding as responsive image" >&2
                            ;;
                        *)
                            echo -e "${BLUE}🌐 Detected: Web Content${NC}" >&2
                            echo "Embedding options:" >&2
                            echo "1. Standard iframe (400px height)" >&2
                            echo "2. Responsive iframe (16:9)" >&2
                            echo "3. Custom size" >&2
                            ;;
                    esac
                    
                    local size_option="1"
                    if [[ "$content_type" != "powerpoint" && "$content_type" != "google_slides" && "$content_type" != "image" && "$content_type" != "pdf" ]]; then
                        read -r -p "Select option (1-3, default: 1): " size_option
                        size_option="${size_option:-1}"
                    fi
                    
                    read -r -p "Enter alt text/title (optional): " alt_text
                    
                    # Generate optimized iframe using our smart function
                    echo "DEBUG: About to call generate_smart_iframe..." >&2
                    local img_tag=$(generate_smart_iframe "$image_url" "$content_type" "$alt_text" "$size_option")
                    echo "DEBUG: generate_smart_iframe returned (length: ${#img_tag}): '$img_tag'" >&2
                    
                    if [[ -n "$img_tag" ]]; then
                        images_html="$images_html<p>$img_tag</p>"
                        
                        case "$content_type" in
                            "youtube") echo -e "${GREEN}✓${NC} YouTube video embedded" >&2 ;;
                            "powerpoint") echo -e "${GREEN}✓${NC} PowerPoint presentation embedded (Office Online viewer)" >&2 ;;
                            "google_slides") echo -e "${GREEN}✓${NC} Google Slides presentation embedded" >&2 ;;
                            "video") echo -e "${GREEN}✓${NC} Video file embedded" >&2 ;;
                            "pdf") echo -e "${GREEN}✓${NC} PDF document embedded" >&2 ;;
                            "image") echo -e "${GREEN}✓${NC} Image embedded (responsive)" >&2 ;;
                            *) echo -e "${GREEN}✓${NC} Content embedded as iframe" >&2 ;;
                        esac
                        
                        ((image_count++))
                        else
                            echo -e "${RED}✗${NC} Failed to generate embedding code" >&2
                        fi
                    else
                        echo -e "${RED}✗${NC} Invalid URL format: $image_url" >&2
                        echo -e "${RED}✗${NC} Please use a valid https:// or http:// URL" >&2
                    fi
                fi
                ;;
            2)
                read -r -p "Enter path to local image file: " file_path
                
                if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
                    local filename
                    filename=$(basename "$file_path")
                    local content_type
                    content_type=$(get_content_type "$filename")
                    
                    # Copy file to our managed directory
                    local managed_path="$FILES_DIR/$filename"
                    cp "$file_path" "$managed_path"
                    
                    if [[ "$DRY_RUN" == true ]]; then
                        warning "DRY RUN: Would upload file $filename to Canvas"
                        images_html="$images_html<p><img src=\"/courses/$SELECTED_COURSE_ID/files/[FILE_ID]/preview\" alt=\"$filename\" style=\"max-width: 100%; height: auto;\" /></p>"
                        ((image_count++))
                    else
                        local file_id
                        if file_id=$(upload_file_to_canvas "$managed_path" "$filename" "$content_type"); then
                            read -r -p "Enter alt text (optional): " alt_text
                            [[ -z "$alt_text" ]] && alt_text="$filename"
                            
                            local img_tag="<p><img src=\"/courses/$SELECTED_COURSE_ID/files/$file_id/preview\" alt=\"$alt_text\" style=\"max-width: 100%; height: auto;\" /></p>"
                            images_html="$images_html$img_tag"
                            success "File uploaded and added to assignment"
                            ((image_count++))
                        else
                            error "Failed to upload file"
                        fi
                    fi
                else
                    error "File not found: $file_path"
                fi
                ;;
            3)
                break
                ;;
            "")
                echo -e "${YELLOW}⚠${NC} Please choose an option (1-3) or press Ctrl+C to cancel" >&2
                ;;
            *)
                echo -e "${RED}✗${NC} Invalid option '$image_option'. Please choose 1, 2, or 3." >&2
                ;;
        esac
        
        if [[ $image_count -ge 5 ]]; then
            warning "Maximum of 5 images recommended for performance"
            read -r -p "Continue adding more images? (y/N): " continue_images
            [[ "$continue_images" != "y" && "$continue_images" != "Y" ]] && break
        fi
    done
    
    if [[ $image_count -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Added $image_count image(s) to assignment" >&2
        echo "$images_html"
    else
        echo ""
    fi
}

# Collect Google Docs templates for assignment
collect_google_docs_templates() {
    local docs_html=""
    
    echo -e "\n${BOLD}${CYAN}Google Docs Templates${NC}" >&2
    echo "====================" >&2
    echo "Add Google Docs templates that students can copy and use." >&2
    echo "Students will be able to make their own copy by clicking the links." >&2
    echo "" >&2
    
    read -r -p "Do you want to add Google Docs templates to this assignment? (y/N): " add_docs
    if [[ "$add_docs" != "y" && "$add_docs" != "Y" ]]; then
        echo ""
        return 0
    fi
    
    local docs_count=0
    while true; do
        echo "" >&2
        echo "Google Docs Template $((docs_count + 1)):" >&2
        echo "1. Add Google Docs template" >&2
        echo "2. Done adding templates" >&2
        echo "" >&2
        read -r -p "Choose option (1-2): " docs_option
        
        case $docs_option in
            1)
                read -r -p "Enter Google Docs URL (https://docs.google.com/...): " docs_url
                if [[ -z "$docs_url" ]]; then
                    echo -e "${YELLOW}⚠${NC} No URL entered, skipping..." >&2
                    continue
                else
                    # Validate and enforce HTTPS for Google Docs URLs
                    local https_docs_url
                    if https_docs_url=$(validate_and_enforce_https "$docs_url") && validate_google_docs_url "$https_docs_url"; then
                        docs_url="$https_docs_url"
                    local doc_id doc_type template_url
                    doc_id=$(extract_google_docs_id "$docs_url")
                    doc_type=$(get_google_docs_type "$docs_url")
                    template_url=$(create_google_docs_template_url "$doc_id" "$doc_type")
                    
                    # DEBUG: Log the extraction process
                    log "DEBUG: Google Docs URL processing:"
                    log "  Input URL: $docs_url"
                    log "  Extracted ID: '$doc_id'"
                    log "  Document Type: '$doc_type'"
                    log "  Template URL: '$template_url'"
                    
                    read -r -p "Enter template name (e.g., 'Assignment Template'): " template_name
                    [[ -z "$template_name" ]] && template_name="Google Docs Template"
                    
                    read -r -p "Enter description (optional): " template_desc
                    
                    local doc_type_name
                    case $doc_type in
                        document) doc_type_name="Document" ;;
                        spreadsheets) doc_type_name="Spreadsheet" ;;
                        presentation) doc_type_name="Presentation" ;;
                        *) doc_type_name="Document" ;;
                    esac
                    
                    local template_html="<div style='border: 1px solid #ccc; padding: 15px; margin: 10px 0; border-radius: 5px;'>"
                    template_html="$template_html<h4>📄 $template_name</h4>"
                    [[ -n "$template_desc" ]] && template_html="$template_html<p>$template_desc</p>"
                    template_html="$template_html<p><strong>Google $doc_type_name Template</strong></p>"
                    template_html="$template_html<p><a href=\"$template_url\" target=\"_blank\" style=\"background-color: #4285f4; color: white; padding: 8px 16px; text-decoration: none; border-radius: 4px; display: inline-block;\">📋 Make a Copy</a></p>"
                    template_html="$template_html<p><em>Click the link above to create your own copy of this template</em></p>"
                    template_html="$template_html</div>"
                    
                        docs_html="$docs_html$template_html"
                        echo -e "${GREEN}✓${NC} Google Docs template added: $template_name" >&2
                        ((docs_count++))
                    else
                        echo -e "${RED}✗${NC} Invalid Google Docs URL: $docs_url" >&2
                        echo "Please use a valid Google Docs URL like:" >&2
                        echo "https://docs.google.com/document/d/1ABCdef123.../edit" >&2
                    fi
                fi
                ;;
            2)
                break
                ;;
            "")
                echo -e "${YELLOW}⚠${NC} Please choose an option (1-2) or press Ctrl+C to cancel" >&2
                ;;
            *)
                echo -e "${RED}✗${NC} Invalid option '$docs_option'. Please choose 1 or 2." >&2
                ;;
        esac
        
        if [[ $docs_count -ge 3 ]]; then
            warning "Maximum of 3 templates recommended for clarity"
            read -r -p "Continue adding more templates? (y/N): " continue_templates
            [[ "$continue_templates" != "y" && "$continue_templates" != "Y" ]] && break
        fi
    done
    
    if [[ $docs_count -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Added $docs_count Google Docs template(s) to assignment" >&2
        echo "$docs_html"
    else
        echo ""
    fi
}

# Collect assignment details
collect_assignment_details() {
    local assignment_name description points_possible due_at unlock_at lock_at
    local assignment_group_id submission_types grading_type published
    
    echo -e "\n${BOLD}${CYAN}Assignment Details${NC}" >&2
    echo "==================" >&2
    
    # Assignment name
    while [[ -z "$assignment_name" ]]; do
        read -r -p "Assignment name: " assignment_name
        [[ -z "$assignment_name" ]] && error "Assignment name is required"
    done
    
    # Description
    echo "" >&2
    read -r -p "Enter assignment description (optional): " description
    
    # Collect images and add to description
    local images_html
    images_html=$(collect_assignment_images)
    if [[ -n "$images_html" ]]; then
        description="$description$images_html"
    fi
    
    # Collect Google Docs templates and add to description
    local docs_html
    docs_html=$(collect_google_docs_templates)
    if [[ -n "$docs_html" ]]; then
        description="$description$docs_html"
    fi
    
    # Points possible
    while true; do
        read -r -p "Points possible (default: 10): " points_input
        points_possible="${points_input:-10}"
        if [[ "$points_possible" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            error "Please enter a valid number"
        fi
    done
    
    # Assignment group
    local groups_data
    groups_data=$(get_assignment_groups)
    local groups_count
    groups_count=$(echo "$groups_data" | jq length)
    
    assignment_group_id=""
    if [[ "$groups_count" -gt 0 ]]; then
        echo -e "\nAssignment Groups:" >&2
        echo "$groups_data" | jq -r 'to_entries[] | "\(.key + 1). \(.value.name)"' >&2
        echo "0. No assignment group" >&2
        
        while true; do
            read -r -p "Select assignment group (0-$groups_count): " group_choice
            if [[ "$group_choice" =~ ^[0-9]+$ ]] && [[ "$group_choice" -le "$groups_count" ]]; then
                if [[ "$group_choice" -gt 0 ]]; then
                    local group_index=$((group_choice - 1))
                    assignment_group_id=$(echo "$groups_data" | jq -r ".[$group_index].id")
                fi
                break
            else
                echo -e "${RED}✗${NC} Please enter a valid number between 0 and $groups_count" >&2
            fi
        done
    fi
    
    # Submission types
    echo -e "\nSubmission Types:" >&2
    echo "1. Online text entry" >&2
    echo "2. Online upload" >&2
    echo "3. Both text entry and upload" >&2
    echo "4. External tool" >&2
    echo "5. No submission" >&2
    
    while true; do
        read -r -p "Select submission type (1-5): " sub_choice
        case $sub_choice in
            1) submission_types="online_text_entry" ;;
            2) submission_types="online_upload" ;;
            3) submission_types="online_text_entry,online_upload" ;;
            4) submission_types="external_tool" ;;
            5) submission_types="none" ;;
            *) echo -e "${RED}✗${NC} Please enter a number between 1 and 5" >&2; continue ;;
        esac
        break
    done
    
    # Grading type
    echo -e "\nGrading Type:" >&2
    echo "1. Points" >&2
    echo "2. Percentage" >&2
    echo "3. Letter grade" >&2
    echo "4. Pass/Fail" >&2
    
    while true; do
        read -r -p "Select grading type (1-4, default: 1): " grade_choice
        grade_choice="${grade_choice:-1}"
        case $grade_choice in
            1) grading_type="points" ;;
            2) grading_type="percent" ;;
            3) grading_type="letter_grade" ;;
            4) grading_type="pass_fail" ;;
            *) echo -e "${RED}✗${NC} Please enter a number between 1 and 4" >&2; continue ;;
        esac
        break
    done
    
    # Dates
    echo -e "\nDates (leave blank to skip, format: YYYY-MM-DD HH:MM):" >&2
    
    while true; do
        read -r -p "Due date: " due_input
        if [[ -z "$due_input" ]] || validate_date "$due_input"; then
            due_at=$(format_date "$due_input")
            break
        else
            echo -e "${RED}✗${NC} Invalid date format. Use YYYY-MM-DD HH:MM" >&2
        fi
    done
    
    while true; do
        read -r -p "Available from date: " unlock_input
        if [[ -z "$unlock_input" ]] || validate_date "$unlock_input"; then
            unlock_at=$(format_date "$unlock_input")
            break
        else
            echo -e "${RED}✗${NC} Invalid date format. Use YYYY-MM-DD HH:MM" >&2
        fi
    done
    
    while true; do
        read -r -p "Available until date: " lock_input
        if [[ -z "$lock_input" ]] || validate_date "$lock_input"; then
            lock_at=$(format_date "$lock_input")
            break
        else
            echo -e "${RED}✗${NC} Invalid date format. Use YYYY-MM-DD HH:MM" >&2
        fi
    done
    
    # Published status
    read -r -p "Publish assignment immediately? (Y/n): " pub_choice
    published="true"
    [[ "$pub_choice" == "n" || "$pub_choice" == "N" ]] && published="false"
    
    
    # Build JSON payload
    local assignment_data="{
        \"assignment\": {
            \"name\": \"$assignment_name\",
            \"description\": $(echo -n "$description" | jq -R .),
            \"points_possible\": $points_possible,
            \"grading_type\": \"$grading_type\",
            \"submission_types\": [\"$(echo "$submission_types" | sed 's/,/","/g')\"],
            \"published\": $published"
    
    [[ -n "$assignment_group_id" ]] && assignment_data="${assignment_data},
        \"assignment_group_id\": $assignment_group_id"
    [[ -n "$due_at" ]] && assignment_data="${assignment_data},
        \"due_at\": \"$due_at\""
    [[ -n "$unlock_at" ]] && assignment_data="${assignment_data},
        \"unlock_at\": \"$unlock_at\""
    [[ -n "$lock_at" ]] && assignment_data="${assignment_data},
        \"lock_at\": \"$lock_at\""
    
    assignment_data="$assignment_data
        }
    }"
    
    
    echo "$assignment_data"
}

# Create assignment
create_assignment() {
    local assignment_data="$1"
    
    echo -e "\n${BOLD}Assignment Summary:${NC}"
    echo "==================="
    
    # DEBUG: Log the raw JSON before parsing
    echo -e "\n${YELLOW}DEBUG: Raw assignment_data (first 500 chars):${NC}" >&2
    echo "${assignment_data:0:500}..." >&2
    echo -e "\n${YELLOW}DEBUG: assignment_data length: ${#assignment_data}${NC}" >&2
    
    # DEBUG: Test JSON validity
    if echo "$assignment_data" | jq . > /dev/null 2>&1; then
        echo -e "${GREEN}DEBUG: JSON is valid${NC}" >&2
    else
        echo -e "${RED}DEBUG: JSON is INVALID - here's the jq error:${NC}" >&2
        echo "$assignment_data" | jq . >&2
        echo -e "\n${RED}DEBUG: Full raw JSON:${NC}" >&2
        echo "$assignment_data" >&2
        return 1
    fi
    
    echo "$assignment_data" | jq -r '.assignment | "Name: \(.name)\nPoints: \(.points_possible)\nGrading: \(.grading_type)\nPublished: \(.published)"'
    
    if [[ "$DRY_RUN" == true ]]; then
        warning "DRY RUN: Assignment would be created with the above settings"
        return 0
    fi
    
    read -r -p "Create this assignment? (Y/n): " confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        info "Assignment creation cancelled"
        return 1
    fi
    
    local course_id="${SELECTED_COURSE_IDS[0]}"
    local course_name="${SELECTED_COURSE_NAMES[0]}"
    
    progress "Creating assignment in $course_name..."
    
    local response
    if response=$(canvas_api POST "/courses/$course_id/assignments" "$assignment_data"); then
        local assignment_id assignment_name assignment_url
        assignment_id=$(echo "$response" | jq -r '.id')
        assignment_name=$(echo "$response" | jq -r '.name')
        assignment_url="$CANVAS_URL/courses/$course_id/assignments/$assignment_id"
        
        success "Assignment '$assignment_name' created successfully!"
        info "Assignment URL: $assignment_url"
        
        # Success confirmation and next actions
        echo -e "\n${BOLD}${CYAN}🎉 Assignment Creation Complete!${NC}"
        echo "====================================="
        echo -e "${GREEN}✓${NC} Your assignment has been successfully created in Canvas"
        echo -e "${BLUE}→${NC} You can view it at: $assignment_url"
        echo ""
        echo "What would you like to do next?"
        echo "1. Create another assignment"
        echo "2. Return to main menu" 
        echo "3. Exit"
        echo ""
        read -r -p "Choose option (1-3, default: 2): " next_action
        next_action="${next_action:-2}"
        
        case $next_action in
            1)
                echo -e "${BLUE}Starting new assignment creation...${NC}"
                return 0  # This will continue the assignment creation flow
                ;;
            2)
                echo -e "${BLUE}Returning to main menu...${NC}"
                return 0
                ;;
            3)
                echo "Thank you for using Canvas Assignment Creator! 👋"
                exit 0
                ;;
            *)
                echo -e "${BLUE}Returning to main menu...${NC}"
                return 0
                ;;
        esac
    else
        error "Failed to create assignment"
        return 1
    fi
}

# Create assignment in multiple courses
create_assignments_multi_course() {
    local assignment_data="$1"
    
    if [[ ${#SELECTED_COURSE_IDS[@]} -eq 0 ]]; then
        error "No courses selected"
        return 1
    fi
    
    echo -e "\n${BOLD}Multi-Course Assignment Summary:${NC}"
    echo "================================"
    echo "$assignment_data" | jq -r '.assignment | "Name: \(.name)\nPoints: \(.points_possible)\nGrading: \(.grading_type)\nPublished: \(.published)"'
    
    echo -e "\n${BOLD}Target Courses (${#SELECTED_COURSE_IDS[@]}):${NC}"
    for i in "${!SELECTED_COURSE_NAMES[@]}"; do
        echo "  $((i+1)). ${SELECTED_COURSE_NAMES[$i]}"
    done
    
    if [[ "$DRY_RUN" == true ]]; then
        warning "DRY RUN: Assignment would be created in ${#SELECTED_COURSE_IDS[@]} courses"
        return 0
    fi
    
    read -r -p "Create this assignment in all ${#SELECTED_COURSE_IDS[@]} selected courses? (Y/n): " confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        info "Assignment creation cancelled"
        return 1
    fi
    
    local success_count=0
    local failed_courses=()
    local created_assignments=()
    
    echo -e "\n${BOLD}Creating assignments:${NC}"
    
    for i in "${!SELECTED_COURSE_IDS[@]}"; do
        local course_id="${SELECTED_COURSE_IDS[$i]}"
        local course_name="${SELECTED_COURSE_NAMES[$i]}"
        
        progress "[$((i+1))/${#SELECTED_COURSE_IDS[@]}] Creating in: $course_name"
        
        local response
        if response=$(canvas_api POST "/courses/$course_id/assignments" "$assignment_data"); then
            local assignment_id assignment_name assignment_url
            assignment_id=$(echo "$response" | jq -r '.id')
            assignment_name=$(echo "$response" | jq -r '.name')
            assignment_url="$CANVAS_URL/courses/$course_id/assignments/$assignment_id"
            
            success "✓ Created in: $course_name"
            created_assignments+=("$course_name: $assignment_url")
            ((success_count++))
        else
            error "✗ Failed in: $course_name"
            failed_courses+=("$course_name")
        fi
        
        # Small delay to avoid overwhelming the API
        sleep 0.5
    done
    
    # Final summary
    echo -e "\n${BOLD}${CYAN}Assignment Creation Summary:${NC}"
    echo "============================"
    success "Successfully created: $success_count/${#SELECTED_COURSE_IDS[@]} assignments"
    
    if [[ ${#created_assignments[@]} -gt 0 ]]; then
        echo -e "\n${BOLD}Created assignments:${NC}"
        for assignment in "${created_assignments[@]}"; do
            echo "  ✓ $assignment"
        done
    fi
    
    if [[ ${#failed_courses[@]} -gt 0 ]]; then
        echo -e "\n${BOLD}Failed courses:${NC}"
        for course in "${failed_courses[@]}"; do
            echo "  ✗ $course"
        done
        warning "Some assignments failed to create. Check permissions and course settings."
    fi
    
    # Multi-course success confirmation and next actions
    echo -e "\n${BOLD}${CYAN}🎉 Multi-Course Assignment Creation Complete!${NC}"
    echo "================================================"
    if [[ $success_count -eq ${#SELECTED_COURSE_IDS[@]} ]]; then
        echo -e "${GREEN}✓${NC} All assignments created successfully across $success_count courses!"
    else
        echo -e "${YELLOW}⚠${NC} Created $success_count out of ${#SELECTED_COURSE_IDS[@]} assignments"
    fi
    echo ""
    echo "What would you like to do next?"
    echo "1. Create another assignment"
    echo "2. Return to main menu"
    echo "3. Exit"
    echo ""
    read -r -p "Choose option (1-3, default: 2): " next_action
    next_action="${next_action:-2}"
    
    case $next_action in
        1)
            echo -e "${BLUE}Starting new assignment creation...${NC}"
            ;;
        2)
            echo -e "${BLUE}Returning to main menu...${NC}"
            ;;
        3)
            echo "Thank you for using Canvas Assignment Creator! 👋"
            exit 0
            ;;
        *)
            echo -e "${BLUE}Returning to main menu...${NC}"
            ;;
    esac
    
    if [[ ${#failed_courses[@]} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# Show help
show_help() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$VERSION${NC}

A comprehensive tool for creating assignments in Canvas LMS via API.

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -d, --dry-run       Preview actions without making changes
    --setup             Force configuration setup
    --reset-config      Clear saved configuration

${BOLD}FEATURES:${NC}
    • Interactive assignment creation
    • Single and multi-course deployment
    • Favorited course prioritization
    • Assignment group integration
    • Date validation and formatting
    • Multiple submission types
    • Configurable grading types
    • Draft and published states
    • Image embedding (URLs and file uploads)
    • File upload and management
    • Google Docs template integration
    • Comprehensive error handling
    • Configuration persistence

${BOLD}EXAMPLES:${NC}
    $0                  # Interactive assignment creation
    $0 --dry-run        # Preview without creating
    $0 --verbose        # Enable detailed logging
    $0 --setup          # Reconfigure Canvas settings

${BOLD}CONFIGURATION:${NC}
    Config file: $CONFIG_FILE
    Cache dir:   $CONFIG_DIR
    Images dir:  $IMAGES_DIR
    Files dir:   $FILES_DIR
    Log file:    $LOG_FILE

${BOLD}CANVAS API TOKEN:${NC}
    Generate your API token in Canvas:
    Account → Settings → Approved Integrations → New Access Token

${BOLD}DATE FORMAT:${NC}
    Use YYYY-MM-DD HH:MM format for dates (24-hour time)
    Examples: 2024-03-15 23:59, 2024-04-01 09:00

${BOLD}IMAGE HANDLING:${NC}
    Two methods for adding images to assignments:
    1. External URLs (recommended): Direct links to hosted images
    2. Local files: Automatically uploaded to Canvas and embedded
    
    Supported formats: JPG, PNG, GIF, WebP, SVG
    Images are automatically sized with max-width: 100%

${BOLD}GOOGLE DOCS TEMPLATES:${NC}
    Add Google Docs templates that students can copy:
    • Supports Documents, Sheets, and Presentations
    • Automatically creates "Make a Copy" links
    • Templates open in new windows/tabs
    • Professional styling with clear instructions
    
    Example URL: https://docs.google.com/document/d/1ABC123.../edit

${BOLD}COURSE SELECTION:${NC}
    The script prioritizes favorited/starred courses:
    • Shows favorited courses first (if any are set)
    • Falls back to all active courses if no favorites
    • Switch between favorited and all courses in the menu
    • To set favorites, star courses in Canvas web interface

${BOLD}MULTI-COURSE DEPLOYMENT:${NC}
    Create identical assignments across multiple courses:
    • Select multiple courses: 1 3 5 (specific courses)
    • Select ranges: 1-3 (courses 1, 2, 3)
    • Select all: type 'all' to select all courses
    • Progress tracking: Real-time deployment status
    • Error handling: Individual course failure reporting

EOF
}

# File management menu
manage_files() {
    while true; do
        echo -e "\n${BOLD}${CYAN}File Management${NC}"
        echo "==============="
        echo "Local directories:"
        echo "  Images: $IMAGES_DIR"
        echo "  Files:  $FILES_DIR"
        echo ""
        echo "1. List local files"
        echo "2. Clear local files"
        echo "3. View disk usage"
        echo "4. Upload file to Canvas"
        echo "b. Back to main menu"
        
        read -r -p "Choose option: " choice
        
        case $choice in
            1)
                echo -e "\n${BOLD}Local Files:${NC}"
                if [[ -d "$IMAGES_DIR" ]] && [[ -n "$(ls -A "$IMAGES_DIR" 2>/dev/null)" ]]; then
                    echo -e "\n${CYAN}Images:${NC}"
                    ls -la "$IMAGES_DIR"
                fi
                if [[ -d "$FILES_DIR" ]] && [[ -n "$(ls -A "$FILES_DIR" 2>/dev/null)" ]]; then
                    echo -e "\n${CYAN}Files:${NC}"
                    ls -la "$FILES_DIR"
                fi
                if [[ -z "$(ls -A "$IMAGES_DIR" "$FILES_DIR" 2>/dev/null)" ]]; then
                    info "No local files found"
                fi
                ;;
            2)
                read -r -p "Clear all local files? This cannot be undone (y/N): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    rm -rf "$IMAGES_DIR"/* "$FILES_DIR"/* 2>/dev/null
                    success "Local files cleared"
                else
                    info "Operation cancelled"
                fi
                ;;
            3)
                echo -e "\n${BOLD}Disk Usage:${NC}"
                if command -v du >/dev/null 2>&1; then
                    echo "Configuration directory:"
                    du -sh "$CONFIG_DIR" 2>/dev/null || echo "Unable to calculate size"
                    echo -e "\nBreakdown:"
                    du -sh "$IMAGES_DIR" 2>/dev/null | sed 's/^/  Images: /' || echo "  Images: 0B"
                    du -sh "$FILES_DIR" 2>/dev/null | sed 's/^/  Files:  /' || echo "  Files: 0B"
                else
                    warning "du command not available"
                fi
                ;;
            4)
                if [[ ${#SELECTED_COURSE_IDS[@]} -eq 0 ]]; then
                    error "Please select a course first"
                    continue
                fi
                
                read -r -p "Enter path to file to upload: " file_path
                if [[ -f "$file_path" ]]; then
                    local filename
                    filename=$(basename "$file_path")
                    local content_type
                    content_type=$(get_content_type "$filename")
                    
                    local managed_path="$FILES_DIR/$filename"
                    cp "$file_path" "$managed_path"
                    
                    if file_id=$(upload_file_to_canvas "$managed_path" "$filename" "$content_type"); then
                        success "File uploaded successfully"
                        info "File ID: $file_id"
                        info "Canvas URL: $CANVAS_URL/courses/${SELECTED_COURSE_IDS[0]}/files/$file_id"
                    else
                        error "Failed to upload file"
                    fi
                else
                    error "File not found: $file_path"
                fi
                ;;
            b|B)
                return 0
                ;;
            *)
                error "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "\n${BOLD}${CYAN}$SCRIPT_NAME${NC}"
        echo "=========================="
        
        local course_count=${#SELECTED_COURSE_IDS[@]:-0}
        
        if [[ $course_count -eq 0 ]]; then
            # No courses selected - show course selection menu only
            warning "No course selected. Please select a course first."
            
            echo -e "\n${BOLD}SELECT COURSE(S)${NC}"
            echo "1. Select a single course"
            echo "2. Select multiple courses"
            echo "3. Refresh course list from Canvas"
            
            echo -e "\n${BOLD}SETTINGS${NC}"
            echo "4. Reconfigure Canvas settings"
            echo "q. Quit"
            
        else
            # Courses selected - show full menu
            if [[ $course_count -eq 1 ]]; then
                success "Selected course: ${SELECTED_COURSE_NAMES[0]}"
            else
                success "Selected $course_count courses:"
                for i in "${!SELECTED_COURSE_NAMES[@]}"; do
                    echo "  $((i+1)). ${SELECTED_COURSE_NAMES[$i]}"
                done
            fi
            
            echo -e "\n${BOLD}ACTIONS${NC}"
            echo "1. Create a new assignment"
            
            echo -e "\n${BOLD}COURSE MANAGEMENT${NC}"
            echo "2. Change selected course(s)"
            echo "3. Select additional courses"
            echo "4. Clear course selection"
            echo "5. Refresh course list from Canvas"
            
            echo -e "\n${BOLD}UTILITIES${NC}"
            echo "6. Manage local files"
            echo "7. Reconfigure Canvas settings"
            echo "q. Quit"
        fi
        
        read -r -p "Choose option: " choice
        
        local course_count=${#SELECTED_COURSE_IDS[@]:-0}
        case $choice in
            1)
                if [[ $course_count -eq 0 ]]; then
                    # No courses selected - Option 1: Select a single course
                    if display_courses; then
                        # Ensure single selection state
                        SELECTED_COURSE_IDS=("${SELECTED_COURSE_ID}")
                        SELECTED_COURSE_NAMES=("${SELECTED_COURSE_NAME}")
                    fi
                else
                    # Courses selected - Option 1: Create a new assignment
                    local assignment_data
                    if ! assignment_data=$(collect_assignment_details); then
                        info "Assignment creation cancelled."
                        continue
                    fi
                    
                    if [[ $course_count -eq 1 ]]; then
                        create_assignment "$assignment_data"
                    else
                        create_assignments_multi_course "$assignment_data"
                    fi
                fi
                ;;
            2)
                if [[ $course_count -eq 0 ]]; then
                    # No courses selected - Option 2: Select multiple courses
                    select_multiple_courses || continue
                else
                    # Courses selected - Option 2: Change selected course(s)
                    if display_courses; then
                        # Ensure single selection state
                        SELECTED_COURSE_IDS=("${SELECTED_COURSE_ID}")
                        SELECTED_COURSE_NAMES=("${SELECTED_COURSE_NAME}")
                    fi
                fi
                ;;
            3)
                if [[ $course_count -eq 0 ]]; then
                    # No courses selected - Option 3: Refresh course list
                    get_courses
                    info "Course list has been refreshed."
                else
                    # Courses selected - Option 3: Select additional courses
                    select_multiple_courses || continue
                fi
                ;;
            4)
                if [[ $course_count -eq 0 ]]; then
                    # No courses selected - Option 4: Reconfigure Canvas settings
                    setup_canvas
                else
                    # Courses selected - Option 4: Clear course selection
                    SELECTED_COURSE_IDS=()
                    SELECTED_COURSE_NAMES=()
                    success "Course selection cleared."
                fi
                ;;
            5)
                # Courses selected only - Option 5: Refresh course list
                if [[ $course_count -gt 0 ]]; then
                    get_courses
                    info "Course list has been refreshed."
                else
                    error "Invalid option. Please choose a valid option."
                fi
                ;;
            6)
                # Courses selected only - Option 6: Manage files
                if [[ $course_count -gt 0 ]]; then
                    manage_files
                else
                    error "Invalid option. Please choose a valid option."
                fi
                ;;
            7)
                # Courses selected only - Option 7: Reconfigure settings
                if [[ $course_count -gt 0 ]]; then
                    setup_canvas
                else
                    error "Invalid option. Please choose a valid option."
                fi
                ;;
            q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                error "Invalid choice. Please try again."
                ;;
        esac
    done
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --setup)
                setup_canvas
                exit $?
                ;;
            --reset-config)
                rm -f "$CONFIG_FILE" "$COURSES_CACHE"
                success "Configuration reset"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"
    
    echo -e "${BOLD}${CYAN}$SCRIPT_NAME v$VERSION${NC}"
    echo ""
    
    check_dependencies
    init_config
    load_config
    
    [[ "$VERBOSE" == true ]] && info "Verbose logging enabled"
    [[ "$DRY_RUN" == true ]] && warning "DRY RUN mode - no changes will be made"
    
    if [[ -z "$CANVAS_URL" || -z "$API_TOKEN" ]]; then
        setup_canvas || exit 1
    elif ! test_api_connection; then
        warning "Stored API credentials invalid"
        setup_canvas || exit 1
    fi
    
    # Go directly to main menu - let user choose what they want to do
    main_menu
}

# Run main function with all arguments
main "$@"