# Contributing to Canvas Assignment Creator

Thank you for your interest in contributing to Canvas Assignment Creator! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/blancochat/canvas-assignment-creator/issues)
2. If not, create a new issue with:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Your environment (OS, bash version, Canvas instance)
   - Relevant log output (with sensitive data removed)

### Suggesting Features

1. Check existing [Issues](https://github.com/blancochat/canvas-assignment-creator/issues) for similar requests
2. Create a new issue with:
   - Clear description of the feature
   - Use case and benefits
   - Possible implementation approach

### Code Contributions

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes following the coding standards below
4. Test your changes thoroughly
5. Commit with clear, descriptive messages
6. Push to your fork and create a Pull Request

## Coding Standards

### Shell Script Guidelines

- Use `bash` (not `sh`) for script compatibility
- Include `#!/bin/bash` shebang
- Use `set -euo pipefail` for error handling
- Quote variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals instead of `[ ]`
- Prefix functions with descriptive names
- Use `local` for function variables

### Code Style

- Indent with 4 spaces (no tabs)
- Line length limit: 120 characters
- Use descriptive variable names
- Add comments for complex logic
- Follow existing patterns in the codebase

### Security

- Never commit API tokens or sensitive data
- Use secure file permissions (600) for config files
- Validate all user inputs
- Escape shell variables properly
- Use `>&2` for error messages and interactive prompts

### Testing

- Test with different Canvas instances if possible
- Verify all menu flows work correctly
- Test error handling paths
- Ensure dry-run mode works
- Test with various input types and edge cases

## Development Setup

1. Install dependencies:
   - `curl`
   - `jq`
   - `bash` 4.0+

2. Set up Canvas API access:
   - Generate API token in Canvas
   - Configure using the script's setup process

3. Test your changes:
   ```bash
   # Syntax check
   bash -n canvas-assign-creator.sh
   
   # Run with dry-run mode
   ./canvas-assign-creator.sh --dry-run
   ```

## Pull Request Process

1. Ensure your code follows the style guidelines
2. Update documentation if needed
3. Add/update tests for new features
4. Ensure CI checks pass
5. Provide clear description of changes
6. Reference related issues

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help maintain a welcoming environment
- Follow GitHub's community guidelines

## Questions?

Feel free to open an issue for questions about contributing or development setup.