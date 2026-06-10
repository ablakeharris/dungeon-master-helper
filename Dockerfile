FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev

COPY dnd_agent/ dnd_agent/

RUN uv run python dnd_agent/scripts/ingest_docs.py

CMD exec .venv/bin/adk web --host 0.0.0.0 --port ${PORT:-8080} .
