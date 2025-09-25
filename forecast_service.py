# forecast_service.py
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Optional, List
import pandas as pd
import statsmodels.api as sm
import os
import sqlalchemy
from sqlalchemy import create_engine
import json

app = FastAPI(title="ForecastService")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+psycopg2://postgres:postgres_password@db:5432/forecast_db")
engine = create_engine(DATABASE_URL, echo=False)

class ArimaRequest(BaseModel):
    csv_path: Optional[str] = None
    date_col: str = "Order Date"
    sales_col: str = "Sales"
    periods: int = 30
    freq: str = "D"
    order: Optional[List[int]] = None
    seasonal_order: Optional[List[int]] = None
    fill_na: bool = True
    use_db: bool = False

def df_from_csv(csv_path: str, date_col: str, sales_col: str, freq: str, fill_na: bool):
    df = pd.read_csv(csv_path, parse_dates=[date_col], dayfirst=False, infer_datetime_format=True)
    ts = df.groupby(date_col)[sales_col].sum().sort_index()
    ts = ts.asfreq(freq)
    if fill_na:
        ts = ts.fillna(0.0)
    return ts

def df_from_db(freq: str, fill_na: bool):
    q = "SELECT order_date::date AS date, SUM(sales)::float AS sales FROM raw_sales GROUP BY order_date ORDER BY order_date;"
    df = pd.read_sql_query(q, engine, parse_dates=['date'])
    if df.empty:
        raise RuntimeError("No rows returned from raw_sales")
    df = df.set_index('date').asfreq(freq)
    if fill_na:
        df = df.fillna(0.0)
    return df['sales']

def build_arima_and_forecast(ts: pd.Series, periods: int, order, seasonal_order=None, start_params=None):
    if order is None:
        order = (1, 1, 1)
    if seasonal_order:
        model = sm.tsa.SARIMAX(ts, order=tuple(order), seasonal_order=tuple(seasonal_order),
                               enforce_stationarity=False, enforce_invertibility=False)
        fitted = model.fit()
    else:
        model = sm.tsa.ARIMA(ts, order=tuple(order))
        fitted = model.fit()
    fc = fitted.get_forecast(steps=periods)
    fc_mean = fc.predicted_mean
    try:
        ci = fc.conf_int(alpha=0.05)
    except Exception:
        ci = pd.DataFrame(index=fc_mean.index, data={0: [None] * len(fc_mean), 1: [None] * len(fc_mean)})
    return fc_mean, ci, fitted

@app.post("/arima")
def arima(req: ArimaRequest):
    # Choose data source
    try:
        if req.use_db:
            ts = df_from_db(req.freq, req.fill_na)
        else:
            if not req.csv_path:
                return {"error": "csv_path not provided and use_db is False"}
            ts = df_from_csv(req.csv_path, req.date_col, req.sales_col, req.freq, req.fill_na)
    except Exception as e:
        return {"error": f"Failed to load data: {e}"}

    try:
        fc_mean, ci, model = build_arima_and_forecast(ts, req.periods, req.order, req.seasonal_order, None)
    except Exception as e:
        return {"error": f"Model fit/forecast failed: {e}"}

    records = []
    for idx in fc_mean.index:
        lower = None
        upper = None
        try:
            if idx in ci.index:
                lower = float(ci.loc[idx].iloc[0]) if not pd.isna(ci.loc[idx].iloc[0]) else None
                upper = float(ci.loc[idx].iloc[1]) if not pd.isna(ci.loc[idx].iloc[1]) else None
        except Exception:
            lower = None
            upper = None
        records.append({
            "date": pd.Timestamp(idx).strftime("%Y-%m-%d"),
            "mean": float(fc_mean.loc[idx]),
            "lower_ci": lower,
            "upper_ci": upper
        })

    history_tail = []
    for idx, val in ts.tail(7).items():
        history_tail.append({"date": pd.Timestamp(idx).strftime("%Y-%m-%d"), "value": float(val)})

    try:
        model_summary = str(model.summary())
    except Exception:
        model_summary = ""

    return {"forecast": records, "history_tail": history_tail, "model_summary": model_summary}
