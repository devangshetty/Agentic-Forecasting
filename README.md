# Agentic-Forecasting

A small forecasting repo that combines a Ruby-based baseline with a lightweight Python ARIMA service and a simple LLM-driven agent. Everything is dockerized for easy local runs and now stores data in Postgres.

---

## Repo contents (short)
- `forecast.rb` — Ruby pipeline: cleans CSV, aggregates daily sales, builds lag features, trains a Random Forest (Rumale), saves `output/forecast.csv` and `output/metrics.json`.  
- `forecast_agent.rb` — Ruby agent wrapper that asks an LLM for a single JSON action (whitelisted actions only) and runs predefined safe actions (`train`, `eval`, `set_param`, `increase_trees`, `decrease_trees`, `call_arima`, `save`, `stop`).  
- `call_arima.rb` — Ruby client that POSTs to the Python ARIMA service and writes `output/arima_forecast.csv` (also inserts ARIMA forecasts into Postgres).  
- `forecast_service.py` — FastAPI service exposing ARIMA/SARIMAX forecasts (statsmodels).  
- `compare_forecasts.rb`, `ensemble_forecast.rb`, `feature_importance.rb` — helper scripts for evaluation and simple ensembling.  
- `Dockerfile.ruby`, `Dockerfile.python`, `docker-compose.yml` — Docker setup for services and Postgres.  
- `schema.sql` — DB schema that creates `raw_sales` and `forecasts` tables.  
- `Gemfile`, `requirements.txt` — dependency manifests.  
- `stores_sales_forecasting.pandas.csv` — example cleaned CSV (replace with your data).  
- `output/` — generated outputs (gitignored).

---

## Models used
- **Random Forest (Rumale)** on lag features — default hyperparams: `n_estimators=200`, `max_depth=8`, `lags=14`. (Ruby baseline.)  
- **ARIMA (statsmodels)** served by the Python FastAPI microservice as an alternative/complementary forecast.  
- A simple ensemble script averages RF + ARIMA predictions.

---

## Quick build & run (Docker Compose)

1. Build and start services:
```bash
cd ~/Desktop/Ruby/forecast_project
docker compose build --pull
docker compose up -d
Wait for Postgres to be ready:

bash
Copy code
until docker compose exec -T db pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
Prepare and import the CSV (one-time):

bash
Copy code
# create a simple 2-column CSV the DB can import
python3 - <<'PY'
import pandas as pd
df = pd.read_csv('stores_sales_forecasting.pandas.csv', parse_dates=['Order Date'])
df2 = pd.DataFrame({'order_date': df['Order Date'].dt.strftime('%Y-%m-%d'), 'sales': df['Sales'].astype(float)})
df2.to_csv('raw_sales_for_pg.csv', index=False)
PY

# import into Postgres (repo is mounted at /app)
docker compose exec -T db psql -U postgres -d forecast_db -c "\copy raw_sales(order_date, sales) FROM '/app/raw_sales_for_pg.csv' WITH CSV HEADER DELIMITER ',';"
Run the Ruby forecast (reads DB and writes forecasts to DB):

bash
Copy code
docker compose exec -T ruby_app bash -lc "bundle exec ruby forecast.rb"
Run ARIMA (stores ARIMA forecasts in DB):

bash
Copy code
docker compose exec -T ruby_app bash -lc "bundle exec ruby call_arima.rb"
Verify forecasts:

bash
Copy code
docker compose exec -T db psql -U postgres -d forecast_db -c "SELECT forecast_date, model