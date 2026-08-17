Lockbox.master_key =
  if Rails.env.test?
    "0" * 64
  else
    ENV["LOCKBOX_MASTER_KEY"].presence || Rails.application.credentials.dig(:lockbox, :master_key)
  end
