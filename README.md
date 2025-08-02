# MDF: Track followers in Mastodon and Bsky

A Ruby CLI tool with TUI interface to track your followers over time on both Mastodon and Bluesky. See who follows/unfollows you, manage non-mutual follows, and discover followback candidates.

## Quick Start with Just

Install [just](https://github.com/casey/just) and run:

```bash
# Install dependencies
just install

# Setup your accounts
just setup-mastodon
just setup-bluesky

# Launch TUI interfaces
just mastodon    # 🐘 Mastodon TUI
just bluesky     # 🦋 Bluesky TUI

# See all available commands
just
```

## Manual Setup

1. Install dependencies:
   ```bash
   bundle install
   ```

2. Get your access credentials:

   **Mastodon:**
   - Go to your Mastodon instance → Preferences → Development
   - Create a new application with `read:accounts` and `write:follows` scopes
   - Copy the access token

   **Bluesky:**
   - Use your handle (e.g., user.bsky.social) and password
   - Or create an app password in Settings → Privacy and Security

3. Run setup:
   ```bash
   ruby mastodon_tracker.rb setup                    # Mastodon
   ruby mastodon_tracker.rb setup --platform=bluesky # Bluesky
   ```

## Usage

### Launch TUI Interface
```bash
ruby mastodon_tracker.rb tui                    # Mastodon (default)
ruby mastodon_tracker.rb tui --platform=bluesky # Bluesky

# Or with just:
just mastodon
just bluesky
```

### Setup
```bash
ruby mastodon_tracker.rb setup                    # Mastodon (default)
ruby mastodon_tracker.rb setup --platform=bluesky # Bluesky
```

### Command Line Interface

### Check for changes
```bash
ruby mastodon_tracker.rb check
ruby mastodon_tracker.rb check --platform=bluesky
```

### View history
```bash
ruby mastodon_tracker.rb history
ruby mastodon_tracker.rb history --platform=bluesky
```

### View statistics
```bash
ruby mastodon_tracker.rb stats
ruby mastodon_tracker.rb stats --platform=bluesky
```

### View non-mutual follows
```bash
ruby mastodon_tracker.rb non_mutual
ruby mastodon_tracker.rb non_mutual --interactive  # Interactive unfollowing
ruby mastodon_tracker.rb non_mutual --platform=bluesky
```

### View followback candidates
```bash
ruby mastodon_tracker.rb followback
ruby mastodon_tracker.rb followback --interactive  # Interactive following
ruby mastodon_tracker.rb followback --platform=bluesky
```

### View account profile
```bash
ruby mastodon_tracker.rb profile @username@instance.com
ruby mastodon_tracker.rb profile user.bsky.social --platform=bluesky
```

## TUI Features

### Navigation
- **↑↓ Arrow keys** or **j/k** to navigate through accounts
- **Space** to toggle selection on current account
- **I** to view detailed info about the currently highlighted account
- **F/U** to follow/unfollow selected accounts
- **A/N** to select all/none
- **Q** to quit back to main menu

### Views
- **Main Dashboard** - Recent changes, stats, quick actions
- **History** - Tabular view of all follower changes
- **Non-mutual** - Accounts you follow who don't follow back
- **Followback** - Accounts that follow you but you don't follow back
- **Account Details** - Full profile with bio, stats, recent posts

## Automation

Add to your crontab to check automatically:
```bash
# Check every hour
0 * * * * cd /path/to/mdf && just check-mastodon
0 * * * * cd /path/to/mdf && just check-bluesky
```

## Features

- **Dual Platform Support** - Track both Mastodon and Bluesky accounts
- **Rich TUI Interface** - Full-screen terminal interface with navigation
- **Follower Change Tracking** - See exactly who follows/unfollows you
- **Non-mutual Management** - Find and unfollow accounts that don't follow back
- **Followback Discovery** - Find followers you haven't followed back
- **Account Details** - View profiles, bios, and recent posts before following
- **Bulk Operations** - Select multiple accounts for batch follow/unfollow
- **Historical Data** - SQLite database stores all changes over time
- **Rate Limiting** - Respects API limits with built-in delays
- **Cross-platform** - Works on macOS, Linux, and Windows
