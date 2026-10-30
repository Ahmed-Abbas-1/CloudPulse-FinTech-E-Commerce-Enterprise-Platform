FROM python:3.12-slim AS builder

WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends gcc && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim

WORKDIR /app
RUN groupadd -g 10001 appgroup && useradd -u 10001 -g appgroup -s /sbin/nologin -M appuser

COPY --from=builder /install /usr/local
COPY main.py .

RUN chown -R appuser:appgroup /app
USER 10001:10001

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
