module Admin
  class BaseController < ApplicationController
    layout false

    before_action :require_admin, prepend: true
  end
end
