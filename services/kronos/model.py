"""
Kronos model wrapper for OTCapital.

Loads the Kronos foundation model from HuggingFace and provides a clean
forecast interface. The model converts OHLCV candlestick data into price
predictions using a two-stage tokenizer + transformer architecture.

Model sizes:
  mini  —  4.1M params, runs on CPU, ~500MB RAM
  small —  49M params, CPU or GPU
  large — 499M params, GPU recommended

HuggingFace repo: shiyu-coder/Kronos-mini (and -small, -large)
Paper: https://arxiv.org/abs/2508.02739 (AAAI 2026)
"""

import os
import logging
from datetime import timedelta, date
from dataclasses import dataclass

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# Map short name → HuggingFace model ID
MODEL_IDS = {
    "mini":  "shiyu-coder/Kronos-mini",
    "small": "shiyu-coder/Kronos-small",
    "large": "shiyu-coder/Kronos-large",
}


@dataclass
class Prediction:
    date: str          # ISO date string "YYYY-MM-DD"
    predicted_close: float
    confidence_low: float
    confidence_high: float


class KronosModel:
    """Wraps KronosPredictor with OTCapital-specific input/output contracts."""

    def __init__(self, model_size: str = "mini"):
        model_size = model_size.lower()
        if model_size not in MODEL_IDS:
            raise ValueError(f"Invalid model_size '{model_size}'. Choose from: {list(MODEL_IDS)}")

        self.model_size = model_size
        self.model_id = MODEL_IDS[model_size]
        self._predictor = None

    def _load(self):
        """Lazy-load the Kronos model on first call."""
        if self._predictor is not None:
            return

        logger.info("Loading Kronos model: %s", self.model_id)

        try:
            from kronos import KronosPredictor  # installed from the Kronos repo
        except ImportError:
            raise RuntimeError(
                "Kronos package not found. Install it from: "
                "https://github.com/shiyu-coder/Kronos"
            )

        cache_dir = os.environ.get("HF_HOME", "/models")
        self._predictor = KronosPredictor.from_pretrained(
            self.model_id,
            cache_dir=cache_dir,
        )
        logger.info("Kronos model loaded successfully: %s", self.model_id)

    def forecast(
        self,
        ohlcv_data: list[dict],
        horizon: int = 7,
    ) -> list[Prediction]:
        """
        Generate price forecasts from OHLCV candlestick data.

        Args:
            ohlcv_data: List of dicts with keys: date, open, high, low, close, volume
                        Sorted oldest → newest. Minimum 30 candles.
            horizon:    Number of future trading days to predict (default: 7).

        Returns:
            List of Prediction objects, one per future trading day.
        """
        self._load()

        if len(ohlcv_data) < 30:
            raise ValueError("Need at least 30 OHLCV candles for a reliable forecast.")

        df = pd.DataFrame(ohlcv_data)
        df["date"] = pd.to_datetime(df["date"])
        df = df.sort_values("date").reset_index(drop=True)

        # Kronos expects a numpy array of shape [T, 5] in OHLCV order
        ohlcv_array = df[["open", "high", "low", "close", "volume"]].values.astype(np.float32)

        # KronosPredictor.predict returns dict with "mean" and optionally "quantiles"
        result = self._predictor.predict(
            ohlcv_array,
            prediction_length=horizon,
            num_samples=100,  # sample count for confidence intervals
        )

        # Build prediction dates starting the next calendar day after last candle
        last_date = df["date"].iloc[-1].date()
        predictions = []

        mean_forecasts = result["mean"]  # shape [horizon] or [[horizon]]
        if hasattr(mean_forecasts, "squeeze"):
            mean_forecasts = mean_forecasts.squeeze()

        # Confidence interval: use 10th/90th percentile if quantiles available
        q_low = result.get("quantile_0.1", None)
        q_high = result.get("quantile_0.9", None)
        if q_low is not None and hasattr(q_low, "squeeze"):
            q_low = q_low.squeeze()
        if q_high is not None and hasattr(q_high, "squeeze"):
            q_high = q_high.squeeze()

        for i in range(horizon):
            pred_date = last_date + timedelta(days=i + 1)
            predicted_close = float(mean_forecasts[i])

            # Use ±5% as fallback confidence band if no quantiles available
            conf_low = float(q_low[i]) if q_low is not None else predicted_close * 0.95
            conf_high = float(q_high[i]) if q_high is not None else predicted_close * 1.05

            predictions.append(Prediction(
                date=pred_date.isoformat(),
                predicted_close=round(predicted_close, 4),
                confidence_low=round(conf_low, 4),
                confidence_high=round(conf_high, 4),
            ))

        return predictions
