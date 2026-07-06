Slack.configure do |config|
  config.token = ENV["SLACK_BOT_TOKEN"].presence || Rails.application.credentials.dig(:slack, :bot_token)
end
