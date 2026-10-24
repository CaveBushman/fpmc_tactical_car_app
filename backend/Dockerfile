FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN useradd --system --uid 1000 tactical && chown -R tactical /app
USER tactical

EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
