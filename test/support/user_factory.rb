module UserFactory
  def create_user(slack_id:, display_name:, hca_linked: true)
    user = User.create!(
      slack_id: slack_id,
      display_name: display_name,
      email: "#{display_name}@example.test"
    )

    if hca_linked
      user.identities.create!(
        provider: "hack_club",
        uid: "hca-#{slack_id}",
        access_token: "fake-token-#{slack_id}"
      )
    end

    user
  end
end
