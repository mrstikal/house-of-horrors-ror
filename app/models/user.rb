class User < ApplicationRecord
  ROLES = %w[guest admin].freeze

  attribute :role, :string, default: "guest"

  has_secure_password

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :email_address, presence: true, length: { maximum: 254 },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email_address, uniqueness: true
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: 12 }, allow_nil: true

  def admin?
    role == "admin"
  end
end
