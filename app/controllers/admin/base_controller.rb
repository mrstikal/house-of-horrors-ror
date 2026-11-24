module Admin
  class BaseController < ApplicationController
    before_action :require_admin, prepend: true
  end
end
