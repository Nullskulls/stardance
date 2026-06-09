require "test_helper"

class OutpostEmailTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { @user = users(:one) }

  test "logged-in visitor to /outpost gets the email exactly once" do
    sign_in @user

    assert_enqueued_email_with UserMailer, :outpost, args: [ @user ] do
      get "/outpost"
    end
    assert_not_nil @user.reload.outpost_email_sent_at

    # A second visit must not enqueue another email.
    assert_no_enqueued_emails { get "/outpost" }
  end

  test "logged-out /outpost visit defers the email until sign in" do
    assert_no_enqueued_emails { get "/outpost" }
    assert_response :success
    assert_nil @user.reload.outpost_email_sent_at

    sign_in @user

    # First request once signed in flushes the pending email, exactly once.
    assert_enqueued_email_with UserMailer, :outpost, args: [ @user ] do
      get root_path
    end
    assert_not_nil @user.reload.outpost_email_sent_at

    assert_no_enqueued_emails { get root_path }
  end
end
