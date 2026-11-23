require "test_helper"

class UserTest < ActiveSupport::TestCase
  PASSWORD = "correct horse battery"

  test "hashes the password and authenticates it" do
    user = User.create!(email_address: "admin@example.test", password: PASSWORD, role: "admin")

    refute_equal PASSWORD, user.password_digest
    assert BCrypt::Password.new(user.password_digest).is_password?(PASSWORD)
    assert user.authenticate_password(PASSWORD)
    refute user.authenticate_password("wrong password")
  end

  test "normalizes the email address" do
    user = User.create!(email_address: "  ADMIN@Example.Test  ", password: PASSWORD)

    assert_equal "admin@example.test", user.email_address
  end

  test "requires a unique normalized email address" do
    User.create!(email_address: "admin@example.test", password: PASSWORD)
    duplicate = User.new(email_address: " ADMIN@EXAMPLE.TEST ", password: PASSWORD)

    refute duplicate.valid?
    assert_includes duplicate.errors[:email_address], "has already been taken"
  end

  test "rejects invalid and too-long email addresses" do
    invalid = User.new(email_address: "not-an-email", password: PASSWORD)
    too_long = User.new(email_address: "#{"a" * 250}@example.test", password: PASSWORD)

    refute invalid.valid?
    refute too_long.valid?
    assert invalid.errors[:email_address].any?
    assert too_long.errors[:email_address].any?
  end

  test "defaults to guest and identifies admins" do
    guest = User.create!(email_address: "guest@example.test", password: PASSWORD)
    admin = User.create!(email_address: "admin@example.test", password: PASSWORD, role: "admin")

    assert_equal "guest", guest.role
    refute guest.admin?
    assert admin.admin?
  end

  test "rejects an unknown role" do
    user = User.new(email_address: "owner@example.test", password: PASSWORD, role: "owner")

    refute user.valid?
    assert_includes user.errors[:role], "is not included in the list"
  end

  test "requires at least twelve password characters on create and change" do
    short = User.new(email_address: "short@example.test", password: "elevenchars")
    user = User.create!(email_address: "long@example.test", password: PASSWORD)

    refute short.valid?
    assert_includes short.errors[:password], "is too short (minimum is 12 characters)"

    user.password = "short"
    refute user.valid?
  end

  test "keeps the digest when the password is unchanged" do
    user = User.create!(email_address: "stable@example.test", password: PASSWORD)
    digest = user.password_digest

    user.update!(email_address: "stable-renamed@example.test")

    assert_equal digest, user.reload.password_digest
  end

  test "rejects a password over bcrypt's byte limit" do
    user = User.new(email_address: "long-password@example.test", password: "a" * 73)

    refute user.valid?
    assert user.errors[:password].any?
  end
end
