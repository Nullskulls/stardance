require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(slack_id: "U_PROJECT_OWNER", display_name: "owner", email: "owner@example.test")
    @owner.identities.create!(provider: "hack_club", uid: "hca_project_owner")
    @viewer = User.create!(slack_id: "U_PROJECT_VIEWER", display_name: "viewer", email: "viewer@example.test")
    @project = Project.create!(title: "Forest Odyssey", description: "Explore a magical forest")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "owner sees inline project editing form on show" do
    sign_in @owner

    get project_path(@project, editing: true)

    assert_response :success
    assert_select "form.project-show--editing[action=?]", project_path(@project)
    assert_select "input[name='project[title]'][value=?]", "Forest Odyssey"
    assert_select "textarea[name='project[description]']", text: "Explore a magical forest"
    assert_select "input[name='inline_project_show'][value='1']", 1
  end

  test "owner can update project from inline show form" do
    sign_in @owner

    patch project_path(@project), params: {
      inline_project_show: "1",
      project: {
        title: "Forest Odyssey DX",
        description: "A brighter forest",
        demo_url: "",
        repo_url: "",
        readme_url: "",
        ai_declaration: "Used AI to rubber-duck CSS."
      }
    }

    assert_redirected_to project_path(@project)
    @project.reload
    assert_equal "Forest Odyssey DX", @project.title
    assert_equal "A brighter forest", @project.description
    assert_equal "Used AI to rubber-duck CSS.", @project.ai_declaration
  end

  test "non-owner sees read-only project shell" do
    sign_in @viewer

    get project_path(@project)

    assert_response :success
    assert_select "form.project-show--editing", 0
    assert_select ".project-show__title", text: "Forest Odyssey"
  end

  test "owner of empty project sees onboarding and github card" do
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding"
    assert_select "#project-show-onboarding-title", text: "Welcome to your new project!"
    assert_select "a[href='#{guide_path(:github_repository)}']", text: /Create your GitHub repository/
  end

  test "owner without hackatime identity sees hackatime setup card" do
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding form[action='/auth/hackatime'][method='post']"
    assert_select ".project-show__onboarding", text: /Set up hour tracking with Hackatime/
  end

  test "owner with hackatime identity does not see hackatime setup card" do
    User::Identity.insert_all([
      {
        user_id: @owner.id,
        provider: "hackatime",
        uid: "hackatime-owner",
        created_at: Time.current,
        updated_at: Time.current
      }
    ])
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding"
    assert_select ".project-show__onboarding", { text: /Set up hour tracking with Hackatime/, count: 0 }
    assert_select ".project-show__onboarding form[action='/auth/hackatime']", 0
  end

  test "project with attached mission shows gold mission onboarding card" do
    mission = Mission.create!(
      slug: "rusty-frontend",
      name: "Rusty Frontend",
      description: "Learn the basics of Rust while building frontend for a simple website."
    )
    @project.mission_attachments.create!(mission: mission)
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding-card--mission[href='#{mission_path(mission.slug)}']", text: /Rusty Frontend/
  end

  test "non-owner does not see owner onboarding" do
    sign_in @viewer

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding", 0
  end

  test "project with existing post does not show onboarding block" do
    fire_event = Post::FireEvent.create!(body: "This project is already active.")
    Post.create!(project: @project, user: @owner, postable: fire_event)
    sign_in @owner

    get project_path(@project)

    assert_response :success
    assert_select ".project-show__onboarding", 0
  end

  test "non-owner cannot update project" do
    sign_in @viewer

    patch project_path(@project), params: {
      inline_project_show: "1",
      project: { title: "Not yours" }
    }

    assert_response :forbidden
    assert_equal "Forest Odyssey", @project.reload.title
  end
end
