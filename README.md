# Agentic-Forecasting

A small forecasting repo that combines a Ruby-based baseline with a lightweight Python ARIMA service and a simple LLM-driven agent. Everything is dockerized for easy local runs.

---

## Repo contents (short)
- `forecast.rb` — Ruby pipeline: cleans CSV, aggregates daily sales, builds lag features, trains a Random Forest (Rumale), saves `output/forecast.csv` and `output/metrics.json`.  
- `forecast_agent.rb` — Ruby agent wrapper that asks an LLM for a single JSON action (whitelisted actions only) and runs predefined safe actions (train, eval, set_param, increase_trees, decrease_trees, call_arima, save, stop).  
- `call_arima.rb` — Ruby client that POSTs to the Python ARIMA service and writes `output/arima_forecast.csv`.  
- `forecast_service.py` — FastAPI service exposing ARIMA/SARIMAX forecasts (statsmodels).  
- `compare_forecasts.rb`, `ensemble_forecast.rb`, `feature_importance.rb` — helper scripts for evaluation and simple ensembling.  
- `Dockerfile.ruby`, `Dockerfile.python`, `docker-compose.yml` — Docker setup for both services.  
- `Gemfile`, `requirements.txt` — dependency manifests.  
- `stores_sales_forecasting.pandas.csv` — example cleaned CSV (replace with your data).  
- `output/` — generated outputs (gitignored).

---

## Models used
- **Random Forest (Rumale)** on lag features — default hyperparams: `n_estimators=200`, `max_depth=8`, `lags=14`. This is the main Ruby baseline.  
- **ARIMA (statsmodels)** served by the Python FastAPI microservice as an alternative/complementary forecast.  
- A simple ensemble script averages RF + ARIMA predictions.

---

## Run locally (minimal)
1. Place your CSV in the project folder. If available, use the cleaned CSV (`stores_sales_forecasting.pandas.csv`) or set `DATA_PATH` when running.  
2. Install Ruby dependencies:
```bash
gem install bundler
bundle install
Set up Python virtualenv and install Python deps:

bash
Copy code
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
Start the ARIMA service (terminal A):

bash
Copy code
source .venv/bin/activate
uvicorn forecast_service:app --host 127.0.0.1 --port 8000
Run the Ruby forecast (terminal B):

bash
Copy code
bundle exec ruby forecast.rb
# or point to a cleaned CSV:
DATA_PATH=stores_sales_forecasting.pandas.csv bundle exec ruby forecast.rb
Request ARIMA from Ruby:

bash
Copy code
bundle exec ruby call_arima.rb
Compare / ensemble:

bash
Copy code
bundle exec ruby compare_forecasts.rb
bundle exec ruby ensemble_forecast.rb
Results are written to output/.

Run with Docker 
Copy .env.example → .env and edit if needed (do not put secrets in git).

Build and start services:

bash
Copy code
docker-compose build
docker-compose up -d
Run commands inside the Ruby container:

bash
Copy code
docker-compose exec ruby_app bundle exec ruby forecast.rb
docker-compose exec ruby_app bundle exec ruby call_arima.rb
View logs:

bash
Copy code
docker-compose logs -f forecast_service
docker-compose logs -f ruby_app
Files in output/ are available on the host because the repo is mounted into the containers.

Agent (brief)
The agent sends a short prompt to an LLM and expects a single JSON action in return.

Only whitelisted actions are supported and the wrapper validates responses before executing anything.

To use the agent with OpenAI, set OPENAI_API_KEY in the environment (or in .env for Docker).

