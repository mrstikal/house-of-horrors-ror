module Api
  class BaseController < ActionController::Base
    wrap_parameters false

    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request

    private

    def render_bad_request
      head :bad_request, content_type: "text/plain"
    end

    def render_error(code, messages)
      status = {
        invalid_input: :unprocessable_entity,
        not_found: :not_found,
        slot_full: :conflict,
        busy: :service_unavailable
      }.fetch(code, :unprocessable_entity)

      render json: { error: { code: code, messages: messages } }, status: status
    end
  end
end
