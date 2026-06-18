Mjml.setup do |config|
  mjml_path = Rails.root.join("node_modules/.bin/mjml")
  config.mjml_binary = mjml_path.to_s if mjml_path.exist?
end
