"""Ingest documents from the docs/ directory into ChromaDB for RAG retrieval.

Supports .txt, .md, and .pdf files. Documents are chunked and embedded using
ChromaDB's default embedding function (all-MiniLM-L6-v2).

Usage:
    python scripts/ingest_docs.py
    python scripts/ingest_docs.py --docs-dir ./my_docs --chunk-size 800
"""

import argparse
import hashlib
import os
from pathlib import Path

import chromadb
from chromadb.errors import NotFoundError

CHROMA_PATH = "chroma_data"
COLLECTION_NAME = "dnd_documents"

DEFAULT_CHUNK_SIZE = 1000
DEFAULT_CHUNK_OVERLAP = 200


def chunk_text(text: str, chunk_size: int, overlap: int) -> list[str]:
    """Split text into overlapping chunks, breaking on paragraph boundaries when possible."""
    if len(text) <= chunk_size:
        return [text]

    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size

        if end < len(text):
            # Try to break on a paragraph boundary
            newline_pos = text.rfind("\n\n", start, end)
            if newline_pos > start + chunk_size // 2:
                end = newline_pos + 2
            else:
                # Fall back to sentence boundary
                period_pos = text.rfind(". ", start, end)
                if period_pos > start + chunk_size // 2:
                    end = period_pos + 2

        chunk = text[start:end].strip()
        if chunk:
            chunks.append(chunk)

        start = end - overlap if end < len(text) else len(text)

    return chunks


def read_text_file(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def read_pdf_file(path: Path) -> str:
    try:
        import pypdf
    except ImportError:
        print(f"  Skipping {path.name}: install 'pypdf' to process PDFs (uv add pypdf)")
        return ""

    reader = pypdf.PdfReader(path)
    pages = []
    for i, page in enumerate(reader.pages):
        text = page.extract_text()
        if text:
            pages.append(f"[Page {i + 1}]\n{text}")
    return "\n\n".join(pages)


READERS = {
    ".txt": read_text_file,
    ".md": read_text_file,
    ".pdf": read_pdf_file,
}


def ingest(docs_dir: str, chunk_size: int, chunk_overlap: int) -> None:
    docs_path = Path(docs_dir)
    if not docs_path.exists():
        print(f"Error: docs directory '{docs_dir}' does not exist.")
        return

    files = [f for f in docs_path.iterdir() if f.suffix.lower() in READERS]
    if not files:
        print(f"No supported files found in '{docs_dir}'. Add .txt, .md, or .pdf files.")
        return

    print(f"Found {len(files)} document(s) in '{docs_dir}'")

    client = chromadb.PersistentClient(path=CHROMA_PATH)

    # Delete existing collection to do a clean re-import
    try:
        client.delete_collection(name=COLLECTION_NAME)
        print(f"Cleared existing '{COLLECTION_NAME}' collection.")
    except NotFoundError:
        pass

    collection = client.create_collection(name=COLLECTION_NAME)

    total_chunks = 0
    for file_path in sorted(files):
        print(f"  Processing: {file_path.name}")
        reader = READERS[file_path.suffix.lower()]
        text = reader(file_path)
        if not text:
            continue

        chunks = chunk_text(text, chunk_size, chunk_overlap)
        print(f"    -> {len(chunks)} chunk(s)")

        ids = []
        documents = []
        metadatas = []
        for i, chunk in enumerate(chunks):
            chunk_id = hashlib.md5(f"{file_path.name}:{i}".encode()).hexdigest()
            ids.append(chunk_id)
            documents.append(chunk)
            metadatas.append({
                "source": file_path.name,
                "chunk_index": i,
            })

        collection.add(ids=ids, documents=documents, metadatas=metadatas)
        total_chunks += len(chunks)

    print(f"\nDone! Ingested {total_chunks} chunks from {len(files)} file(s) into '{COLLECTION_NAME}'.")
    print(f"ChromaDB data stored at: {os.path.abspath(CHROMA_PATH)}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest D&D documents into ChromaDB")
    parser.add_argument("--docs-dir", default="docs", help="Directory containing documents")
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE, help="Chunk size in characters")
    parser.add_argument("--chunk-overlap", type=int, default=DEFAULT_CHUNK_OVERLAP, help="Overlap between chunks")
    args = parser.parse_args()
    ingest(args.docs_dir, args.chunk_size, args.chunk_overlap)


if __name__ == "__main__":
    main()
