# Forecast Project

This repo contains a Ruby forecasting pipeline (Daru + Rumale) and a Python FastAPI microservice that produces ARIMA forecasts. The two are integrated and Dockerized.

## Quick start (local dev)

1. Copy environment variables:
   ```bash
   cp .env.example .env
   # edit .env to add OPENAI_API_KEY if needed
