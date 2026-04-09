FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev

COPY dnd_agent/ dnd_agent/
COPY scripts/ scripts/
COPY docs/ docs/

RUN uv run python scripts/ingest_docs.py

EXPOSE 8000

CMD ["uv", "run", "adk", "web", "--host", "0.0.0.0", "--port", "8000", "."]
