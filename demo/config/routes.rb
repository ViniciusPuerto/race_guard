Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  post "wallets/:id/charge_naive", to: "wallets#charge_naive"
  post "wallets/:id/charge_safe", to: "wallets#charge_safe"
  post "products/:id/reserve", to: "products#reserve"
  post "jobs/once_charge_run", to: "jobs#once_charge_run"
  post "simulations/:scenario/run", to: "simulations#run"
end
