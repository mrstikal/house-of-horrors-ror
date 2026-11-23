Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"

  get "admin", to: "admin/dashboard#show", as: :admin

  namespace :admin do
    resource :session, only: [ :create, :destroy ], controller: "sessions"
  end
end
