module Admin
  class SessionsController < ApplicationController
    RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)

    rate_limit to: 10, within: 3.minutes, only: :create,
      store: RATE_LIMIT_STORE, with: :render_rate_limited, prepend: true

    before_action :require_admin, only: :destroy

    def create
      email_address = session_params[:email_address]
      password = session_params[:password]

      user = if email_address.is_a?(String) && password.is_a?(String)
        User.authenticate_by(email_address: email_address, password: password)
      end

      if user&.admin?
        reset_session
        session[:admin_user_id] = user.id
        session[:admin_expires_at] = 8.hours.from_now.to_i
        redirect_to admin_path, status: :see_other
      else
        render_login_error("Invalid email or password.", :unprocessable_entity)
      end
    end

    def destroy
      reset_session
      redirect_to admin_path, status: :see_other
    end

    private

    def session_params
      value = params[:session]
      return ActionController::Parameters.new unless value.is_a?(ActionController::Parameters)

      value.permit(:email_address, :password)
    end

    def render_rate_limited
      render_login_error("Too many attempts. Try again in a few minutes.", :too_many_requests)
    end

    def render_login_error(message, status)
      @error_message = message
      render "admin/dashboard/show", status: status
    end
  end
end
