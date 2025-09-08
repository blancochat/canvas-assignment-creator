# Canvas Assignment Creator

A comprehensive, user-friendly bash script that automates the creation of assignments in Canvas LMS using the Canvas API. Designed for educators with varying technical expertise.

## Features

### 🚀 Core Functionality
- **Interactive Assignment Creation**: Step-by-step guided process
- **Course Management**: Browse, select, and manage your Canvas courses  
- **Assignment Groups**: Integration with existing assignment groups
- **Multiple Submission Types**: Text entry, file upload, external tools, etc.
- **Flexible Grading**: Points, percentage, letter grades, pass/fail
- **Date Management**: Due dates, availability windows with validation
- **Draft & Published States**: Choose when to make assignments visible
- **Image Embedding**: Support for external URLs and local file uploads
- **File Management**: Upload and manage files with automatic Canvas integration
- **Google Docs Templates**: Embed copyable templates for student use
- **Multi-Course Deployment**: Create assignments in multiple courses simultaneously

### 🛡️ Security & Reliability
- **Secure API Token Storage**: Encrypted configuration management
- **Input Validation**: Comprehensive validation of all user inputs
- **Error Handling**: Graceful handling of API errors and network issues
- **Rate Limiting**: Respects Canvas API rate limits
- **Permission Validation**: Verifies user permissions before operations

### 🎨 User Experience
- **Colorized Output**: Enhanced readability with color-coded messages
- **Progress Indicators**: Clear feedback during operations
- **Configuration Persistence**: Save settings for future use
- **Comprehensive Help**: Built-in documentation and examples
- **Dry Run Mode**: Preview actions without making changes

### 🖼️ Image & File Handling
- **External Image URLs**: Direct embedding of hosted images
- **Local File Upload**: Automatic upload of local files to Canvas
- **File Structure Management**: Organized local file storage
- **Multiple Image Formats**: JPG, PNG, GIF, WebP, SVG support
- **Responsive Images**: Automatic sizing for optimal display
- **File Management Interface**: View, upload, and manage files
- **Canvas Integration**: Direct file referencing in assignments

### 📄 Google Docs Integration
- **Template Embedding**: Add copyable Google Docs, Sheets, or Slides
- **Automatic Copy Links**: Generate "Make a Copy" URLs for students
- **Multiple Document Types**: Documents, Spreadsheets, Presentations
- **Professional Styling**: Clean, bordered template displays
- **New Window Opening**: Templates open in new tabs/windows
- **URL Validation**: Automatic validation of Google Docs URLs

### 🎯 Multi-Course Deployment
- **Bulk Assignment Creation**: Deploy identical assignments to multiple courses
- **Flexible Selection**: Choose specific courses, ranges, or all courses
- **Progress Tracking**: Real-time status updates during deployment
- **Error Resilience**: Individual course failure handling and reporting
- **Batch Optimization**: API rate limiting and deployment pacing
- **Success Reporting**: Detailed summary with assignment URLs

## Requirements

### System Dependencies
- **bash** (4.0+)
- **curl** - For API communication
- **jq** - For JSON parsing
- **date** - For date validation and formatting

### Installation of Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install curl jq
```

**macOS:**
```bash
# Using Homebrew
brew install curl jq

# Using MacPorts  
sudo port install curl jq
```

**CentOS/RHEL:**
```bash
sudo yum install curl jq
# or on newer versions
sudo dnf install curl jq
```

## Installation

1. **Download the script:**
```bash
git clone <repository-url>
cd createassign
```

2. **Make it executable:**
```bash
chmod +x canvas-assign-creator.sh
```

3. **Optional - Add to PATH:**
```bash
# Add to your ~/.bashrc or ~/.zshrc
export PATH="/path/to/createassign:$PATH"

