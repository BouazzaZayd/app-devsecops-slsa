FROM python:3.12-slim

LABEL org.opencontainers.image.source="http://10.0.0.11:3000/devsecops-lab/app-devsecops"

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir gunicorn

COPY app/app.py .
COPY app/auth.py .

RUN useradd --system --no-create-home appuser \
    && mkdir -p /data \
    && chown appuser:appuser /data

USER appuser

ENV FLASK_HOST=0.0.0.0
ENV FLASK_PORT=8080

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
