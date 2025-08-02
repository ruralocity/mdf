#!/usr/bin/env ruby

require 'httparty'
require 'json'
require 'sqlite3'
require 'thor'
require 'set'

class MastodonTracker < Thor
  desc "setup", "Setup your Mastodon instance and access token"
  def setup
    puts "Setting up Mastodon Follower Tracker..."
    
    print "Enter your Mastodon instance URL (e.g., mastodon.social): "
    STDOUT.flush
    instance = STDIN.gets&.chomp&.strip
    
    # Validate and format instance URL
    if instance.nil? || instance.empty?
      puts "Error: Instance URL cannot be empty"
      return
    end
    
    instance = "https://#{instance}" unless instance.start_with?('http')
    
    # Basic URL validation
    unless instance.match?(/^https?:\/\/[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/)
      puts "Error: Invalid instance URL format"
      return
    end
    
    print "Enter your access token: "
    STDOUT.flush
    token = STDIN.gets&.chomp&.strip
    
    if token.nil? || token.empty?
      puts "Error: Access token cannot be empty"
      return
    end
    
    save_config(instance, token)
    init_database
    
    puts "Setup complete! Run 'ruby mastodon_tracker.rb check' to start tracking."
  end

  desc "check", "Check for new followers/unfollowers"
  def check
    config = load_config
    return puts "Please run setup first!" unless config
    
    current_followers = fetch_followers(config[:instance], config[:token])
    return puts "Failed to fetch followers" unless current_followers
    
    previous_followers = get_previous_followers
    
    if previous_followers.empty?
      puts "First run - storing #{current_followers.length} followers"
      store_followers(current_followers)
      return
    end
    
    new_followers = current_followers - previous_followers
    unfollowers = previous_followers - current_followers
    
    if new_followers.any?
      puts "\n🎉 New followers (#{new_followers.length}):"
      new_followers.each { |f| puts "  + #{f[:display_name]} (@#{f[:acct]})" }
      log_changes(new_followers, 'follow')
    end
    
    if unfollowers.any?
      puts "\n💔 Unfollowers (#{unfollowers.length}):"
      unfollowers.each { |f| puts "  - #{f[:display_name]} (@#{f[:acct]})" }
      log_changes(unfollowers, 'unfollow')
    end
    
    if new_followers.empty? && unfollowers.empty?
      puts "No changes in followers"
    end
    
    store_followers(current_followers)
    puts "\nTotal followers: #{current_followers.length}"
  end

  desc "history", "Show follower change history"
  def history
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    
    changes = db.execute("SELECT * FROM follower_changes ORDER BY timestamp DESC LIMIT 50")
    
    if changes.empty?
      puts "No history found. Run 'check' first!"
      return
    end
    
    puts "Recent follower changes:\n"
    changes.each do |change|
      time = Time.parse(change['timestamp']).strftime('%Y-%m-%d %H:%M')
      action = change['action'] == 'follow' ? '🎉' : '💔'
      puts "#{time} #{action} #{change['display_name']} (@#{change['acct']})"
    end
  end

  desc "non_mutual", "Show accounts you follow who don't follow you back (with optional unfollowing)"
  option :interactive, type: :boolean, default: false, aliases: '-i', desc: 'Interactively unfollow accounts'
  def non_mutual
    config = load_config
    return puts "Please run setup first!" unless config
    
    puts "Fetching your followers..."
    followers = fetch_followers(config[:instance], config[:token])
    return puts "Failed to fetch followers" unless followers
    
    puts "Fetching accounts you follow..."
    following = fetch_following(config[:instance], config[:token])
    return puts "Failed to fetch following list" unless following
    
    follower_ids = followers.map { |f| f[:id] }.to_set
    
    non_mutual = following.reject { |f| follower_ids.include?(f[:id]) }
    
    if non_mutual.empty?
      puts "🎉 All accounts you follow also follow you back!"
      return
    end
    
    puts "\n💔 Accounts you follow who don't follow back (#{non_mutual.length}):"
    
    if options[:interactive]
      unfollowed_count = 0
      
      non_mutual.each_with_index do |account, index|
        puts "\n[#{index + 1}/#{non_mutual.length}] #{account[:display_name]} (@#{account[:acct]})"
        puts "  Followers: #{account[:followers_count]} | Following: #{account[:following_count]}"
        
        print "Unfollow this account? [y/N/q(uit)]: "
        response = STDIN.gets.chomp.downcase
        
        case response
        when 'y', 'yes'
          if unfollow_account(config[:instance], config[:token], account[:id])
            puts "  ✅ Unfollowed #{account[:display_name]}"
            unfollowed_count += 1
          else
            puts "  ❌ Failed to unfollow #{account[:display_name]}"
          end
        when 'q', 'quit'
          puts "Stopping..."
          break
        else
          puts "  ⏭️  Skipped"
        end
        
        sleep(1) # Rate limiting
      end
      
      puts "\n📊 Summary:"
      puts "Accounts unfollowed: #{unfollowed_count}"
    else
      non_mutual.each do |account|
        puts "  #{account[:display_name]} (@#{account[:acct]}) - #{account[:followers_count]} followers"
      end
      
      puts "\n💡 Tip: Use --interactive or -i to interactively unfollow accounts"
    end
    
    puts "\nSummary:"
    puts "You follow: #{following.length}"
    puts "Follow you: #{followers.length}"
    puts "Non-mutual: #{non_mutual.length}"
  end

  desc "stats", "Show follower statistics"
  def stats
    db = SQLite3::Database.new(db_path)
    
    total = db.execute("SELECT COUNT(*) FROM current_followers")[0][0]
    
    follows = db.execute("SELECT COUNT(*) FROM follower_changes WHERE action = 'follow'")[0][0]
    unfollows = db.execute("SELECT COUNT(*) FROM follower_changes WHERE action = 'unfollow'")[0][0]
    
    puts "📊 Follower Statistics:"
    puts "Current followers: #{total}"
    puts "Total follows tracked: #{follows}"
    puts "Total unfollows tracked: #{unfollows}"
    puts "Net change: +#{follows - unfollows}"
  end

  private

  def config_path
    File.expand_path('~/.mastodon_tracker_config.json')
  end

  def db_path
    File.expand_path('~/.mastodon_tracker.db')
  end

  def save_config(instance, token)
    config = { instance: instance, token: token }
    File.write(config_path, JSON.pretty_generate(config))
  end

  def load_config
    return nil unless File.exist?(config_path)
    
    config = JSON.parse(File.read(config_path), symbolize_names: true)
    
    # Validate config
    if config[:instance].nil? || config[:instance].strip.empty? || 
       config[:token].nil? || config[:token].strip.empty?
      puts "Error: Invalid configuration. Please run setup again."
      return nil
    end
    
    config
  rescue JSON::ParserError
    puts "Error: Corrupted configuration file. Please run setup again."
    nil
  end

  def init_database
    db = SQLite3::Database.new(db_path)
    
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS current_followers (
        id TEXT PRIMARY KEY,
        acct TEXT,
        display_name TEXT,
        followers_count INTEGER,
        following_count INTEGER,
        created_at TEXT
      )
    SQL
    
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS follower_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        follower_id TEXT,
        acct TEXT,
        display_name TEXT,
        action TEXT,
        timestamp TEXT
      )
    SQL
    
    db.close
  end

  def fetch_followers(instance, token)
    url = "#{instance}/api/v1/accounts/verify_credentials"
    
    response = HTTParty.get(url, headers: {
      'Authorization' => "Bearer #{token}"
    })
    
    unless response.success?
      puts "Failed to verify credentials: #{response.code}"
      return nil
    end
    
    account_id = response['id']
    followers = []
    next_url = "#{instance}/api/v1/accounts/#{account_id}/followers?limit=80"
    
    while next_url
      response = HTTParty.get(next_url, headers: {
        'Authorization' => "Bearer #{token}"
      })
      
      unless response.success?
        puts "Failed to fetch followers: #{response.code}"
        return nil
      end
      
      batch = response.parsed_response.map do |follower|
        {
          id: follower['id'],
          acct: follower['acct'],
          display_name: follower['display_name'] || follower['username'],
          followers_count: follower['followers_count'],
          following_count: follower['following_count'],
          created_at: follower['created_at']
        }
      end
      
      followers.concat(batch)
      
      link_header = response.headers['link']
      next_url = parse_next_url(link_header)
      
      sleep(0.5) # Rate limiting
    end
    
    followers
  end

  def fetch_following(instance, token)
    url = "#{instance}/api/v1/accounts/verify_credentials"
    
    response = HTTParty.get(url, headers: {
      'Authorization' => "Bearer #{token}"
    })
    
    unless response.success?
      puts "Failed to verify credentials: #{response.code}"
      return nil
    end
    
    account_id = response['id']
    following = []
    next_url = "#{instance}/api/v1/accounts/#{account_id}/following?limit=80"
    
    while next_url
      response = HTTParty.get(next_url, headers: {
        'Authorization' => "Bearer #{token}"
      })
      
      unless response.success?
        puts "Failed to fetch following list: #{response.code}"
        return nil
      end
      
      batch = response.parsed_response.map do |account|
        {
          id: account['id'],
          acct: account['acct'],
          display_name: account['display_name'] || account['username'],
          followers_count: account['followers_count'],
          following_count: account['following_count'],
          created_at: account['created_at']
        }
      end
      
      following.concat(batch)
      
      link_header = response.headers['link']
      next_url = parse_next_url(link_header)
      
      sleep(0.5) # Rate limiting
    end
    
    following
  end

  def unfollow_account(instance, token, account_id)
    url = "#{instance}/api/v1/accounts/#{account_id}/unfollow"
    
    response = HTTParty.post(url, headers: {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json'
    })
    
    response.success?
  end

  def parse_next_url(link_header)
    return nil unless link_header
    
    links = link_header.split(',')
    next_link = links.find { |link| link.include?('rel="next"') }
    return nil unless next_link
    
    next_link.match(/<([^>]+)>/)[1]
  end

  def get_previous_followers
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    
    rows = db.execute("SELECT * FROM current_followers")
    
    rows.map do |row|
      {
        id: row['id'],
        acct: row['acct'],
        display_name: row['display_name'],
        followers_count: row['followers_count'],
        following_count: row['following_count'],
        created_at: row['created_at']
      }
    end
  ensure
    db&.close
  end

  def store_followers(followers)
    db = SQLite3::Database.new(db_path)
    
    db.execute("DELETE FROM current_followers")
    
    followers.each do |follower|
      db.execute(
        "INSERT INTO current_followers VALUES (?, ?, ?, ?, ?, ?)",
        [follower[:id], follower[:acct], follower[:display_name], 
         follower[:followers_count], follower[:following_count], follower[:created_at]]
      )
    end
  ensure
    db&.close
  end

  def log_changes(followers, action)
    db = SQLite3::Database.new(db_path)
    
    followers.each do |follower|
      db.execute(
        "INSERT INTO follower_changes (follower_id, acct, display_name, action, timestamp) VALUES (?, ?, ?, ?, ?)",
        [follower[:id], follower[:acct], follower[:display_name], action, Time.now.iso8601]
      )
    end
  ensure
    db&.close
  end
end

MastodonTracker.start(ARGV)