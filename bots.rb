require 'twitter_ebooks'

class TwilightWarmth < Ebooks::Bot
  # This is added to the hour time for testing and simulating
  # different timezones. -6 is for adjusting heroku to CST
  @@hour_adjustment = -6
  # The maximum number of tweets of a user that can be retweeted
  # per hour
  @@max_tweets_per_user_per_hour = 3

  # Configuration here applies to all MyBots
  def configure
    environment = ENV['TWILIGHTWARMTH_ENVIRONMENT']
    if environment == "production"
      self.consumer_key = ENV["TWILIGHTWARMTH_TWITTER_CONSUMER_KEY"]
      self.consumer_secret = ENV["TWILIGHTWARMTH_TWITTER_CONSUMER_SECRET"]
    elsif environment == "testing"
      self.consumer_key = ENV["TWILIGHTWARMTH_TEST_TWITTER_CONSUMER_KEY"]
      self.consumer_secret = ENV["TWILIGHTWARMTH_TEST_TWITTER_CONSUMER_SECRET"]
    else
      raise "Must specify a TWILIGHTWARMTH_ENVIRONMENT"
    end
  end

  def on_startup
    @current_hour = self.get_current_hour
    @user_favorites_this_hour = {}
    puts "Started in hour " + @current_hour.to_s + "."
    self.unfollow_unfollowers

    # Unfollow people who unfollowed us
    scheduler.every '15m' do
      self.unfollow_unfollowers
    end

    self.favorite_posts

    # Core code
    scheduler.every '1m' do
      self.favorite_posts
    end
  end

  def on_follow(user)
    puts "Followed by " + user.screen_name + "."
    self.follow(user.screen_name)
    puts "Following " + user.screen_name + "."
    self.unfollow_unfollowers
  end

  def get_current_hour
    hour = Time.new.hour + @@hour_adjustment
    # If our hour adjustment puts it over/under a regular day, wrap it around
    if hour > 24
      hour = hour - 24
    elsif hour < 0
      hour = hour + 24
    end
    hour
  end

  def favorite_posts
    hour = self.get_current_hour
    start_seconds = Time.now

    # Clear our settings in @user_favorites_this_hour if @current_hour has changed
    if hour != @current_hour
      @current_hour = hour
      @user_favorites_this_hour = {}
    end

    attempts = 0

    if hour >= 3 and hour <= 5
      puts "In the Twilight Zone. Favoriting..."
      no_favorite_yet = true
      while no_favorite_yet do
        # Only try to favorite something 5 times. If we fail,
        # give up.
        if attempts == 3
          puts "Tried 3 times this loop, giving up."
          break
        end
        attempts += 1

        followers = []
        self.get_followers.each do |follower|
          followers.push(follower)
        end
        random_user = followers.sample

        favorites = @user_favorites_this_hour[random_user.id.to_s]
        if !favorites.nil?
          # If we've already favorited this person's tweets this hour,
          # skip to another user and try again
          if favorites == @@max_tweets_per_user_per_hour
            puts "Favorited " + random_user.screen_name + " too many times already."
            next
          end
        end

        timeline = self.twitter.user_timeline(random_user,
          {
            exclude_replies: true,
            include_rts: false,
            count: 100
          }
        )
        begin
          tweets = []
          timeline.each do |tweet|
            tweets.push(tweet)
          end
          tweet = tweets.sample
          puts "Trying to favorite " + tweet.text
          self.twitter.favorite(tweet)
        rescue Twitter::Error::AlreadyFavorited
          # Already favorited? Try another one
          puts "Already favorited this one."
          next
        end

        # success
        no_favorite_yet = false
        if not @user_favorites_this_hour.key? random_user.id.to_s
          @user_favorites_this_hour[random_user.id.to_s] = 0
        end
        @user_favorites_this_hour[random_user.id.to_s] += 1
      end
    end
  end

  # Custom non-twitter_ebooks methods
  def seconds_since(future, past)
    future - past
  end

  def get_followers
    self.twitter.followers
  end

  def get_following
    self.twitter.following
  end

  # Get all users that we are following
  # but aren't following us so we can
  # unfollow them for privacy
  def diff_followers_to_following
    follower_names = []
    self.get_followers.each do |user|
      follower_names << user.screen_name
    end
    following_names = []
    self.get_following.each do |user|
      following_names << user.screen_name
    end
    not_followed_names = []
    following_names.each do |following|
      if !follower_names.include? following
        not_followed_names << following
      end
    end
    not_followed_names
  end

  def unfollow_unfollowers
    unfollows = self.diff_followers_to_following
    if unfollows.length > 0
      puts "No longer followed by these users: " + unfollows.to_s
      puts "Now unfollowing."
      unfollows.each do |unfollow|
        self.twitter.unfollow(unfollow)
      end
    end
  end
end

## Kickoff
env = ENV['TWILIGHTWARMTH_ENVIRONMENT']

if env == "production"
  TwilightWarmth.new("twilightwarmth") do |bot|
    # Token connecting the app to this account
    bot.access_token = ENV["TWILIGHTWARMTH_TWITTER_OAUTH_TOKEN"]
    # Secret connecting the app to this account
    bot.access_token_secret = ENV["TWILIGHTWARMTH_TWITTER_OAUTH_TOKEN_SECRET"]
        puts "Initializing in production mode..."
  end
elsif env == "testing"
  TwilightWarmth.new("twilightwarmthtest") do |bot|
    # Token connecting the app to this account
    bot.access_token = ENV["TWILIGHTWARMTH_TEST_TWITTER_OAUTH_TOKEN"]
    # Secret connecting the app to this account
    bot.access_token_secret = ENV["TWILIGHTWARMTH_TEST_TWITTER_OAUTH_TOKEN_SECRET"]
        puts "Initializing in staging mode..."
  end
else
  raise "Must specify a TWILIGHTWARMTH_ENVIRONMENT"
end