# Or create a symbolic link
sudo ln -s /path/to/createassign/canvas-assign-creator.sh /usr/local/bin/canvas-assign
```

## Setup

### Canvas API Token

1. Log in to your Canvas instance
2. Go to **Account → Settings**
3. Scroll to **Approved Integrations**
4. Click **New Access Token**
5. Enter a purpose (e.g., "Assignment Creator Script")
6. Set expiration date (optional)
7. Click **Generate Token**
8. **Copy and save the token immediately** (you won't be able to see it again)

### First Run

Run the script for initial setup:

```bash
./canvas-assign-creator.sh
```

The script will guide you through:
1. Canvas URL configuration
2. API token setup
3. Connection testing
4. Configuration saving

## Usage

### Basic Usage

```bash
./canvas-assign-creator.sh
```

This launches the interactive mode where you can:
1. Select a course from your favorited courses (or all active courses)
2. Create assignments with guided prompts
3. Configure all assignment properties
4. Add images to assignment descriptions
5. Add Google Docs templates
6. Review and confirm before creation

### Command Line Options

```bash
./canvas-assign-creator.sh [OPTIONS]

Options:
  -h, --help          Show help message and exit
  -v, --verbose       Enable verbose logging
  -d, --dry-run       Preview actions without making changes
  --setup             Force configuration setup
  --reset-config      Clear saved configuration
```

### Examples

**Interactive assignment creation:**
```bash
./canvas-assign-creator.sh
```

**Preview mode (no changes made):**
```bash
./canvas-assign-creator.sh --dry-run
```

**Verbose logging for troubleshooting:**
```bash
./canvas-assign-creator.sh --verbose
```

**Reconfigure Canvas settings:**
```bash
./canvas-assign-creator.sh --setup
```

## Assignment Configuration

### Required Fields
- **Assignment Name**: Descriptive title for the assignment
- **Points Possible**: Numeric value for grading

### Optional Fields
- **Description**: Rich text description (HTML supported)
- **Due Date**: When the assignment is due
- **Available From**: When students can access the assignment  
- **Available Until**: When the assignment becomes unavailable
- **Assignment Group**: Categorization within the course
- **Submission Types**: How students submit work
- **Grading Type**: Points, percentage, letter grade, or pass/fail
- **Published Status**: Draft or immediately published

### Date Format

Use the format: `YYYY-MM-DD HH:MM` (24-hour time)

**Examples:**
- `2024-03-15 23:59` (due at 11:59 PM)
- `2024-04-01 09:00` (available at 9:00 AM)
- Leave blank to skip optional dates

### Submission Types

1. **Online Text Entry**: Students type responses directly
2. **Online Upload**: Students upload files
3. **Both**: Text entry and file upload options
4. **External Tool**: Integration with external applications
5. **No Submission**: Information-only assignments

### Grading Types

1. **Points**: Traditional point-based grading
2. **Percentage**: Graded as percentages
3. **Letter Grade**: A, B, C, D, F grading
4. **Pass/Fail**: Binary pass/fail grading

### Adding Images to Assignments

The script provides two methods for including images in assignment descriptions:

#### Method 1: External Image URLs (Recommended)
1. During assignment creation, choose to add images
2. Select "Enter image URL" 
3. Provide the direct URL to your hosted image
4. Optionally add alt text and width specifications
5. Images are embedded using HTML `<img>` tags

**Example URLs:**
- `https://example.com/my-diagram.png`
- `https://university.edu/course-materials/chart.jpg`

#### Method 2: Local File Upload
1. During assignment creation, choose to add images
2. Select "Upload local file"
3. Provide the path to your local image file
4. The script automatically:
   - Copies the file to managed storage
   - Uploads it to Canvas via API
   - Embeds it in the assignment description
   - Generates proper Canvas file references

**Supported Formats:**
- JPG/JPEG images
- PNG images  
- GIF images
- WebP images
- SVG vector graphics

**Features:**
- Automatic responsive sizing (`max-width: 100%`)
- Proper alt text for accessibility
- Clean HTML generation
- File management and cleanup

### File Management

