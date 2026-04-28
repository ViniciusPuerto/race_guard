DC=docker compose -f $(CURDIR)/docker-compose.yml

.PHONY: up down logs shell db seed simulate-wallet simulate-stock simulate-once

up:
	$(DC) up --build -d

down:
	$(DC) down

logs:
	$(DC) logs -f api sidekiq postgres redis

shell:
	$(DC) exec api bash

db:
	$(DC) exec api bundle exec rails db:prepare

seed:
	$(DC) exec api bundle exec rails db:seed

simulate-wallet:
	$(DC) exec api bundle exec rake demo:wallet_race

simulate-stock:
	$(DC) exec api bundle exec rake demo:stock_race

simulate-once:
	$(DC) exec api bundle exec rake demo:once_run
