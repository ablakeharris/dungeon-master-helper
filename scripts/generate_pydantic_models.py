import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIRECTORY = PROJECT_ROOT / "dnd5e_json_schema" / "schemas"
OUTPUT_DIRECTORY = PROJECT_ROOT / "dnd_agent" / "generated_models"


def main() -> None:
    schema_files = list(SCHEMA_DIRECTORY.glob("*.json"))
    if not schema_files:
        raise FileNotFoundError(f"No JSON Schema files found in {SCHEMA_DIRECTORY}")

    command = [
        "datamodel-codegen",
        "--input",
        str(SCHEMA_DIRECTORY),
        "--input-file-type",
        "jsonschema",
        "--output",
        str(OUTPUT_DIRECTORY),
        "--output-model-type",
        "pydantic_v2.BaseModel",
        "--target-python-version",
        "3.13",
        "--disable-timestamp",
        "--use-annotated",
        "--deserialize-default-values",
        "enum",
    ]
    subprocess.run(command, cwd=PROJECT_ROOT, check=True)
    print(
        f"Generated Pydantic models for {len(schema_files)} schemas in {OUTPUT_DIRECTORY}"
    )


if __name__ == "__main__":
    main()
