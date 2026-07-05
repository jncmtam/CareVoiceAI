.PHONY: help setup backend test smoke patient-flow demo-check docker-up docker-down clean

help:
	@echo "CareVoice AI — lệnh nhanh"
	@echo ""
	@echo "  make setup        Cài backend + tạo .env từ .env.example (nếu chưa có)"
	@echo "  make backend      Chạy API local (SQLite, port 8000)"
	@echo "  make test         Pytest toàn bộ backend"
	@echo "  make smoke        Smoke test flow chính (cần API đang chạy)"
	@echo "  make patient-flow Test luồng bệnh nhân (cần API đang chạy)"
	@echo "  make demo-check   Pytest + smoke + patient-flow × 3 lần"
	@echo "  make docker-up    Docker Compose (PostgreSQL + Redis + API)"
	@echo "  make docker-down  Dừng Docker Compose"
	@echo "  make clean        Xoá cache pytest/ruff local"

setup:
	@test -f backend/.env || cp backend/.env.example backend/.env
	cd backend && python3 -m venv .venv && .venv/bin/python -m pip install -q -e ".[dev]"
	@echo "✅ Setup xong. Chỉnh backend/.env nếu cần VNPT live, rồi: make backend"

backend:
	cd backend && ./scripts/start_local.sh

test:
	cd backend && .venv/bin/python -m pytest -q

smoke:
	cd backend && ./scripts/smoke_test_localhost.sh

patient-flow:
	cd backend && ./scripts/patient_flow_test.sh

demo-check:
	./scripts/run_submission_checks.sh

docker-up:
	cd backend && docker compose up --build -d

docker-down:
	cd backend && docker compose down

clean:
	rm -rf backend/.pytest_cache backend/.ruff_cache backend/**/__pycache__