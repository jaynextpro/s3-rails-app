Rails.application.routes.draw do
  resources :uploads, only: [:new, :create, :index]
  delete 'uploads', to: 'uploads#destroy'
  root 'uploads#new'
end
