require 'httparty'
require 'json'
require 'sqlite3'
require 'time'
require 'set'

class BlueskyTracker
  def initialize
    @session = nil
  end

  def load_config
    config_path = File.expand_path('~/.bluesky_tracker_config.json')
    return nil unless File.exist?(config_path)
    
    config = JSON.parse(File.read(config_path), symbolize_names: true)
    
    # Validate config
    if config[:handle].nil? || config[:handle].strip.empty? || 
       config[:password].nil? || config[:password].strip.empty?
      puts "Error: Invalid configuration. Please run setup again."
      return nil
    end
    
    config
  rescue JSON::ParserError
    puts "Error: Corrupted configuration file. Please run setup again."
    nil
  end

  def save_config(handle, password)
    config_path = File.expand_path('~/.bluesky_tracker_config.json')
    config = { handle: handle, password: password }
    File.write(config_path, JSON.pretty_generate(config))
  end

  def setup
    puts "Setting up Bluesky Follower Tracker..."
    
    print "Enter your Bluesky handle (e.g., user.bsky.social): "
    STDOUT.flush
    handle = STDIN.gets&.chomp&.strip
    
    if handle.nil? || handle.empty?
      puts "Error: Handle cannot be empty"
      return false
    end
    
    print "Enter your Bluesky password or app password: "
    STDOUT.flush
    password = STDIN.gets&.chomp&.strip
    
    if password.nil? || password.empty?
      puts "Error: Password cannot be empty"
      return false
    end
    
    # Test authentication
    if authenticate(handle, password)
      save_config(handle, password)
      init_database
      puts "Setup complete!"
      return true
    else
      puts "Authentication failed. Please check your credentials."
      return false
    end
  end

  def authenticate(handle, password)
    url = "https://bsky.social/xrpc/com.atproto.server.createSession"
    
    response = HTTParty.post(url, {
      headers: { 'Content-Type' => 'application/json' },
      body: { identifier: handle, password: password }.to_json
    })
    
    if response.success?
      @session = response.parsed_response
      true
    else
      false
    end
  end

  def ensure_authenticated
    config = load_config
    return false unless config
    
    return true if @session && @session['accessJwt']
    
    authenticate(config[:handle], config[:password])
  end

  def db_path
    File.expand_path('~/.bluesky_tracker.db')
  end

  def init_database
    db = SQLite3::Database.new(db_path)
    
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS current_followers (
        did TEXT PRIMARY KEY,
        handle TEXT,
        display_name TEXT,
        followers_count INTEGER,
        following_count INTEGER,
        created_at TEXT
      )
    SQL
    
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS follower_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        follower_did TEXT,
        handle TEXT,
        display_name TEXT,
        action TEXT,
        timestamp TEXT
      )
    SQL
    
    db.close
  end

  def fetch_followers
    return nil unless ensure_authenticated
    
    followers = []
    cursor = nil
    
    loop do
      url = "https://bsky.social/xrpc/app.bsky.graph.getFollowers"
      params = { actor: @session['did'], limit: 100 }
      params[:cursor] = cursor if cursor
      
      response = HTTParty.get(url, {
        headers: { 'Authorization' => "Bearer #{@session['accessJwt']}" },
        query: params
      })
      
      unless response.success?
        puts "Failed to fetch followers: #{response.code}"
        return nil
      end
      
      data = response.parsed_response
      batch = data['followers'].map do |follower|
        {
          did: follower['did'],
          handle: follower['handle'],
          display_name: follower['displayName'] || follower['handle'],
          followers_count: follower['followersCount'] || 0,
          following_count: follower['followsCount'] || 0,
          created_at: follower['createdAt']
        }
      end
      
      followers.concat(batch)
      
      cursor = data['cursor']
      break unless cursor
      
      sleep(0.5) # Rate limiting
    end
    
    followers
  end

  def fetch_following
    return nil unless ensure_authenticated
    
    following = []
    cursor = nil
    
    loop do
      url = "https://bsky.social/xrpc/app.bsky.graph.getFollows"
      params = { actor: @session['did'], limit: 100 }
      params[:cursor] = cursor if cursor
      
      response = HTTParty.get(url, {
        headers: { 'Authorization' => "Bearer #{@session['accessJwt']}" },
        query: params
      })
      
      unless response.success?
        puts "Failed to fetch following: #{response.code}"
        return nil
      end
      
      data = response.parsed_response
      batch = data['follows'].map do |follow|
        {
          did: follow['did'],
          handle: follow['handle'],
          display_name: follow['displayName'] || follow['handle'],
          followers_count: follow['followersCount'] || 0,
          following_count: follow['followsCount'] || 0,
          created_at: follow['createdAt']
        }
      end
      
      following.concat(batch)
      
      cursor = data['cursor']
      break unless cursor
      
      sleep(0.5) # Rate limiting
    end
    
    following
  end

  def fetch_account_details(did_or_handle)
    return nil unless ensure_authenticated
    
    url = "https://bsky.social/xrpc/app.bsky.actor.getProfile"
    
    response = HTTParty.get(url, {
      headers: { 'Authorization' => "Bearer #{@session['accessJwt']}" },
      query: { actor: did_or_handle }
    })
    
    if response.success?
      profile = response.parsed_response
      {
        did: profile['did'],
        handle: profile['handle'],
        display_name: profile['displayName'] || profile['handle'],
        description: profile['description'],
        followers_count: profile['followersCount'] || 0,
        following_count: profile['followsCount'] || 0,
        posts_count: profile['postsCount'] || 0,
        created_at: profile['createdAt'],
        avatar: profile['avatar']
      }
    else
      nil
    end
  end

  def fetch_account_posts(did_or_handle, limit = 5)
    return [] unless ensure_authenticated
    
    url = "https://bsky.social/xrpc/app.bsky.feed.getAuthorFeed"
    
    response = HTTParty.get(url, {
      headers: { 'Authorization' => "Bearer #{@session['accessJwt']}" },
      query: { actor: did_or_handle, limit: limit }
    })
    
    if response.success?
      data = response.parsed_response
      data['feed'].map do |item|
        post = item['post']
        {
          uri: post['uri'],
          text: post['record']['text'],
          created_at: post['record']['createdAt'],
          like_count: post['likeCount'] || 0,
          repost_count: post['repostCount'] || 0,
          reply_count: post['replyCount'] || 0
        }
      end
    else
      []
    end
  end

  def follow_account(did_or_handle)
    return false unless ensure_authenticated
    
    url = "https://bsky.social/xrpc/com.atproto.repo.createRecord"
    
    response = HTTParty.post(url, {
      headers: { 
        'Authorization' => "Bearer #{@session['accessJwt']}",
        'Content-Type' => 'application/json'
      },
      body: {
        repo: @session['did'],
        collection: 'app.bsky.graph.follow',
        record: {
          subject: did_or_handle,
          createdAt: Time.now.utc.iso8601
        }
      }.to_json
    })
    
    response.success?
  end

  def unfollow_account(did_or_handle)
    # This is more complex in Bluesky - you need to find the follow record first
    # For now, return false as it requires additional API calls
    false
  end

  def check
    return puts "Please run setup first!" unless load_config
    
    current_followers = fetch_followers
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
      new_followers.each { |f| puts "  + #{f[:display_name]} (@#{f[:handle]})" }
      log_changes(new_followers, 'follow')
    end
    
    if unfollowers.any?
      puts "\n💔 Unfollowers (#{unfollowers.length}):"
      unfollowers.each { |f| puts "  - #{f[:display_name]} (@#{f[:handle]})" }
      log_changes(unfollowers, 'unfollow')
    end
    
    if new_followers.empty? && unfollowers.empty?
      puts "No changes in followers"
    end
    
    store_followers(current_followers)
    puts "\nTotal followers: #{current_followers.length}"
  end

  def get_previous_followers
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    
    rows = db.execute("SELECT * FROM current_followers")
    
    rows.map do |row|
      {
        did: row['did'],
        handle: row['handle'],
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
        [follower[:did], follower[:handle], follower[:display_name], 
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
        "INSERT INTO follower_changes (follower_did, handle, display_name, action, timestamp) VALUES (?, ?, ?, ?, ?)",
        [follower[:did], follower[:handle], follower[:display_name], action, Time.now.iso8601]
      )
    end
  ensure
    db&.close
  end

  def get_recent_changes(limit = 15)
    begin
      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      db.execute("SELECT * FROM follower_changes ORDER BY timestamp DESC LIMIT ?", [limit])
    rescue
      []
    ensure
      db&.close
    end
  end

  def stats
    db = SQLite3::Database.new(db_path)
    
    total = db.execute("SELECT COUNT(*) FROM current_followers")[0][0]
    follows = db.execute("SELECT COUNT(*) FROM follower_changes WHERE action = 'follow'")[0][0]
    unfollows = db.execute("SELECT COUNT(*) FROM follower_changes WHERE action = 'unfollow'")[0][0]
    
    {
      followers: total,
      follows_tracked: follows,
      unfollows_tracked: unfollows,
      net_change: follows - unfollows
    }
  ensure
    db&.close
  end
end