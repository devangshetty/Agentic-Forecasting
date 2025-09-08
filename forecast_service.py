# forecast_service.py
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Optional, List
import pandas as pd
import statsmodels.api as sm
from datetime import timedelta
import json
import os

app = FastAPI(title="ForecastService")

class ArimaRequest(BaseModel):
    csv_path: str
    date_col: str = "Order Date"
    sales_col: str = "Sales"
    periods: int = 30
    freq: str = "D"
    order: Optional[List[int]] = None
    seasonal_order: Optional[List[int]] = None
    fill_na: bool = True
    start_params: Optional[List[float]] = None

def df_from_csv(csv_path: str, date_col: str, sales_col: str, freq: str, fill_na: bool):
    df = pd.read_csv(csv_path, parse_dates=[date_col], dayfirst=False, infer_datetime_format=True)
    ts = df.groupby(date_col)[sales_col].sum().sort_index()
    ts = ts.asfreq(freq)
    if fill_na:
        ts = ts.fillna(0.0)
    return ts

def build_arima_and_forecast(ts: pd.Series, periods: int, order, seasonal_order=None, start_params=None):
    # If seasonal_order provided use SARIMAX; otherwise use ARIMA
    if order is None:
        order = (1, 1, 1)
    fitted = None
    if seasonal_order:
        # Use SARIMAX for seasonal models
        model = sm.tsa.SARIMAX(ts, order=tuple(order), seasonal_order=tuple(seasonal_order),
                               enforce_stationarity=False, enforce_invertibility=False)
        fitted = model.fit()  # no disp
    else:
        # Use ARIMA (new statsmodels ARIMA wrapper)
        model = sm.tsa.ARIMA(ts, order=tuple(order))
        fitted = model.fit()  # no disp
    # Forecast (both result types support get_forecast)
    fc = fitted.get_forecast(steps=periods)
    fc_mean = fc.predicted_mean
    try:
        ci = fc.conf_int(alpha=0.05)
    except Exception:
        # fallback if conf_int not available in some result types
        ci = pd.DataFrame(index=fc_mean.index, data={0: [float("nan")] * len(fc_mean), 1: [float("nan")] * len(fc_mean)})
    return fc_mean, ci, fitted

@app.post("/arima")
def arima(req: ArimaRequest):
    if not os.path.exists(req.csv_path):
        return {"error": f"CSV path not found: {req.csv_path}"}
    try:
        ts = df_from_csv(req.csv_path, req.date_col, req.sales_col, req.freq, req.fill_na)
    except Exception as e:
        return {"error": f"Failed to read CSV: {e}"}
    try:
        fc_mean, ci, model = build_arima_and_forecast(ts, req.periods, req.order, req.seasonal_order, req.start_params)
    except Exception as e:
        return {"error": f"Model fit/forecast failed: {e}"}

    records = []
    for idx in fc_mean.index:
        lower = None
        upper = None
        if isinstance(ci, pd.DataFrame) and idx in ci.index:
            # conf_int returns columns [lower, upper] — but column labels differ by versions; pick first two columns
            try:
                lower = float(ci.loc[idx].iloc[0])
                upper = float(ci.loc[idx].iloc[1])
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

    # model.summary() can be large; return a short string header if available
    try:
        model_summary = str(model.summary())
    except Exception:
        model_summary = ""

    return {"forecast": records, "history_tail": history_tail, "model_summary": model_summary}
