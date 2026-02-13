# Contributing to PagerDuty-Slack Sync

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Issues

If you find a bug or have a feature request:

1. Check if the issue already exists in the GitHub/GitLab issues
2. If not, create a new issue with:
   - A clear, descriptive title
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Your environment (OS, bash version, etc.)
   - Relevant logs (use `--debug` flag)

### Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone <your-fork-url>
   cd pagerduty-2-slack
   ```

2. **Install development dependencies**
   ```bash
   # On macOS
   brew install shellcheck jq
   
   # On Ubuntu/Debian
   apt-get install shellcheck jq
   
   # On Alpine
   apk add shellcheck jq bash
   ```

3. **Make the script executable**
   ```bash
   chmod +x push_into_slack_group.sh
   chmod +x tests/test_script.sh
   ```

### Making Changes

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Follow coding standards**
   - Use shellcheck to validate your code: `shellcheck push_into_slack_group.sh`
   - Follow existing code style and conventions
   - Add comments for complex logic
   - Use meaningful variable names

3. **Test your changes**
   ```bash
   # Run the test suite
   ./tests/test_script.sh
   
   # Test with dry-run mode
   export PAGER_TOKEN="your-token"
   export SLACK_TOKEN="your-token"
   ./push_into_slack_group.sh --dry-run P123456 P654321 'test-group'
   
   # Test with debug logging
   ./push_into_slack_group.sh --debug P123456 P654321 'test-group'
   ```

4. **Update documentation**
   - Update README.md if adding new features
   - Add examples for new functionality
   - Update help text in the script if needed

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add feature description"
   ```
   
   Use conventional commit messages:
   - `feat:` for new features
   - `fix:` for bug fixes
   - `docs:` for documentation changes
   - `test:` for test additions/changes
   - `refactor:` for code refactoring
   - `ci:` for CI/CD changes

6. **Push and create a merge/pull request**
   ```bash
   git push origin feature/your-feature-name
   ```

## Code Style Guidelines

### Bash Best Practices

- Use `set -euo pipefail` at the start of scripts
- Quote all variable expansions: `"$var"` not `$var`
- Use `[[ ]]` for conditionals instead of `[ ]`
- Prefer functions over inline code
- Use local variables in functions
- Check return values of commands
- Provide helpful error messages

### Function Naming

- Use snake_case for function names
- Use descriptive names: `get_slack_user_id` not `get_id`
- Prefix internal/helper functions with underscore if needed

### Error Handling

- Return appropriate exit codes
- Log errors with `log_error`
- Provide actionable error messages
- Use retry logic for transient failures

### Logging

- Use appropriate log levels:
  - `log_debug` - Detailed debugging information
  - `log_verbose` - Additional information for troubleshooting
  - `log_info` - General informational messages
  - `log_warn` - Warning messages
  - `log_error` - Error messages

## Testing Guidelines

### Manual Testing Checklist

Before submitting a PR, test:

- [ ] Script runs with minimal arguments
- [ ] `--dry-run` mode works correctly
- [ ] `--help` displays correct information
- [ ] `--version` returns version number
- [ ] `--health-check` validates API connectivity
- [ ] Error handling works for invalid inputs
- [ ] Caching reduces API calls on subsequent runs
- [ ] Retry logic works for transient failures
- [ ] All verbosity levels work (`--quiet`, `--verbose`, `--debug`)
- [ ] Script works in CI/CD environment

### Adding Tests

When adding new features:

1. Add test cases to `tests/test_script.sh`
2. Ensure tests are idempotent
3. Clean up any test artifacts
4. Document what the test validates

## Release Process

1. Update version number in script (`VERSION` variable)
2. Update CHANGELOG.md (if exists)
3. Create a git tag: `git tag -a v2.0.0 -m "Release v2.0.0"`
4. Push tag: `git push origin v2.0.0`

## Questions?

If you have questions about contributing:

- Check existing issues and discussions
- Review the README.md for usage examples
- Reach out to maintainers

## License

By contributing, you agree that your contributions will be licensed under the same license as the project.
