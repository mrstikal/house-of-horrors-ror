class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_admin

  private

  def current_admin
    return @current_admin if defined?(@current_admin)

    @current_admin = begin
      user_id = session[:admin_user_id]
      expires_at = session[:admin_expires_at]

      if user_id && expires_at.is_a?(Integer) && Time.current.to_i < expires_at
        user = User.find_by(id: user_id)
        user if user&.admin?
      end
    end
  end

  def require_admin
    head :forbidden unless current_admin
  end
end
