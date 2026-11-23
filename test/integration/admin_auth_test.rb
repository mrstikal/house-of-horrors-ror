require "test_helper"
require_relative "../support/admin_session_test_helper"

class AdminAuthTest < ActionDispatch::IntegrationTest
  include AdminSessionTestHelper

  PASSWORD = "correct horse battery"

  setup do
    @admin = User.create!(email_address: "admin@example.test", password: PASSWORD, role: "admin")
    @guest = User.create!(email_address: "guest@example.test", password: PASSWORD, role: "guest")
  end

  test "renders the login form and shared navigation without the homepage header" do
    get admin_path

    assert_response :success
    assert_select "form[action=?][method=?]", admin_session_path, "post" do
      assert_select "input[name=?]", "session[email_address]"
      assert_select "input[name=?][type=?]", "session[password]", "password"
    end
    assert_select "nav a", text: "Homepage"
    assert_select "nav a", text: "Admin"
    assert_select "header.home-header", count: 0
    assert_no_match(/house_of_horrors\/house\.jpg/, response.body)
  end

  test "rejects a guest login with a generic error" do
    sign_in(@guest)

    assert_response :unprocessable_entity
    assert_includes response.body, "Invalid email or password."
    assert_empty css_select("input[name='session[password]']").first["value"].to_s

    get admin_path
    assert_signed_out
  end

  test "rejects a wrong password with a generic error" do
    sign_in(@admin, password: "wrong password")

    assert_response :unprocessable_entity
    assert_includes response.body, "Invalid email or password."
  end

  test "signs in an admin with a normalized email and shows the dashboard" do
    sign_in(@admin, email_address: " ADMIN@Example.Test ")

    assert_response :see_other
    assert_equal admin_path, URI.parse(response.location).path

    get admin_path
    assert_response :success
    assert_includes response.body, @admin.email_address
    assert_select "form[action=?] input[name=?][value=?]", admin_session_path, "_method", "delete"
    assert_select "form[action=?] button", admin_session_path, text: "Log out"
  end

  test "returns 403 for a logout without an admin session" do
    delete admin_session_path

    assert_response :forbidden
  end

  test "logs out and denies a second logout" do
    sign_in(@admin)
    assert_response :see_other

    delete admin_session_path
    assert_response :see_other
    assert_equal admin_path, URI.parse(response.location).path

    delete admin_session_path
    assert_response :forbidden

    get admin_path
    assert_signed_out
  end

  test "denies a protected action after the admin role is removed" do
    sign_in(@admin)
    @admin.update!(role: "guest")

    delete admin_session_path
    assert_response :forbidden

    get admin_path
    assert_signed_out
  end

  test "denies a protected action after eight hours" do
    sign_in(@admin)
    assert_response :see_other

    travel 8.hours + 1.second do
      delete admin_session_path
      assert_response :forbidden

      get admin_path
      assert_signed_out
    end
  end

  test "rate limits login attempts after ten tries" do
    10.times do
      sign_in(@admin, password: "wrong password")
      assert_response :unprocessable_entity
    end

    sign_in(@admin, password: "wrong password")

    assert_response :too_many_requests
    assert_includes response.body, "Too many attempts. Try again in a few minutes."
    assert_select "form[action=?]", admin_session_path
  end

  test "rejects a login without a CSRF token when forgery protection is enabled" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      get admin_path
      assert_response :success
      token = css_select("input[name='authenticity_token']").first&.[]("value")
      assert token.present?

      sign_in(@admin)
      assert_response :unprocessable_entity

      get admin_path
      assert_signed_out
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  test "counts CSRF-rejected login attempts toward the rate limit" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      10.times do
        sign_in(@admin)
        assert_response :unprocessable_entity
      end

      sign_in(@admin)
      assert_response :too_many_requests
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end

  private

  def sign_in(user, email_address: user.email_address, password: PASSWORD)
    post admin_session_path, params: { session: { email_address: email_address, password: password } }
  end

  def assert_signed_out
    assert_select "input[name=?]", "session[email_address]"
    assert_select "form[action=?] input[name=?][value=?]", admin_session_path, "_method", "delete", count: 0
  end
end
