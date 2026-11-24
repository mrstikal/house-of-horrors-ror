module Admin
  class DashboardController < ApplicationController
    def show
      redirect_to admin_rooms_path, status: :see_other if current_admin
    end
  end
end
