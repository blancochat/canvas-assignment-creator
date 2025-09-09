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
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
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
    local response_file
    response_file=$(mktemp)
    
    local curl_args=(
        -s -w "%{http_code}"
        -H "Authorization: Bearer $API_TOKEN"
        -H "Content-Type: application/json"
        -X "$method"
    )
    
    [[ -n "$data" ]] && curl_args+=(-d "$data")
    
    local http_code
    http_code=$(curl "${curl_args[@]}" "$CANVAS_URL/api/v1$endpoint" -o "$response_file")
    
    log "API Request: $method $endpoint - HTTP $http_code"
    
    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        cat "$response_file"
        rm -f "$response_file"
        return 0
    else
        local error_msg
        error_msg=$(jq -r '.errors[]?.message // .message // "Unknown error"' "$response_file" 2>/dev/null || echo "API request failed")
        error "API Error ($http_code): $error_msg"
        rm -f "$response_file"
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
    
    if command -v gdate >/dev/null 2>&1; then
        gdate -d "$date_str" --iso-8601=seconds 2>/dev/null
    else
        date -d "$date_str" --iso-8601=seconds 2>/dev/null || date -j -f "%Y-%m-%d %H:%M" "$date_str" "+%Y-%m-%dT%H:%M:%S%z"
    fi
}

# Validate URL format
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        return 0
    else
        return 1
    fi
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
    if [[ "$url" =~ /d/([a-zA-Z0-9-_]+) ]]; then
        echo "${BASH_REMATCH[1]}"
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
    
    echo -e "\n${BOLD}${CYAN}Assignment Images${NC}" >&2
    echo "=================" >&2
    echo "You can add images to your assignment description." >&2
    echo "Options:" >&2
    echo "1. External image URLs (recommended)" >&2
    echo "2. Local image files (will be uploaded to Canvas)" >&2
    echo "" >&2
    
    read -r -p "Do you want to add images to this assignment? (y/N): " add_images
    if [[ "$add_images" != "y" && "$add_images" != "Y" ]]; then
        return 0
    fi
    
    local image_count=0
    while true; do
        echo "" >&2
        echo "Image $((image_count + 1)):" >&2
        echo "1. Enter content URL (embedded as responsive iframe)" >&2
        echo "2. Upload local file" >&2
        echo "3. Done adding images" >&2
        echo "" >&2
        read -r -p "Choose option (1-3): " image_option
        
        case $image_option in
            1)
                read -r -p "Enter content URL to embed as iframe (https://...): " image_url
                if [[ -z "$image_url" ]]; then
                    echo -e "${YELLOW}⚠${NC} No URL entered, skipping..." >&2
                    continue
                elif validate_url "$image_url"; then
                    read -r -p "Enter alt text/title (optional): " alt_text
                    
                    echo "Choose iframe sizing:" >&2
                    echo "1. Standard content (100% width, 300px height)" >&2
                    echo "2. Video/interactive (16:9 responsive aspect ratio)" >&2
                    echo "3. Custom dimensions" >&2
                    read -r -p "Select option (1-3, default: 1): " size_option
                    size_option="${size_option:-1}"
                    
                    local img_tag=""
                    case $size_option in
                        1)
                            # Standard content - Canvas LMS recommended default
                            img_tag="<iframe src=\"$image_url\" style=\"width: 100%; height: 300px; border: 1px solid #ccc; overflow: hidden;\""
                            [[ -n "$alt_text" ]] && img_tag="$img_tag title=\"$alt_text\""
                            img_tag="$img_tag></iframe>"
                            ;;
                        2)
                            # Responsive 16:9 aspect ratio - best for video/interactive content
                            local container_style="width: 100%; min-width: 400px; max-width: 800px;"
                            local wrapper_style="position: relative; width: 100%; overflow: hidden; padding-top: 56.25%;"
                            local iframe_style="position: absolute; top: 0; left: 0; right: 0; width: 100%; height: 100%; border: 1px solid #ccc;"
                            
                            img_tag="<div style=\"$container_style\"><div style=\"$wrapper_style\">"
                            img_tag="$img_tag<iframe src=\"$image_url\" style=\"$iframe_style\""
                            [[ -n "$alt_text" ]] && img_tag="$img_tag title=\"$alt_text\""
                            img_tag="$img_tag allowfullscreen></iframe></div></div>"
                            ;;
                        3)
                            # Custom dimensions
                            read -r -p "Enter width (default: 100%): " custom_width
                            custom_width="${custom_width:-100%}"
                            read -r -p "Enter height in pixels (default: 400): " custom_height
                            custom_height="${custom_height:-400}"
                            
                            # Add 'px' to height if it's just a number
                            [[ "$custom_height" =~ ^[0-9]+$ ]] && custom_height="${custom_height}px"
                            
                            img_tag="<iframe src=\"$image_url\" style=\"width: $custom_width; height: $custom_height; border: 1px solid #ccc; overflow: hidden;\""
                            [[ -n "$alt_text" ]] && img_tag="$img_tag title=\"$alt_text\""
                            img_tag="$img_tag></iframe>"
                            ;;
                    esac
                    
                    images_html="$images_html<p>$img_tag</p>"
                    echo -e "${GREEN}✓${NC} Content URL added as iframe" >&2
                    ((image_count++))
                else
                    echo -e "${RED}✗${NC} Invalid URL format: $image_url" >&2
                    echo -e "${RED}✗${NC} Please use a valid https:// or http:// URL" >&2
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
                elif validate_google_docs_url "$docs_url"; then
                    local doc_id doc_type template_url
                    doc_id=$(extract_google_docs_id "$docs_url")
                    doc_type=$(get_google_docs_type "$docs_url")
                    template_url=$(create_google_docs_template_url "$doc_id" "$doc_type")
                    
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
        return 0
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
            warning "No course selected. Please select a course first."
        elif [[ $course_count -eq 1 ]]; then
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
        echo "2. Select a single course"
        echo "3. Select multiple courses"
        echo "4. Refresh course list from Canvas"
        
        echo -e "\n${BOLD}UTILITIES${NC}"
        echo "5. Manage local files"
        echo "6. Reconfigure Canvas settings"
        echo "q. Quit"
        
        read -r -p "Choose option: " choice
        
        case $choice in
            1)
                # Create a new assignment
                local course_count=${#SELECTED_COURSE_IDS[@]:-0}
                if [[ $course_count -eq 0 ]]; then
                    error "No course selected."
                    read -r -p "Select a course now? (Y/n): " sel_choice
                    if [[ "$sel_choice" != "n" && "$sel_choice" != "N" ]]; then
                        display_courses || continue
                        # After selection, re-check and proceed
                        [[ ${#SELECTED_COURSE_IDS[@]:-0} -eq 0 ]] && continue
                    else
                        continue
                    fi
                fi
                
                # Re-evaluate count after potential selection
                course_count=${#SELECTED_COURSE_IDS[@]:-0}
                
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
                ;;
            2)
                # Select a single course
                if display_courses; then
                    # Ensure single selection state
                    SELECTED_COURSE_IDS=("${SELECTED_COURSE_ID}")
                    SELECTED_COURSE_NAMES=("${SELECTED_COURSE_NAME}")
                fi
                ;;
            3)
                # Select multiple courses
                select_multiple_courses || continue
                ;;
            4)
                # Refresh course list
                get_courses
                info "Course list has been refreshed."
                ;;
            5)
                # Manage files
                manage_files
                ;;
            6)
                # Reconfigure settings
                setup_canvas
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