module Admin
  class RoomImagesController < BaseController
    before_action :set_active_tab
    before_action :load_rooms

    def create
      result = RoomImageUpload.call(params[:image])

      if result[:ok]
        redirect_to admin_rooms_path, status: :see_other,
          notice: "Image uploaded: #{result[:record].filename}. Select it when creating or editing a room."
      else
        @mode = :index
        @room = nil
        flash.now[:alert] = result[:messages].join(" ")
        render "admin/workspace", status: failure_status(result[:code])
      end
    end

    private

    def set_active_tab
      @active_tab = :rooms
    end

    def load_rooms
      @rooms = Room.order(:name, :id)
      @reservation_counts = Reservation.group(:room_id).count
    end

    def failure_status(code)
      code == :storage_unavailable ? :service_unavailable : :unprocessable_entity
    end
  end
end
