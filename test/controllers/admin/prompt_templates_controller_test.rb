require "test_helper"

class Admin::PromptTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email_address: "prompt-admin@example.com",
      password: "password123456",
      admin: true,
      totp_enabled: true
    )
    @admin.ensure_totp_secret!

    post session_url, params: {
      email_address: @admin.email_address,
      password: "password123456"
    }
    post mfa_session_url, params: {
      code: ROTP::TOTP.new(@admin.totp_secret).now
    }

    @template = PromptTemplate.create!(
      key: "test_prompt",
      name: "Test Prompt",
      description: "A test prompt",
      system_role: "You are a test assistant",
      instructions: "Do {{thing}} with {{stuff}}",
      model_tier: "default",
      placeholders: [
        { "name" => "thing", "description" => "The thing" },
        { "name" => "stuff", "description" => "The stuff" }
      ]
    )
  end

  test "index shows all prompts" do
    get admin_prompt_templates_url
    assert_response :success
    assert_select "td", text: /Test Prompt/
  end

  test "edit shows prompt form" do
    get edit_admin_prompt_template_url(@template)
    assert_response :success
    assert_select "textarea", minimum: 2
  end

  test "update saves changes and creates version" do
    assert_difference "@template.versions.count", 1 do
      patch admin_prompt_template_url(@template), params: {
        prompt_template: {
          instructions: "Updated instructions for {{thing}}",
          editor_note: "Changed wording"
        }
      }
    end
    assert_redirected_to edit_admin_prompt_template_url(@template)
    @template.reload
    assert_equal "Updated instructions for {{thing}}", @template.instructions
  end

  test "update with no text change does not create version" do
    assert_no_difference "@template.versions.count" do
      patch admin_prompt_template_url(@template), params: {
        prompt_template: {
          name: "Renamed Prompt"
        }
      }
    end
  end

  test "edit loads prompt run examples" do
    PromptRun.create!(
      prompt_template_key: @template.key,
      ai_model: "gpt-5.2",
      messages: [{ "role" => "user", "content" => "test" }],
      response_body: '{"result": "test"}',
      response_format: "json_object"
    )

    get edit_admin_prompt_template_url(@template)
    assert_response :success
    assert_select "[data-tab='examples']"
  end

  test "edit shows empty state when no examples exist" do
    get edit_admin_prompt_template_url(@template)
    assert_response :success
    assert_select "[data-tab='examples']"
  end

  test "diff returns version comparison" do
    @template.update!(instructions: "v2 instructions", editor_note: "v2")
    version = @template.versions.recent.last

    get diff_admin_prompt_template_url(@template, version_id: version.id)
    assert_response :success
  end
end