Access the file management interface from the main menu (option 5):

1. **List Local Files**: View all cached images and files
2. **Clear Local Files**: Remove all locally stored files  
3. **View Disk Usage**: Check storage space usage
4. **Upload File to Canvas**: Direct file upload to course

**File Storage Locations:**
- Images: `~/.canvas-config/images/`
- Files: `~/.canvas-config/files/`

### Adding Google Docs Templates

The script makes it easy to embed copyable Google Docs templates in assignments:

#### Step-by-Step Process
1. **During Assignment Creation**: After adding images, you'll be prompted for Google Docs templates
2. **Choose to Add Templates**: Select "y" when asked about adding Google Docs templates
3. **Enter Google Docs URL**: Provide the sharing URL from your Google Doc, Sheet, or Slides
4. **Customize Template**: Add a name and description for the template
5. **Automatic Processing**: The script generates a professional template display with copy link

#### Supported Google Docs URLs
- **Documents**: `https://docs.google.com/document/d/[ID]/edit`
- **Spreadsheets**: `https://docs.google.com/spreadsheets/d/[ID]/edit` 
- **Presentations**: `https://docs.google.com/presentation/d/[ID]/edit`

#### Template Features
- **Professional Display**: Each template appears in a styled box with clear instructions
- **Make a Copy Button**: Students get a prominent blue button to create their own copy
- **Automatic URL Generation**: The script converts sharing URLs to copy URLs automatically
- **New Window Opening**: Templates open in new tabs/windows via `target="_blank"`
- **Clear Instructions**: Each template includes usage instructions for students

#### Example Template Display
```html
📄 Essay Writing Template
This template provides a structured format for your essay assignment.

Google Document Template
[📋 Make a Copy]
Click the link above to create your own copy of this template
```

#### Best Practices
- **Limit to 3 Templates**: Keep assignments clear and focused
- **Use Descriptive Names**: Help students understand each template's purpose
- **Test Template Access**: Ensure sharing is enabled on your Google Docs
- **Provide Instructions**: Include brief descriptions of how to use each template

#### Making Your Google Docs Copyable
1. Open your Google Doc, Sheet, or Presentation
2. Click **Share** in the top-right corner
3. Set sharing to **"Anyone with the link can view"**
4. Copy the sharing URL for use in the script

### Multi-Course Assignment Deployment

The script supports creating identical assignments across multiple courses simultaneously:

#### Course Selection Options
```bash
# Multiple specific courses
Enter selection: 1 3 5

# Course ranges  
Enter selection: 1-3 7-9

# Combination of individual and ranges
Enter selection: 1 3-5 8

# All available courses
Enter selection: all
```

#### Multi-Course Workflow
1. **Launch Script**: Run the assignment creator
2. **Select Multiple Courses**: Choose courses using numbers, ranges, or 'all'
3. **Configure Assignment**: Set up assignment details (applied to all courses)
4. **Review Selection**: Confirm target courses and assignment settings
5. **Deploy**: Script creates assignments sequentially with progress tracking

#### Example Multi-Course Session
```
Select Multiple Favorited Courses
==================================
ℹ Showing your starred/favorited courses only

Available courses:
1. Biology 101 (BIO-101)
2. Chemistry 201 (CHEM-201)
3. Physics 301 (PHYS-301)
4. Advanced Biology (BIO-401)

Enter selection: 1 3 4
✓ Added 3 course(s) to selection

Currently selected courses:
  ✓ Biology 101 (BIO-101)
  ✓ Physics 301 (PHYS-301) 
  ✓ Advanced Biology (BIO-401)

Enter selection: done
✓ Selected 3 courses for assignment creation
```

#### Deployment Features
- **Progress Indicators**: Real-time status during creation
- **Individual Error Handling**: Continues if one course fails
- **Rate Limiting**: Automatic delays prevent API overload
- **Complete Summary**: Shows all created assignments with direct URLs
- **Batch Efficiency**: Single assignment configuration for all courses

