# CRUSH Configuration

## Build/Test Commands
```bash
# Install dependencies
just install
bundle install

# Launch TUI interfaces
just mastodon    # Mastodon TUI
just bluesky     # Bluesky TUI

# Setup accounts
just setup-mastodon
just setup-bluesky

# Quick checks
just check-mastodon
just check-bluesky

# Test
bundle exec rspec

# Lint/Format
bundle exec rubocop
bundle exec rubocop -a  # auto-fix
just lint               # via justfile
```

## Code Style Guidelines

### General
- Use 2 spaces for indentation (Ruby standard)
- Prefer explicit over implicit
- Write self-documenting code with clear variable names
- Keep methods small and focused

### Naming Conventions
- Use snake_case for variables/methods (Ruby standard)
- Use PascalCase for classes/modules
- Use UPPER_SNAKE_CASE for constants
- Use descriptive names that explain intent

### Error Handling
- Always handle errors explicitly
- Use proper error types and messages
- Log errors with context
- Fail fast when appropriate

### Imports/Dependencies
- Group imports logically (stdlib, third-party, local)
- Use absolute imports when possible
- Avoid circular dependencies