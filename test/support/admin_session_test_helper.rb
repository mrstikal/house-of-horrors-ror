module AdminSessionTestHelper
  extend ActiveSupport::Concern

  included do
    setup { Admin::SessionsController::RATE_LIMIT_STORE.clear }
    teardown { Admin::SessionsController::RATE_LIMIT_STORE.clear }
  end
end