### Course Selection & Favorites

The script intelligently manages course selection by prioritizing your most-used courses:

#### Favorited Courses Priority
- **Primary Display**: Shows favorited/starred courses first
- **Smart Fallback**: Displays all active courses if no favorites are set
- **Easy Switching**: Toggle between favorited and all courses in the interface
- **Clear Indicators**: Visual cues show whether you're viewing favorites or all courses

#### Setting Up Favorites in Canvas
1. **Login to Canvas**: Access your Canvas web interface
2. **Navigate to Courses**: Go to your courses list
3. **Star Courses**: Click the star (⭐) next to courses you use frequently
4. **Automatic Sync**: The script will automatically detect your favorites

#### Course Selection Interface
```
Select a Favorited Course
=========================
ℹ Showing your starred/favorited courses only

1. Advanced Biology (BIO-401)
2. Chemistry Lab (CHEM-301) 
3. Physics Fundamentals (PHYS-101)

Options:
a) Show all active courses
r) Refresh course list
q) Quit
```

#### Benefits of Using Favorites
- **Faster Navigation**: Skip through dozens of old courses
- **Focus on Current**: Only see courses you're actively teaching
- **Reduced Clutter**: Clean interface with relevant courses only
- **Semester Management**: Easy to update as terms change

#### Troubleshooting Course Selection
- **No Favorites Set**: Script automatically shows all active courses
- **Missing Courses**: Check if course is published and you're enrolled
- **Old Courses Showing**: Update your favorites in Canvas web interface
- **Permission Issues**: Ensure you have instructor/TA permissions

## Configuration Files

### Location
- **Config Directory**: `~/.canvas-config/`
- **Main Config**: `~/.canvas-config/config`
- **Course Cache**: `~/.canvas-config/courses_cache`
- **Log File**: `~/.canvas-config/canvas-assign.log`

### Manual Configuration

If needed, you can manually edit the config file:

```bash
# ~/.canvas-config/config
CANVAS_URL=https://your-institution.instructure.com
API_TOKEN=your_api_token_here
```

**Note:** The config file has restrictive permissions (600) for security.

## Troubleshooting

### Common Issues

**"Missing required dependencies"**
- Install curl and jq using your system's package manager
- See installation instructions above

**"API connection failed"**  
- Verify your Canvas URL is correct
- Check that your API token is valid and not expired
- Ensure you have network connectivity
- Try running with `--verbose` for detailed error messages

**"No active courses found"**
- Verify you're enrolled in courses for the current term
- Check that courses are published and active
- Try refreshing the course list

**"Permission denied errors"**
- Ensure you have instructor or TA permissions in the selected course
- Verify your API token has necessary scopes

### Verbose Logging

Enable detailed logging for troubleshooting:

```bash
./canvas-assign-creator.sh --verbose
```

This creates detailed logs in `~/.canvas-config/canvas-assign.log`

### Reset Configuration

If you encounter persistent issues:

```bash
./canvas-assign-creator.sh --reset-config
```

This clears all saved settings and forces reconfiguration.

## Security Considerations

- **API tokens are stored securely** with restricted file permissions
- **No tokens are logged** or displayed in plain text  
- **Input validation** prevents injection attacks
- **HTTPS connections** ensure encrypted communication
- **No sensitive data** is cached inappropriately

## Canvas API Rate Limits

The script respects Canvas API rate limits:
- **Default limit**: 700 requests per hour per token
- **Automatic retry** with exponential backoff on rate limit errors
- **Efficient caching** to minimize API calls

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source and available under the MIT License.

## Support

For issues and feature requests, please:
1. Check the troubleshooting section above
2. Review the verbose logs
3. Open an issue with detailed error information

## Changelog

### Version 1.0.0
- Initial release with full feature set
- Interactive assignment creation
- Course management and selection
- Comprehensive error handling
- Configuration persistence
- Security enhancements