Rails.application.routes.draw do
  resources :uploads, only: [:new, :create]
  root 'uploads#new'
end
