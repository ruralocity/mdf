# Mastodon/Bluesky Follower Tracker
# Run `just help` to see organized commands

# Show organized help with grouped commands
default:
    @just help

# Show organized help with grouped commands
help:
    @echo "Mastodon/Bluesky Follower Tracker"
    @echo "=================================="
    @echo ""
    @echo "🚀 Quick Start:"
    @echo "  just install           Install dependencies"
    @echo "  just status            Show configuration status"
    @echo "  just setup-mastodon    Setup Mastodon account"
    @echo "  just setup-bluesky     Setup Bluesky account"
    @echo "  just mastodon          Launch Mastodon TUI"
    @echo "  just bluesky           Launch Bluesky TUI"
    @echo ""
    @echo "🐘 Mastodon Commands:"
    @echo "  just mastodon                    Launch Mastodon TUI"
    @echo "  just setup-mastodon              Setup account"
    @echo "  just check-mastodon              Quick follower check"
    @echo "  just history-mastodon            View follower history"
    @echo "  just stats-mastodon              Show stats"
    @echo "  just non-mutual-mastodon         View non-mutual follows"
    @echo "  just unfollow-mastodon           Interactive unfollowing"
    @echo "  just followback-mastodon         View followback candidates"
    @echo "  just follow-mastodon             Interactive following"
    @echo "  just profile-mastodon <handle>   View profile info"
    @echo "  just clean-mastodon              Clean up data"
    @echo ""
    @echo "🦋 Bluesky Commands:"
    @echo "  just bluesky                     Launch Bluesky TUI"
    @echo "  just setup-bluesky               Setup account"
    @echo "  just check-bluesky               Quick follower check"
    @echo "  just history-bluesky             View follower history"
    @echo "  just stats-bluesky               Show stats"
    @echo "  just non-mutual-bluesky          View non-mutual follows"
    @echo "  just unfollow-bluesky            Interactive unfollowing"
    @echo "  just followback-bluesky          View followback candidates"
    @echo "  just follow-bluesky              Interactive following"
    @echo "  just profile-bluesky <handle>    View profile info"
    @echo "  just clean-bluesky               Clean up data"
    @echo ""
    @echo "🛠️  Development Commands:"
    @echo "  just check-syntax                Run syntax check"
    @echo "  just lint                        Run linter"
    @echo "  just watch                       Watch for file changes"
    @echo ""
    @echo "🧹 Cleanup Commands:"
    @echo "  just clean-all                   Clean up all data"
    @echo ""
    @echo "💡 Tip: Run 'just --list' to see all commands alphabetically"

# Install dependencies
install:
    bundle install

# Show current configuration and database status
status:
    @echo "=== Configuration Status ==="
    @echo -n "Mastodon: "
    @test -f ~/.mastodon_tracker_config.json && echo "✅ Configured" || echo "❌ Not configured"
    @echo -n "Bluesky:  "
    @test -f ~/.bluesky_tracker_config.json && echo "✅ Configured" || echo "❌ Not configured"
    @echo ""
    @echo "=== Database Status ==="
    @echo -n "Mastodon DB: "
    @test -f ~/.mastodon_tracker.db && echo "✅ Exists" || echo "❌ Not found"
    @echo -n "Bluesky DB:  "
    @test -f ~/.bluesky_tracker.db && echo "✅ Exists" || echo "❌ Not found"

# Clean up all data (WARNING: destructive)
clean-all: clean-mastodon clean-bluesky
    @echo "All data cleaned."

# ============================================================================
# MASTODON COMMANDS
# ============================================================================

# Setup Mastodon account
setup-mastodon:
    ruby mastodon_tracker.rb setup --platform=mastodon

# Launch Mastodon TUI
mastodon:
    ruby mastodon_tracker.rb tui --platform=mastodon

# Quick check for Mastodon followers
check-mastodon:
    ruby mastodon_tracker.rb check --platform=mastodon

# View Mastodon follower history
history-mastodon:
    ruby mastodon_tracker.rb history --platform=mastodon

# Show Mastodon stats
stats-mastodon:
    ruby mastodon_tracker.rb stats --platform=mastodon

# View non-mutual follows on Mastodon
non-mutual-mastodon:
    ruby mastodon_tracker.rb non_mutual --platform=mastodon

# Interactive unfollow on Mastodon
unfollow-mastodon:
    ruby mastodon_tracker.rb non_mutual --platform=mastodon --interactive

# View followback candidates on Mastodon
followback-mastodon:
    ruby mastodon_tracker.rb followback --platform=mastodon

# Interactive follow on Mastodon
follow-mastodon:
    ruby mastodon_tracker.rb followback --platform=mastodon --interactive

# View Mastodon profile info (requires handle/username as argument)
profile-mastodon handle:
    ruby mastodon_tracker.rb profile "{{handle}}" --platform=mastodon

# Clean up Mastodon data (WARNING: destructive)
clean-mastodon:
    rm -f ~/.mastodon_tracker.db ~/.mastodon_tracker_config.json
    @echo "Mastodon data cleaned. Run 'just setup-mastodon' to reconfigure."

# ============================================================================
# BLUESKY COMMANDS
# ============================================================================

# Setup Bluesky account  
setup-bluesky:
    ruby mastodon_tracker.rb setup --platform=bluesky

# Launch Bluesky TUI
bluesky:
    ruby mastodon_tracker.rb tui --platform=bluesky

# Quick check for Bluesky followers
check-bluesky:
    ruby mastodon_tracker.rb check --platform=bluesky

# View Bluesky follower history (CLI)
history-bluesky:
    ruby mastodon_tracker.rb history --platform=bluesky

# Show Bluesky stats (CLI)
stats-bluesky:
    ruby mastodon_tracker.rb stats --platform=bluesky

# View non-mutual follows on Bluesky (CLI)
non-mutual-bluesky:
    ruby mastodon_tracker.rb non_mutual --platform=bluesky

# Interactive unfollow on Bluesky (CLI)
unfollow-bluesky:
    ruby mastodon_tracker.rb non_mutual --platform=bluesky --interactive

# View followback candidates on Bluesky (CLI)
followback-bluesky:
    ruby mastodon_tracker.rb followback --platform=bluesky

# Interactive follow on Bluesky (CLI)
follow-bluesky:
    ruby mastodon_tracker.rb followback --platform=bluesky --interactive

# View Bluesky profile info (requires handle as argument)
profile-bluesky handle:
    ruby mastodon_tracker.rb profile "{{handle}}" --platform=bluesky

# Clean up Bluesky data (WARNING: destructive)
clean-bluesky:
    rm -f ~/.bluesky_tracker.db ~/.bluesky_tracker_config.json
    @echo "Bluesky data cleaned. Run 'just setup-bluesky' to reconfigure."

# ============================================================================
# DEVELOPMENT COMMANDS
# ============================================================================

# Run syntax check on all Ruby files
check-syntax:
    ruby -c mastodon_tracker.rb
    ruby -c mastodon_tui.rb
    ruby -c bluesky_tracker.rb

# Run linter if available
lint:
    bundle exec rubocop || echo "Rubocop not available, skipping lint"

# Development: watch for file changes and run syntax check
watch:
    @echo "Watching for file changes... (Ctrl+C to stop)"
    @while true; do \
        inotifywait -q -e modify *.rb 2>/dev/null || fswatch -1 *.rb 2>/dev/null || (sleep 2; echo "Install inotifywait or fswatch for better file watching"); \
        just check-syntax; \
        echo "--- Waiting for changes ---; \
    done