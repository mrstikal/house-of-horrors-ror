module Api
  class AvailabilityController < BaseController
    def show
      response.set_header("Cache-Control", "no-store")
      result = Reservations::Availability.call(room_id: params[:room_id], date: params[:date])

      if result.success?
        render json: {
          room_id: result[:room_id],
          date: result[:date].iso8601,
          slots: result[:slots].map { |slot| serialize_slot(slot) }
        }
      else
        render_error(result[:code], result[:messages])
      end
    end

    private

    def serialize_slot(slot)
      {
        start_hour: slot[:start_hour],
        start_datetime: slot[:start_datetime].utc.iso8601,
        end_datetime: slot[:end_datetime].utc.iso8601,
        label: slot[:label],
        remaining: slot[:remaining],
        nearly_full: slot[:nearly_full]
      }
    end
  end
end
