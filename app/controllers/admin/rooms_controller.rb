module Admin
  class RoomsController < BaseController
    before_action :set_active_tab
    before_action :load_rooms
    before_action :set_room, only: [ :show, :edit, :update, :destroy ]

    def index
      @mode = :index
      @room = nil
      render_workspace
    end

    def show
      @mode = :show
      render_workspace
    end

    def new
      @mode = :new
      @room = Room.new
      render_workspace
    end

    def create
      @mode = :new
      result = Rooms::Write.call(action: :create, attributes: room_params)

      if result[:ok]
        redirect_to admin_room_path(result[:record]), status: :see_other,
          notice: "Room was successfully created."
      else
        attributes = room_params
        @room = Room.new(attributes.except(:capacity))
        @submitted_capacity = attributes[:capacity]
        render_failure(result, :new)
      end
    end

    def edit
      @mode = :edit
      render_workspace
    end

    def update
      @mode = :edit
      result = Rooms::Write.call(action: :update, id: @room.id, attributes: room_params)

      if result[:ok]
        redirect_to admin_room_path(result[:record]), status: :see_other,
          notice: "Room was successfully updated."
      else
        attributes = room_params
        @room.assign_attributes(attributes.except(:capacity))
        @submitted_capacity = attributes[:capacity]
        render_failure(result, :edit)
      end
    end

    def destroy
      @mode = :show
      result = Rooms::Write.call(action: :destroy, id: @room.id)

      if result[:ok]
        redirect_to admin_rooms_path, status: :see_other,
          notice: "Room was successfully deleted."
      else
        render_failure(result, :show)
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

    def set_room
      @room = Room.find_by(id: params[:id])
      head :not_found unless @room
    end

    def room_params
      params.require(:room).permit(:name, :description, :capacity, :image_key)
    end

    def render_workspace(status: :ok)
      render "admin/workspace", status: status
    end

    def render_failure(result, template)
      flash.now[:alert] = result[:messages].join(" ")
      @mode = template
      render_workspace(status: failure_status(result[:code]))
    end

    def failure_status(code)
      {
        invalid_input: :unprocessable_entity,
        not_found: :not_found,
        capacity_below_bookings: :conflict,
        room_has_reservations: :conflict,
        busy: :service_unavailable
      }.fetch(code, :unprocessable_entity)
    end
  end
end
