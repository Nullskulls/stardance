ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "view_component/test_helpers"

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include UserFactory
  end
end

class ViewComponent::TestCase
  include Rails.application.routes.url_helpers
  include ViewComponent::TestHelpers

  private :test_error_path if method_defined?(:test_error_path)
  private :test_error_url if method_defined?(:test_error_url)
end

module ActionDispatch
  class IntegrationTest
    private

    def sign_in(user)
      get dev_login_path(user.id)
    end
  end
end
