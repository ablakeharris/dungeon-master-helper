import chromadb


CHROMA_PATH = "chroma_data"
COLLECTION_NAME = "dnd_documents"


def _get_collection() -> chromadb.Collection:
    client = chromadb.PersistentClient(path=CHROMA_PATH)
    return client.get_collection(name=COLLECTION_NAME)


def search_documents(query: str, n_results: int = 5) -> dict:
    """Search the D&D knowledge base for relevant rules, lore, or campaign information.

    Use this tool when you need to look up specific rules, spells, monsters,
    NPCs, locations, or campaign details from source material.

    Args:
        query: A natural language search query describing what to look up.
        n_results: Number of results to return (default 5, max 10).

    Returns:
        A dict containing matching document excerpts and their sources.
    """
    n_results = min(max(n_results, 1), 10)

    try:
        collection = _get_collection()
    except Exception:
        return {
            "error": "Knowledge base not found. Run the ingestion script first: "
            "python scripts/ingest_docs.py"
        }

    results = collection.query(query_texts=[query], n_results=n_results)

    documents = []
    for i, doc in enumerate(results["documents"][0]):
        metadata = results["metadatas"][0][i] if results["metadatas"] else {}
        documents.append({
            "content": doc,
            "source": metadata.get("source", "unknown"),
            "page": metadata.get("page", None),
        })

    return {"query": query, "results": documents}
