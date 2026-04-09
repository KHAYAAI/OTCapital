"""
Kronos FastAPI microservice for OTCapital.

Exposes two endpoints:
  GET  /health    — liveness check, returns model status
  POST /forecast  — run Kronos price forecast on OHLCV data

Configured via environment variables:
  KRONOS_MODEL   — model size: "mini" (default), "small", or "large"
  HF_HOME        — HuggingFace cache directory (default: /models)
  PORT           — port to listen on (default: 5000)

Usage:
  uvicorn main:app --host 0.0.0.0 --port 5000
"""

import os
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator

from model import KronosModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Model singleton (loaded once at startup)
# ---------------------------------------------------------------------------
MODEL_SIZE = os.environ.get("KRONOS_MODEL", "mini").lower()
_model: KronosModel | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _model
    logger.info("Starting Kronos service with model size: %s", MODEL_SIZE)
    _model = KronosModel(model_size=MODEL_SIZE)
    # Pre-load model weights at startup so first request is fast
    try:
        _model._load()
        logger.info("Kronos model pre-loaded successfully")
    except Exception as e:
        logger.warning("Could not pre-load model (will retry on first request): %s", e)
    yield
    logger.info("Kronos service shutting down")


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Kronos Forecasting Service",
    description="OTCapital integration for the Kronos financial candlestick foundation model",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # The Rails app is on the same Docker network; tighten if exposed
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------
class OHLCVCandle(BaseModel):
    date: str                            # "YYYY-MM-DD"
    open: float = Field(gt=0)
    high: float = Field(gt=0)
    low: float  = Field(gt=0)
    close: float = Field(gt=0)
    volume: float = Field(ge=0)

    @field_validator("date")
    @classmethod
    def validate_date_format(cls, v: str) -> str:
        try:
            datetime.strptime(v, "%Y-%m-%d")
        except ValueError:
            raise ValueError("date must be in YYYY-MM-DD format")
        return v


class ForecastRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=20)
    ohlcv: list[OHLCVCandle] = Field(min_length=30)
    horizon: int = Field(default=7, ge=1, le=30)
    model_size: str = Field(default="mini")

    @field_validator("model_size")
    @classmethod
    def validate_model_size(cls, v: str) -> str:
        allowed = {"mini", "small", "large"}
        if v.lower() not in allowed:
            raise ValueError(f"model_size must be one of: {allowed}")
        return v.lower()


class PredictionItem(BaseModel):
    date: str
    predicted_close: float
    confidence_low: float
    confidence_high: float


class ForecastResponse(BaseModel):
    symbol: str
    generated_at: str
    model: str
    horizon: int
    predictions: list[PredictionItem]


class HealthResponse(BaseModel):
    status: str
    model: str
    model_loaded: bool


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------
@app.get("/health", response_model=HealthResponse)
async def health():
    """Liveness check. Returns model name and whether weights are loaded."""
    loaded = _model is not None and _model._predictor is not None
    return HealthResponse(
        status="ok",
        model=f"kronos-{MODEL_SIZE}",
        model_loaded=loaded,
    )


@app.post("/forecast", response_model=ForecastResponse)
async def forecast(request: ForecastRequest):
    """
    Run Kronos price forecast on OHLCV candlestick data.

    The model used is determined by KRONOS_MODEL env var at startup.
    The request's model_size field is accepted for documentation purposes
    but the service always uses the pre-loaded model.
    """
    if _model is None:
        raise HTTPException(status_code=503, detail="Model not yet initialized")

    ohlcv_dicts = [c.model_dump() for c in request.ohlcv]

    try:
        raw_predictions = _model.forecast(
            ohlcv_data=ohlcv_dicts,
            horizon=request.horizon,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.exception("Kronos forecast failed for symbol %s", request.symbol)
        raise HTTPException(status_code=500, detail=f"Forecast error: {str(e)}")

    predictions = [
        PredictionItem(
            date=p.date,
            predicted_close=p.predicted_close,
            confidence_low=p.confidence_low,
            confidence_high=p.confidence_high,
        )
        for p in raw_predictions
    ]

    return ForecastResponse(
        symbol=request.symbol.upper(),
        generated_at=datetime.now(timezone.utc).isoformat(),
        model=f"kronos-{MODEL_SIZE}",
        horizon=request.horizon,
        predictions=predictions,
    )
