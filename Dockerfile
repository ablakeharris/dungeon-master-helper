FROM python:3.14-slim AS build

# This stage runs the doc ingestion script to populate the cache.

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked

COPY dnd_agent/ dnd_agent/

RUN uv run python dnd_agent/scripts/ingest_docs.py

FROM python:3.14-slim AS deploy

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev

COPY --from=build /app/dnd_agent/ ./dnd_agent/
COPY --from=build /root/.cache/chroma/ /root/.cache/chroma/

CMD exec .venv/bin/adk web --host 0.0.0.0 --port ${PORT:-8080} --allow_origins=http://localhost:8088,http://127.0.0.1:8088 .
