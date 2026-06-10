# dungeon-master-helper

A Dungeon Master assistant powered by Google ADK and Gemini. It answers D&D 5e rules questions, looks up spells/monsters/items from source documents via RAG, and rolls dice.

## Prerequisites

- Python 3.14+
- [uv](https://docs.astral.sh/uv/)
- A Google Cloud project with the Vertex AI API enabled
- Authenticated via ADC locally (`gcloud auth application-default login`)

## Setup

Install dependencies:

```bash
uv sync
```

## Ingest Documents

Place your D&D source documents (`.txt`, `.md`, or `.pdf`) in the `docs/` directory, then run:

```bash
uv run python scripts/ingest_docs.py
```

This chunks the documents and stores embeddings in a local ChromaDB database (`chroma_data/`).

## Run Locally

Launch the ADK web UI:

```bash
uv run adk web .
```

## Deploy to Cloud Run (private)

The app is deployed to Cloud Run with public access disabled (`--no-allow-unauthenticated`). Instead of exposing a public endpoint, you reach the running service through an authenticated local proxy that signs each request with your own `gcloud` identity. Only identities granted `roles/run.invoker` can reach the service, so it stays private without any load balancer, custom domain, or OAuth setup.

### 1. Deploy the Cloud Run service

```bash
dnd_agent/scripts/deploy.sh
```

This enables the needed APIs, grants the build service account access to Vertex AI (for doc ingestion at build time), builds the image, deploys the service with public access disabled, and grants the deploying account `run.invoker` so it can use the proxy.

### 2. Run it locally through the proxy

```bash
dnd_agent/scripts/run-local.sh
```

This starts `gcloud run services proxy` (installing the `cloud-run-proxy` component on first run) and forwards `localhost:8088` to the service. Open:

> http://localhost:8088/dev-ui/

Leave the proxy running while you use the app.

### Granting access to another person

Anyone who needs access runs the proxy from their own machine after you grant their account `run.invoker`:

```bash
gcloud run services add-iam-policy-binding dnd-waterdeep \
  --region=us-central1 --project=dnd-waterdeep-492623 \
  --member="user:someone@example.com" --role="roles/run.invoker"
```

They need the `gcloud` CLI and access to the project. The service is never exposed publicly.

### Environment variables

The scripts default to:

| Var | Default |
| --- | --- |
| `PROJECT` | `dnd-waterdeep-492623` |
| `REGION` | `us-central1` |
| `SERVICE` | `dnd-waterdeep` |
| `PORT` | `8088` (local proxy port, `run-local.sh` only) |

Override them inline to target a different project/region/port.
