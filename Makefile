up:
	docker compose up --build -d

down:
	docker compose down

clean:
	docker compose down -v --rmi all --remove-orphans
