module Admin
  class ReservationsController < BaseController
    INVALID_FILTER_MESSAGE = "Select a valid room and UTC date filter."

    before_action :set_active_tab
    before_action :load_rooms, only: :index
    before_action :set_reservation, only: :show

    def index
      @mode = :index
      room_raw = filter_value(:room_id)
      date_raw = filter_value(:date)
      @submitted_room_id = scalar_value(room_raw)
      @submitted_date = scalar_value(date_raw)
      room_id = room_raw.nil? ? nil : BookingSlots.parse_id(room_raw)
      date = date_raw.nil? ? nil : BookingSlots.parse_date(date_raw)
      @submitted_room_id = room_id.to_s if room_id

      if (room_raw && !room_id) || (date_raw && !date)
        @invalid_filters = true
        @reservations = []
        flash.now[:alert] = INVALID_FILTER_MESSAGE
        return render_workspace(status: :unprocessable_entity)
      end

      @invalid_filters = false
      @reservations = filtered_reservations(room_id, date)
      render_workspace
    end

    def show
      @mode = :show
      render_workspace
    end

    private

    def set_active_tab
      @active_tab = :reservations
    end

    def load_rooms
      @rooms = Room.order(:name, :id)
    end

    def set_reservation
      @reservation = Reservation.includes(:room).find_by(id: params[:id])
      head :not_found unless @reservation
    end

    def filter_value(key)
      value = params[key]
      return nil if value.nil?
      return nil if value.is_a?(String) && value.blank?

      value
    end

    def scalar_value(value)
      value.is_a?(String) || value.is_a?(Integer) ? value.to_s : nil
    end

    def filtered_reservations(room_id, date)
      scope = Reservation.includes(:room).order(:start_datetime, :id)
      scope = scope.where(room_id: room_id) if room_id

      if date
        day_start = Time.utc(date.year, date.month, date.day)
        scope = scope.where(start_datetime: day_start...(day_start + 1.day))
      end

      scope
    end

    def render_workspace(status: :ok)
      render "admin/workspace", status: status
    end
  end
end
