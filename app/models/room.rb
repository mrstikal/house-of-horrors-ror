class Room < ApplicationRecord
  belongs_to :image_blob, class_name: "ActiveStorage::Blob", optional: true

  has_many :reservations, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: true
  validates :description, presence: true, length: { maximum: 2000 }
  validates :capacity, presence: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 2_147_483_647
  }
  validates :image_key, inclusion: { in: RoomImages.keys }, allow_nil: true
  validate :exactly_one_image_reference
  validate :image_blob_is_upload

  before_validation :normalize_image_key, :strip_name

  private

  def normalize_image_key
    self.image_key = nil if image_key.blank?
  end

  def exactly_one_image_reference
    return if image_key.present? ^ image_blob_id.present?

    errors.add(:base, "Select exactly one room image.")
  end

  def image_blob_is_upload
    return if image_blob_id.blank?

    unless RoomImages.uploads.where(id: image_blob_id).exists?
      errors.add(:image_blob, "must be a stored PNG or JPEG upload")
    end
  end

  def strip_name
    self.name = name.strip if name
  end
end
