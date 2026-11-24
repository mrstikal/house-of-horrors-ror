module Api
  class ReservationsController < BaseController
    def create
      reservation = params[:reservation]
      unless reservation.is_a?(ActionController::Parameters)
        return render_error(:invalid_input, [ "Select a valid room, date and hour." ])
      end

      permitted = reservation.permit(:room_id, :date, :start_hour)
      result = Reservations::Create.call(
        room_id: permitted[:room_id],
        date: permitted[:date],
        start_hour: permitted[:start_hour]
      )

      if result.success?
        record = result[:record]

        render json: {
          reservation: {
            id: record.id,
            room_id: record.room_id,
            start_datetime: record.start_datetime.utc.iso8601,
            end_datetime: record.end_datetime.utc.iso8601
          }
        }, status: :created
      else
        render_error(result[:code], result[:messages])
      end
    end
  end
end
