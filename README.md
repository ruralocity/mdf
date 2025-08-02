# Mastodon Follower Tracker

A simple Ruby CLI tool to track your Mastodon followers over time and see who follows/unfollows you.

## Setup

1. Install dependencies:
   ```bash
   bundle install
   ```

2. Get your Mastodon access token:
   - Go to your Mastodon instance → Preferences → Development
   - Create a new application with `read:accounts` and `write:follows` scopes
   - Copy the access token

3. Run setup:
   ```bash
   ruby mastodon_tracker.rb setup
   ```

## Usage

### Launch TUI Interface
```bash
ruby mastodon_tracker.rb tui
```

### Command Line Interface

### Check for changes
```bash
ruby mastodon_tracker.rb check
```

### View history
```bash
ruby mastodon_tracker.rb history
```

### View statistics
```bash
ruby mastodon_tracker.rb stats
```

### View non-mutual follows
```bash
ruby mastodon_tracker.rb non_mutual
ruby mastodon_tracker.rb non_mutual --interactive  # Interactive unfollowing
```

### View account profile
```bash
ruby mastodon_tracker.rb profile @username@instance.com
```

### View followback candidates
```bash
ruby mastodon_tracker.rb followback
ruby mastodon_tracker.rb followback --interactive  # Interactive following
```

## Automation

Add to your crontab to check automatically:
```bash
# Check every hour
0 * * * * cd /path/to/mdf && ruby mastodon_tracker.rb check
```

## Features

- Track new followers and unfollowers
- Store historical data in SQLite database
- Rate limiting to respect API limits
- Simple CLI interface with Thor
- Configuration stored in home directory