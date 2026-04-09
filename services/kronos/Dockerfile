# ---------------------------------------------------------------------------
# Kronos Forecasting Microservice
# ---------------------------------------------------------------------------
# Python 3.11 slim image with PyTorch CPU build (no CUDA by default).
# For GPU support, swap the base image to pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime
# and remove the --index-url torch CPU override below.
#
# Model weights are downloaded from HuggingFace Hub on first startup and
# cached in the /models volume (see compose.example.ai.yml).
# ---------------------------------------------------------------------------

FROM python:3.11-slim

WORKDIR /app

# System deps for torch + numpy
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
# CPU-only torch to keep image size manageable (~800MB vs 5GB+ for CUDA)
# Override with a CUDA wheel index for GPU servers.
COPY requirements.txt .
RUN pip install --no-cache-dir \
    torch==2.5.1 \
    --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir \
    fastapi==0.115.6 \
    uvicorn[standard]==0.34.0 \
    pydantic==2.10.4 \
    numpy==1.26.4 \
    pandas==2.2.3 \
    transformers==4.47.1 \
    huggingface_hub==0.27.0 \
    && pip install --no-cache-dir \
    git+https://github.com/shiyu-coder/Kronos.git

COPY main.py model.py ./

# HuggingFace cache mount point (map to a named Docker volume)
ENV HF_HOME=/models
ENV KRONOS_MODEL=mini
ENV PORT=5000

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5000"]
