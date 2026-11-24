Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"

  get "admin", to: "admin/dashboard#show", as: :admin

  get "room_photos/:id", to: "room_photos#show", as: :room_photo

  namespace :api, defaults: { format: :json } do
    get "availability", to: "availability#show", as: :availability
    resources :reservations, only: :create
  end

  namespace :admin do
    resource :session, only: [ :create, :destroy ], controller: "sessions"
    resources :rooms
    resources :room_images, only: :create
    resources :reservations
  end
end
