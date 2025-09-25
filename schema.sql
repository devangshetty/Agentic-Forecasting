CREATE TABLE IF NOT EXISTS raw_sales (
  order_date DATE NOT NULL,
  sales NUMERIC NOT NULL
);

CREATE TABLE IF NOT EXISTS forecasts (
  id SERIAL PRIMARY KEY,
  forecast_date DATE NOT NULL,
  model TEXT NOT NULL,
  predicted NUMERIC NOT NULL,
  lower_ci NUMERIC,
  upper_ci NUMERIC,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_raw_sales_date ON raw_sales(order_date);
CREATE INDEX IF NOT EXISTS idx_forecasts_date ON forecasts(forecast_date);
