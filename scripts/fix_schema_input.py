import json
import re
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCHEMA_DIRECTORY = PROJECT_ROOT / "dnd5e_json_schema" / "schemas"
DAMAGE_TYPE_SCHEMA = SCHEMA_DIRECTORY / "damage_type.schema.json"
BOOLEAN_FALSE_DEFAULT = re.compile(
    r'("type"\s*:\s*(?:"boolean"|\[[^\]]*"boolean"[^\]]*\])'
    r'\s*,\s*"default"\s*:\s*)"false"'
)


def count_boolean_false_defaults(value: Any) -> int:
    if isinstance(value, dict):
        schema_type = value.get("type")
        includes_boolean = schema_type == "boolean" or (
            isinstance(schema_type, list) and "boolean" in schema_type
        )
        current = int(includes_boolean and value.get("default") == "false")
        return current + sum(
            count_boolean_false_defaults(item) for item in value.values()
        )
    if isinstance(value, list):
        return sum(count_boolean_false_defaults(item) for item in value)
    return 0


def remove_damage_type_default() -> None:
    source = DAMAGE_TYPE_SCHEMA.read_text(encoding="utf-8")
    schema = json.loads(source)
    if "default" not in schema:
        return
    if schema["default"] not in ("none", ""):
        raise ValueError(f"Unexpected damage type default: {schema['default']!r}")

    del schema["default"]
    DAMAGE_TYPE_SCHEMA.write_text(
        json.dumps(schema, indent=4) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    changes = []
    for schema_path in sorted(SCHEMA_DIRECTORY.glob("*.json")):
        source = schema_path.read_text(encoding="utf-8")
        schema = json.loads(source)
        expected_count = count_boolean_false_defaults(schema)
        updated_source, replacement_count = BOOLEAN_FALSE_DEFAULT.subn(
            r"\1false", source
        )
        if replacement_count != expected_count:
            raise ValueError(
                f"Unexpected boolean default layout in {schema_path}: "
                f"found {expected_count} target(s), matched {replacement_count}"
            )
        if replacement_count:
            changes.append((schema_path, updated_source, replacement_count))

    for schema_path, updated_source, _ in changes:
        schema_path.write_text(updated_source, encoding="utf-8")

    total = sum(replacement_count for _, _, replacement_count in changes)
    print(f"Updated {total} boolean default(s) across {len(changes)} schema file(s).")
    remove_damage_type_default()


if __name__ == "__main__":
    main()
