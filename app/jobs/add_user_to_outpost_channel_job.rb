class AddUserToOutpostChannelJob < ApplicationJob
  queue_as :latency_5m

  # #outpost — https://hackclub.enterprise.slack.com/archives/C0B04RP43TQ
  OUTPOST_CHANNEL_ID = "C0B04RP43TQ".freeze

  def perform(user_id)
    return if Rails.env.development?

    user = User.find_by(id: user_id)
    return if user&.slack_id.blank?

    client = Slack::Web::Client.new(token: Rails.application.credentials.dig(:slack, :bot_token))
    client.conversations_invite(channel: OUTPOST_CHANNEL_ID, users: user.slack_id)
  rescue Slack::Web::Api::Errors::SlackError => e
    # The user is already a member — nothing to do.
    return if e.message == "already_in_channel"

    Rails.logger.error("Failed to add user #{user_id} to #outpost: #{e.message}")
  end
end
