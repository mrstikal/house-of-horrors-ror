class Room < ApplicationRecord
  has_many :reservations, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: true
  validates :description, presence: true, length: { maximum: 2000 }
  validates :capacity, presence: true, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1,
    less_than_or_equal_to: 2_147_483_647
  }
  validates :image_key, presence: true, inclusion: { in: RoomImages.keys }

  before_validation :strip_name

  private

  def strip_name
    self.name = name.strip if name
  end
end
