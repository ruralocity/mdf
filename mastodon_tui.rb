require 'stringio'
require 'set'

# TUI gems
require 'tty-box'
require 'tty-cursor'
require 'tty-screen'
require 'tty-table'
require 'tty-prompt'
require 'tty-spinner'
require 'pastel'

class MastodonTUI
  def initialize(tracker, platform = 'mastodon')
    @tracker = tracker
    @platform = platform
    @cursor = TTY::Cursor
    @pastel = Pastel.new
    @prompt = TTY::Prompt.new
    @running = true
  end

  def start
    setup_screen
    show_main_dashboard
  ensure
    cleanup_screen
  end

  private

  def setup_screen
    print @cursor.clear_screen
    print @cursor.hide
  end

  def cleanup_screen
    print @cursor.show
    print @cursor.move_to(0, TTY::Screen.height)
  end

  def show_main_dashboard
    while @running
      draw_main_dashboard
      handle_main_input
    end
  end

  def draw_main_dashboard
    print @cursor.move_to(0, 0)
    
    config = @tracker.load_config
    stats = get_current_stats
    recent_changes = get_recent_changes(15) # Get more changes to fill space
    
    # Calculate available space
    total_height = TTY::Screen.height
    header_height = 3
    stats_height = 6
    menu_height = 3
    available_for_changes = total_height - header_height - stats_height - menu_height - 2 # padding
    
    # Header
    platform_emoji = @platform == 'bluesky' ? '🦋' : '🐘'
    platform_name = @platform.capitalize
    
    header = TTY::Box.frame(
      title: { top_left: " #{platform_emoji} #{platform_name} Follower Tracker " },
      width: TTY::Screen.width,
      height: header_height,
      border: :thick
    ) do
      if @platform == 'mastodon'
        instance = config ? config[:instance].gsub('https://', '') : 'Not configured'
        "Instance: #{instance}#{' ' * 20}Last Check: #{get_last_check_time}"
      else
        handle = config ? config[:handle] : 'Not configured'
        "Handle: #{handle}#{' ' * 20}Last Check: #{get_last_check_time}"
      end
    end
    
    # Stats section
    stats_content = if stats
      followers = stats[:followers] || 0
      following = stats[:following] || 0
      non_mutual = stats[:non_mutual] || 0
      
      "📊 Current Stats\n" +
      "   Followers: #{@pastel.green(followers)}    Following: #{@pastel.blue(following)}    Non-mutual: #{@pastel.yellow(non_mutual)}\n" +
      "   Today: #{format_daily_changes}\n" +
      "   Terminal: #{TTY::Screen.width}x#{TTY::Screen.height}"
    else
      "📊 No data available - run a check first\n" +
      "   Terminal: #{TTY::Screen.width}x#{TTY::Screen.height}"
    end
    
    stats_box = TTY::Box.frame(
      width: TTY::Screen.width,
      height: stats_height,
      border: :light
    ) { stats_content }
    
    # Recent changes section - use remaining space
    changes_content = if recent_changes.any?
      max_changes = [recent_changes.length, available_for_changes - 3].max # Leave room for title and padding
      displayed_changes = recent_changes.first(max_changes)
      
      "🔄 Recent Changes (showing #{displayed_changes.length}/#{recent_changes.length})\n" + 
      displayed_changes.map do |change|
        time = Time.parse(change['timestamp']).strftime('%m-%d %H:%M')
        emoji = change['action'] == 'follow' ? '🎉' : '💔'
        action = change['action'] == 'follow' ? 'followed' : 'unfollowed'
        
        if @platform == 'mastodon'
          "   #{time}  #{emoji} #{change['display_name']} (@#{change['acct']}) #{action} you"
        else
          "   #{time}  #{emoji} #{change['display_name']} (@#{change['handle']}) #{action} you"
        end
      end.join("\n")
    else
      "🔄 Recent Changes\n   No recent changes - run a check to see activity"
    end
    
    changes_box = TTY::Box.frame(
      width: TTY::Screen.width,
      height: available_for_changes,
      border: :light
    ) { changes_content }
    
    # Menu
    menu_box = TTY::Box.frame(
      width: TTY::Screen.width,
      height: menu_height,
      border: :light
    ) { "[C]heck Now  [H]istory  [N]on-mutual  [F]ollowback  [S]ettings  [Q]uit" }
    
    print header + stats_box + changes_box + menu_box
  end

  def handle_main_input
    key = nil
    begin
      # Use a simpler approach for key input
      system("stty raw -echo")
      key = STDIN.getc
    ensure
      system("stty -raw echo")
    end
    
    case key&.downcase
    when 'c'
      run_check
    when 'h'
      show_history_view
    when 'n'
      show_non_mutual_view
    when 'f'
      show_followback_view
    when 's'
      show_settings
    when 'q'
      @running = false
    end
  end

  def run_check
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    spinner = TTY::Spinner.new("[:spinner] Checking for follower changes...", format: :dots)
    spinner.auto_spin
    
    begin
      # Capture the output from the check command
      old_stdout = $stdout
      $stdout = StringIO.new
      
      @tracker.check
      
      output = $stdout.string
      $stdout = old_stdout
      
      spinner.success("Check complete!")
      
      # Show results
      puts "\n" + TTY::Box.frame(
        title: { top_left: " Check Results " },
        width: [60, TTY::Screen.width - 4].min,
        padding: 1
      ) { output }
      
      puts "\nPress any key to continue..."
      
      begin
        system("stty raw -echo")
        STDIN.getc
      ensure
        system("stty -raw echo")
      end
      
    rescue => e
      spinner.error("Check failed!")
      puts "\nError: #{e.message}"
      puts "Press any key to continue..."
      
      begin
        system("stty raw -echo")
        STDIN.getc
      ensure
        system("stty -raw echo")
      end
    ensure
      $stdout = old_stdout if old_stdout
    end
  end

  def show_history_view
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    # Get database connection based on platform
    if @platform == 'mastodon'
      db = SQLite3::Database.new(@tracker.db_path)
      db.results_as_hash = true
    end
    
    # Calculate how many changes we can show based on terminal height
    available_height = TTY::Screen.height - 6 # Leave room for header, footer, padding
    max_changes = [available_height - 2, 50].min # At least 2 lines for content, max 50 records
    
    if @platform == 'mastodon'
      changes = db.execute("SELECT * FROM follower_changes ORDER BY timestamp DESC LIMIT ?", [max_changes])
    else
      changes = @tracker.get_recent_changes(max_changes)
    end
    
    if changes.empty?
      content = "No history found. Run a check first!"
    else
      table = TTY::Table.new(
        header: ['Time', 'Action', 'User', 'Handle'],
        rows: changes.map do |change|
          time = Time.parse(change['timestamp']).strftime('%m-%d %H:%M')
          emoji = change['action'] == 'follow' ? '🎉' : '💔'
          action = change['action'] == 'follow' ? 'Follow' : 'Unfollow'
          
          if @platform == 'mastodon'
            [time, "#{emoji} #{action}", change['display_name'], "@#{change['acct']}"]
          else
            [time, "#{emoji} #{action}", change['display_name'], "@#{change['handle']}"]
          end
        end
      )
      content = table.render(:unicode, padding: [0, 1])
    end
    
    box = TTY::Box.frame(
      title: { top_left: " Follower History (#{changes.length} recent) " },
      width: TTY::Screen.width,
      height: TTY::Screen.height - 2, # Use almost full height
      padding: 1
    ) { content }
    
    puts box
    puts "[B]ack to main menu"
    
    key = nil
    loop do
      begin
        system("stty raw -echo")
        key = STDIN.getc
      ensure
        system("stty -raw echo")
      end
      
      case key&.downcase
      when 'b'
        break
      end
    end
    
    db&.close if @platform == 'mastodon'
  end

  def show_non_mutual_view
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    spinner = TTY::Spinner.new("[:spinner] Fetching non-mutual follows...", format: :dots)
    spinner.auto_spin
    
    begin
      config = @tracker.load_config
      return puts "Please run setup first!" unless config
      
      if @platform == 'mastodon'
        followers = @tracker.fetch_followers(config[:instance], config[:token])
        following = @tracker.fetch_following(config[:instance], config[:token])
      else
        # Bluesky methods don't take parameters - they handle auth internally
        followers = @tracker.fetch_followers
        following = @tracker.fetch_following
      end
      
      return puts "Failed to fetch data" unless followers && following
      
      if @platform == 'mastodon'
        follower_ids = followers.map { |f| f[:id] }.to_set
        non_mutual = following.reject { |f| follower_ids.include?(f[:id]) }
      else
        follower_ids = followers.map { |f| f[:did] }.to_set
        non_mutual = following.reject { |f| follower_ids.include?(f[:did]) }
      end
      
      spinner.success("Found #{non_mutual.length} non-mutual follows")
      
      if non_mutual.empty?
        puts "\n🎉 All accounts you follow also follow you back!"
        puts "Press any key to continue..."
        
        begin
          system("stty raw -echo")
          STDIN.getc
        ensure
          system("stty -raw echo")
        end
        return
      end
      
      # Interactive navigation
      current_index = 0
      selected = Set.new
      
      loop do
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        
        # Header
        puts TTY::Box.frame(
          title: { top_left: " Non-Mutual Follows " },
          width: TTY::Screen.width,
          height: 3
        ) { "#{non_mutual.length} accounts • #{selected.length} selected • Use ↑↓ to navigate" }
        
        # Account list with navigation - show more accounts based on terminal height
        available_height = TTY::Screen.height - 8 # Leave room for header, instructions, etc.
        display_count = [available_height, 20].min # Show up to 20 accounts or terminal height
        
        display_start = [0, current_index - display_count/2].max
        display_end = [non_mutual.length, display_start + display_count].min
        
        # Adjust start if we're near the end
        if display_end - display_start < display_count && display_start > 0
          display_start = [0, display_end - display_count].max
        end
        
        (display_start...display_end).each do |idx|
          account = non_mutual[idx]
          checkbox = selected.include?(idx) ? '✓' : ' '
          followers_text = format_number(account[:followers_count])
          
          # Highlight current selection
          if idx == current_index
            line = @pastel.inverse(" > [#{checkbox}] #{account[:display_name]} (@#{account[:acct]}) - #{followers_text} followers ")
          else
            color = selected.include?(idx) ? :green : :white
            line = @pastel.decorate("   [#{checkbox}] #{account[:display_name]} (@#{account[:acct]}) - #{followers_text} followers", color)
          end
          
          puts line
        end
        
        puts "\n[↑↓] Navigate • [Space] Toggle • [I]nfo • [U]nfollow Selected • [A]ll • [N]one • [Q]uit"
        
        begin
          system("stty raw -echo")
          key = STDIN.getc
          
          # Handle arrow keys (they send escape sequences)
          if key == "\e"
            key += STDIN.read_nonblock(2) rescue ""
          end
        ensure
          system("stty -raw echo")
        end
        
        case key
        when "\e[A", 'k' # Up arrow or k
          current_index = [0, current_index - 1].max
        when "\e[B", 'j' # Down arrow or j
          current_index = [non_mutual.length - 1, current_index + 1].min
        when ' ' # Space to toggle
          if selected.include?(current_index)
            selected.delete(current_index)
          else
            selected.add(current_index)
          end
        when 'i', 'I'
          show_account_detail(non_mutual[current_index], config)
        when 'u', 'U'
          if selected.any?
            selected_accounts = selected.map { |i| non_mutual[i] }
            if confirm_bulk_unfollow(selected_accounts, config)
              break
            end
          end
        when 'a', 'A'
          selected = Set.new(0...non_mutual.length)
        when 'n', 'N'
          selected.clear
        when 'q', 'Q'
          break
        end
      end
      
    rescue => e
      spinner.error("Failed to fetch data")
      puts "Error: #{e.message}"
      puts "Press any key to continue..."
      
      begin
        system("stty raw -echo")
        STDIN.getc
      ensure
        system("stty -raw echo")
      end
    end
  end

  def show_followback_view
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    spinner = TTY::Spinner.new("[:spinner] Finding accounts to follow back...", format: :dots)
    spinner.auto_spin
    
    begin
      config = @tracker.load_config
      return puts "Please run setup first!" unless config
      
      if @platform == 'mastodon'
        followers = @tracker.fetch_followers(config[:instance], config[:token])
        following = @tracker.fetch_following(config[:instance], config[:token])
      else
        # Bluesky methods don't take parameters - they handle auth internally
        followers = @tracker.fetch_followers
        following = @tracker.fetch_following
      end
      
      return puts "Failed to fetch data" unless followers && following
      
      if @platform == 'mastodon'
        following_ids = following.map { |f| f[:id] }.to_set
        followback_candidates = followers.reject { |f| following_ids.include?(f[:id]) }
      else
        following_ids = following.map { |f| f[:did] }.to_set
        followback_candidates = followers.reject { |f| following_ids.include?(f[:did]) }
      end
      
      spinner.success("Found #{followback_candidates.length} accounts you could follow back")
      
      if followback_candidates.empty?
        puts "\n🎉 You already follow back everyone who follows you!"
        puts "Press any key to continue..."
        
        begin
          system("stty raw -echo")
          STDIN.getc
        ensure
          system("stty -raw echo")
        end
        return
      end
      
      # Interactive navigation
      current_index = 0
      selected = Set.new
      
      loop do
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        
        # Header
        puts TTY::Box.frame(
          title: { top_left: " Follow Back Candidates " },
          width: TTY::Screen.width,
          height: 3
        ) { "#{followback_candidates.length} accounts • #{selected.length} selected • Use ↑↓ to navigate" }
        
        # Account list with navigation - show more accounts based on terminal height
        available_height = TTY::Screen.height - 8 # Leave room for header, instructions, etc.
        display_count = [available_height, 20].min # Show up to 20 accounts or terminal height
        
        display_start = [0, current_index - display_count/2].max
        display_end = [followback_candidates.length, display_start + display_count].min
        
        # Adjust start if we're near the end
        if display_end - display_start < display_count && display_start > 0
          display_start = [0, display_end - display_count].max
        end
        
        (display_start...display_end).each do |idx|
          account = followback_candidates[idx]
          checkbox = selected.include?(idx) ? '✓' : ' '
          followers_text = format_number(account[:followers_count])
          
          # Highlight current selection
          if idx == current_index
            line = @pastel.inverse(" > [#{checkbox}] #{account[:display_name]} (@#{account[:acct]}) - #{followers_text} followers ")
          else
            color = selected.include?(idx) ? :green : :white
            line = @pastel.decorate("   [#{checkbox}] #{account[:display_name]} (@#{account[:acct]}) - #{followers_text} followers", color)
          end
          
          puts line
        end
        
        puts "\n[↑↓] Navigate • [Space] Toggle • [I]nfo • [F]ollow Selected • [A]ll • [N]one • [Q]uit"
        
        begin
          system("stty raw -echo")
          key = STDIN.getc
          
          # Handle arrow keys (they send escape sequences)
          if key == "\e"
            key += STDIN.read_nonblock(2) rescue ""
          end
        ensure
          system("stty -raw echo")
        end
        
        case key
        when "\e[A", 'k' # Up arrow or k
          current_index = [0, current_index - 1].max
        when "\e[B", 'j' # Down arrow or j
          current_index = [followback_candidates.length - 1, current_index + 1].min
        when ' ' # Space to toggle
          if selected.include?(current_index)
            selected.delete(current_index)
          else
            selected.add(current_index)
          end
        when 'i', 'I'
          show_account_detail(followback_candidates[current_index], config)
        when 'f', 'F'
          if selected.any?
            selected_accounts = selected.map { |i| followback_candidates[i] }
            if confirm_bulk_follow(selected_accounts, config)
              break
            end
          end
        when 'a', 'A'
          selected = Set.new(0...followback_candidates.length)
        when 'n', 'N'
          selected.clear
        when 'q', 'Q'
          break
        end
      end
      
    rescue => e
      spinner.error("Failed to fetch data")
      puts "Error: #{e.message}"
      puts "Press any key to continue..."
      
      begin
        system("stty raw -echo")
        STDIN.getc
      ensure
        system("stty -raw echo")
      end
    end
  end

  def show_account_detail(account, config)
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    spinner = TTY::Spinner.new("[:spinner] Fetching account details...", format: :dots)
    spinner.auto_spin
    
    begin
      # Fetch detailed account info
      if @platform == 'mastodon'
        account_details = @tracker.fetch_account_details(config[:instance], config[:token], account[:id])
        recent_posts = @tracker.fetch_account_posts(config[:instance], config[:token], account[:id], 3)
      else
        # Bluesky uses DID instead of ID and different method signature
        account_id = account[:did] || account[:id]
        account_details = @tracker.fetch_account_details(account_id)
        recent_posts = @tracker.fetch_account_posts(account_id, 3)
      end
      
      spinner.success("Account details loaded")
      
      print @cursor.clear_screen
      print @cursor.move_to(0, 0)
      
      if account_details
        # Account header
        if @platform == 'mastodon'
          header_content = "#{account_details[:display_name]} (@#{account_details[:acct]})\n" +
                          "#{account_details[:url]}\n" +
                          "Joined: #{format_date(account_details[:created_at])}"
        else
          header_content = "#{account_details[:display_name]} (@#{account_details[:handle]})\n" +
                          "DID: #{account_details[:did][0..30]}...\n" +
                          "Joined: #{format_date(account_details[:created_at])}"
        end
        
        header_box = TTY::Box.frame(
          title: { top_left: " Account Info " },
          width: TTY::Screen.width,
          height: 5,
          padding: 1
        ) { header_content }
        
        # Stats
        if @platform == 'mastodon'
          stats_content = "Followers: #{format_number(account_details[:followers_count])} | " +
                         "Following: #{format_number(account_details[:following_count])} | " +
                         "Posts: #{format_number(account_details[:statuses_count])}"
        else
          stats_content = "Followers: #{format_number(account_details[:followers_count])} | " +
                         "Following: #{format_number(account_details[:following_count])} | " +
                         "Posts: #{format_number(account_details[:posts_count])}"
        end
        
        stats_box = TTY::Box.frame(
          width: TTY::Screen.width,
          height: 3,
          border: :light
        ) { stats_content }
        
        # Bio
        if @platform == 'mastodon'
          bio_content = account_details[:note] ? strip_html(account_details[:note]) : "No bio available"
        else
          bio_content = account_details[:description] || "No bio available"
        end
        bio_box = TTY::Box.frame(
          title: { top_left: " Bio " },
          width: TTY::Screen.width,
          height: 6,
          padding: 1
        ) { bio_content }
        
        # Recent posts - use more space
        posts_content = if recent_posts && recent_posts.any?
          available_lines = [TTY::Screen.height - 25, 8].max # Adaptive based on terminal height
          posts_to_show = [recent_posts.length, available_lines / 3].max # Roughly 3 lines per post
          
          "Recent Posts (showing #{posts_to_show}/#{recent_posts.length}):\n\n" + 
          recent_posts.first(posts_to_show).map.with_index do |post, idx|
            if @platform == 'mastodon'
              content = strip_html(post[:content])
            else
              content = post[:text]
            end
            
            # Adjust content length based on terminal width
            max_content_length = [TTY::Screen.width - 10, 150].min
            content = content[0..max_content_length] + "..." if content.length > max_content_length
            time = format_date(post[:created_at])
            "#{idx + 1}. #{time}\n   #{content}\n"
          end.join("\n")
        else
          "No recent posts available"
        end
        
        posts_height = [TTY::Screen.height - 20, 8].max # Use remaining space
        posts_box = TTY::Box.frame(
          title: { top_left: " Recent Activity " },
          width: TTY::Screen.width,
          height: posts_height,
          padding: 1
        ) { posts_content }
        
        print header_box + stats_box + bio_box + posts_box
      else
        puts "Failed to load account details"
      end
      
      puts "[F]ollow • [U]nfollow • [O]pen in browser • [B]ack"
      
      loop do
        begin
          system("stty raw -echo")
          key = STDIN.getc
        ensure
          system("stty -raw echo")
        end
        
        case key&.downcase
        when 'f'
          if @platform == 'mastodon'
            if @tracker.follow_account(config[:instance], config[:token], account[:id])
              puts "\n✅ Followed #{account[:display_name]}"
            else
              puts "\n❌ Failed to follow #{account[:display_name]}"
            end
          else
            account_id = account[:did] || account[:id]
            if @tracker.follow_account(account_id)
              puts "\n✅ Followed #{account[:display_name]}"
            else
              puts "\n❌ Failed to follow #{account[:display_name]}"
            end
          end
          sleep(1)
          break
        when 'u'
          if @platform == 'mastodon'
            if @tracker.unfollow_account(config[:instance], config[:token], account[:id])
              puts "\n✅ Unfollowed #{account[:display_name]}"
            else
              puts "\n❌ Failed to unfollow #{account[:display_name]}"
            end
          else
            account_id = account[:did] || account[:id]
            if @tracker.unfollow_account(account_id)
              puts "\n✅ Unfollowed #{account[:display_name]}"
            else
              puts "\n❌ Failed to unfollow #{account[:display_name]}"
            end
          end
          sleep(1)
          break
        when 'o'
          if @platform == 'mastodon' && account_details && account_details[:url]
            system("open '#{account_details[:url]}'") # macOS
            puts "\n🌐 Opened in browser"
            sleep(1)
          elsif @platform == 'bluesky' && account_details
            url = "https://bsky.app/profile/#{account_details[:handle]}"
            system("open '#{url}'") # macOS
            puts "\n🌐 Opened in browser"
            sleep(1)
          end
        when 'b'
          break
        end
      end
      
    rescue => e
      spinner.error("Failed to load account details")
      puts "Error: #{e.message}"
      puts "Press any key to continue..."
      
      begin
        system("stty raw -echo")
        STDIN.getc
      ensure
        system("stty -raw echo")
      end
    end
  end

  def confirm_bulk_follow(selected_accounts, config)
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    puts "About to follow #{selected_accounts.length} accounts:"
    selected_accounts.each do |account|
      if @platform == 'mastodon'
        puts "  • #{account[:display_name]} (@#{account[:acct]})"
      else
        puts "  • #{account[:display_name]} (@#{account[:handle]})"
      end
    end
    
    puts "\nAre you sure you want to follow these accounts? [y/N]"
    
    begin
      system("stty raw -echo")
      response = STDIN.getc
    ensure
      system("stty -raw echo")
    end
    
    if response&.downcase == 'y'
      spinner = TTY::Spinner.new("[:spinner] Following accounts...", format: :dots)
      spinner.auto_spin
      
      followed = 0
      selected_accounts.each do |account|
        if @platform == 'mastodon'
          account_id = account[:id]
          if @tracker.follow_account(config[:instance], config[:token], account_id)
            followed += 1
          end
        else
          account_id = account[:did] || account[:id]
          if @tracker.follow_account(account_id)
            followed += 1
          end
        end
        sleep(1) # Rate limiting
      end
      
      spinner.success("Followed #{followed}/#{selected_accounts.length} accounts")
      puts "Press any key to continue..."
      
      begin
        system("stty raw -echo")
        STDIN.getc
      ensure
        system("stty -raw echo")
      end
      
      true
    else
      false
    end
  end

  def confirm_bulk_unfollow(selected_accounts, config)
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    puts "About to unfollow #{selected_accounts.length} accounts:"
    selected_accounts.each do |account|
      if @platform == 'mastodon'
        puts "  • #{account[:display_name]} (@#{account[:acct]})"
      else
        puts "  • #{account[:display_name]} (@#{account[:handle]})"
      end
    end
    
    puts "\nAre you sure you want to unfollow these accounts? [y/N]"
    
    begin
      system("stty raw -echo")
      response = STDIN.getc
    ensure
      system("stty -raw echo")
    end
    
    if response&.downcase == 'y'
      spinner = TTY::Spinner.new("[:spinner] Unfollowing accounts...", format: :dots)
      spinner.auto_spin
      
      unfollowed = 0
      selected_accounts.each do |account|
        if @platform == 'mastodon'
          account_id = account[:id]
          if @tracker.unfollow_account(config[:instance], config[:token], account_id)
            unfollowed += 1
          end
        else
          account_id = account[:did] || account[:id]
          if @tracker.unfollow_account(account_id)
            unfollowed += 1
          end
        end
        sleep(1) # Rate limiting
      end
      
      spinner.success("Unfollowed #{unfollowed}/#{selected_accounts.length} accounts")
      puts "Press any key to continue..."
      
      begin
        system("stty raw -echo")
        STDIN.getc
      ensure
        system("stty -raw echo")
      end
      
      true
    else
      false
    end
  end

  def show_settings
    print @cursor.clear_screen
    print @cursor.move_to(0, 0)
    
    config = @tracker.load_config
    
    content = if config
      "Current Configuration:\n\n" +
      "Instance: #{config[:instance]}\n" +
      "Token: #{config[:token][0..10]}...\n\n" +
      "[R]econfigure • [B]ack"
    else
      "No configuration found.\n\n[S]etup • [B]ack"
    end
    
    box = TTY::Box.frame(
      title: { top_left: " Settings " },
      width: 60,
      height: 10,
      padding: 1
    ) { content }
    
    puts box
    
    key = nil
    loop do
      begin
        system("stty raw -echo")
        key = STDIN.getc
      ensure
        system("stty -raw echo")
      end
      
      case key&.downcase
      when 'r', 's'
        @tracker.setup
        break
      when 'b'
        break
      end
    end
  end

  def get_current_stats
    config = @tracker.load_config
    return nil unless config
    
    begin
      if @platform == 'mastodon'
        db = SQLite3::Database.new(@tracker.db_path)
        followers_count = db.execute("SELECT COUNT(*) FROM current_followers")[0][0]
        
        # This would require fetching following count - simplified for now
        {
          followers: followers_count,
          following: nil,
          non_mutual: nil
        }
      else
        # Bluesky stats
        stats = @tracker.stats
        {
          followers: stats[:followers],
          following: nil,
          non_mutual: nil
        }
      end
    rescue
      nil
    ensure
      db&.close if @platform == 'mastodon'
    end
  end

  def get_recent_changes(limit = 5)
    begin
      if @platform == 'mastodon'
        db = SQLite3::Database.new(@tracker.db_path)
        db.results_as_hash = true
        db.execute("SELECT * FROM follower_changes ORDER BY timestamp DESC LIMIT ?", [limit])
      else
        @tracker.get_recent_changes(limit)
      end
    rescue
      []
    ensure
      db&.close if @platform == 'mastodon' && db
    end
  end

  def get_last_check_time
    # This would track last check time - simplified for now
    "Never"
  end

  def format_daily_changes
    # This would calculate today's changes - simplified for now
    "+0 followers, -0 unfollowers"
  end

  def format_date(date_string)
    return "Unknown" unless date_string
    Time.parse(date_string).strftime('%b %Y')
  rescue
    "Unknown"
  end

  def format_number(num)
    return "0" unless num
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def strip_html(html)
    return "" unless html
    html.gsub(/<[^>]*>/, '').gsub(/&[^;]+;/, ' ').strip
  end
end