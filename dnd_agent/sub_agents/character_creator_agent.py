from google.adk.agents import Agent
from google.adk.agents.callback_context import CallbackContext
from google.genai import types
from pydantic import BaseModel

from dnd_agent.generated_models.Character_schema import (
    Background,
    DD5ECharacter,
)
from dnd_agent.generated_models.Class_schema import DD5EClass, Spellcasting
from dnd_agent.generated_models.Creature_schema import SavingThrows, Skills
from dnd_agent.generated_models.equipment_schema import JsonSchemaForDD5EEquiment
from dnd_agent.generated_models.feature_schema import JsonSchemaForDD5EFeature
from dnd_agent.generated_models.Race_schema import DD5ERace, Size
from dnd_agent.generated_models.Spell_schema import Model as DD5ESpell


class AbilityScores(BaseModel):
    str: int
    dex: int
    con: int
    int: int
    wis: int
    cha: int


class SpellOutputSchema(BaseModel):
    name: str
    description: str
    level: str
    casting_time: str
    range_area: str
    components: list[str]
    duration: str
    ritual: bool
    concentration: bool


class EquipmentOutputSchema(BaseModel):
    name: str
    quantity: int
    magic: bool


class CharacterOutputSchema(BaseModel):
    name: str
    player_name: str
    race: str
    race_subtype: str
    size: str
    class_name: str
    level: int
    spellcasting_ability: str
    background: str
    alignment: str
    ability_scores: AbilityScores
    hit_points: int
    armor_class: int
    speed: int
    hit_die: int
    saving_throws: list[str]
    skill_proficiencies: list[str]
    weapon_proficiencies: list[str]
    armor_proficiencies: list[str]
    tool_proficiencies: list[str]
    languages: list[str]
    class_features: list[str]
    racial_traits: list[str]
    equipment: list[EquipmentOutputSchema]
    spells: list[SpellOutputSchema]


def _normalize_name(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


_ABILITY_NAMES = {
    "strength": "str",
    "dexterity": "dex",
    "constitution": "con",
    "intelligence": "int",
    "wisdom": "wis",
    "charisma": "cha",
}


# If we were to pass `DD5ECharacter` directly to the output_schema, the output would be too large and Gemini will reject it.
# Instead we use a simplified `CharacterOutputSchema`, and then this function is run as a callback to produce the `DD5ECharacter`
def _canonical_character(draft: CharacterOutputSchema) -> DD5ECharacter:
    skill_proficiencies = {_normalize_name(name) for name in draft.skill_proficiencies}
    skills = {
        name: _normalize_name(name) in skill_proficiencies
        for name in Skills.model_fields
    }
    saving_throw_proficiencies = {
        _ABILITY_NAMES.get(_normalize_name(name), _normalize_name(name))
        for name in draft.saving_throws
    }
    saving_throws = {
        alias or name: _ABILITY_NAMES.get(
            _normalize_name(alias or name), _normalize_name(alias or name)
        )
        in saving_throw_proficiencies
        for name, field in SavingThrows.model_fields.items()
        for alias in [field.alias]
    }

    race = DD5ERace.model_validate(
        {
            "name": draft.race,
            "subtype": draft.race_subtype,
            "size": Size(draft.size),
            "traits": [
                JsonSchemaForDD5EFeature(name=trait) for trait in draft.racial_traits
            ],
        }
    )
    character_class = DD5EClass.model_validate(
        {
            "name": draft.class_name,
            "level": draft.level,
            "hit_die": draft.hit_die,
            "spellcasting": Spellcasting(draft.spellcasting_ability),
            "features": [
                JsonSchemaForDD5EFeature(name=feature)
                for feature in draft.class_features
            ],
        }
    )

    return DD5ECharacter.model_validate(
        {
            "name": draft.name,
            "alignment": draft.alignment,
            "speed": {
                "Walk": draft.speed,
                "Burrow": 0,
                "Climb": 0,
                "Fly": 0,
                "Hover": False,
                "Swim": 0,
            },
            "hit_points": {
                "max": draft.hit_points,
                "current": draft.hit_points,
                "dice": [{"sides": draft.hit_die, "count": draft.level}],
            },
            "skills": skills,
            "languages": draft.languages,
            "ability_scores": draft.ability_scores.model_dump(),
            "saving_throws": saving_throws,
            "armor_class": {"value": draft.armor_class},
            "race": race,
            "classes": [character_class],
            "background": Background(name=draft.background),
            "player": {"name": draft.player_name},
            "weapon_proficiencies": draft.weapon_proficiencies,
            "armor_proficiencies": draft.armor_proficiencies,
            "tool_proficiencies": draft.tool_proficiencies,
            "equipment": [
                JsonSchemaForDD5EEquiment.model_validate(item.model_dump())
                for item in draft.equipment
            ],
            "spells": [
                DD5ESpell.model_validate(spell.model_dump()) for spell in draft.spells
            ],
            "shield": False,
        }
    )


def _return_canonical_character(
    callback_context: CallbackContext,
) -> types.Content:
    draft = CharacterOutputSchema.model_validate(
        callback_context.state["character_draft"]
    )
    character = _canonical_character(draft)
    return types.Content(
        role="model",
        parts=[
            types.Part(
                text=character.model_dump_json(
                    by_alias=True, exclude_none=True, indent=2
                )
            )
        ],
    )


character_creator_agent = Agent(
    model="gemini-2.5-flash",
    name="character_creator",
    description="D&D 5e character creation assistant",
    instruction="""Generate a JSON representation of a D&D 5e character based on the user's prompt.

Return only the character data matching the provided output schema. Do not include
Markdown, commentary, or fields outside the schema. Use the character details and
constraints requested by the user. If details are omitted, make reasonable, internally
consistent choices for a playable 5e character, including every required schema field.
Keep rules-based choices consistent with the requested edition and character options.
Use one of Tiny, Small, Medium, Large, Huge, or Gargantuan for size. Use a numeric hit
die from 1, 2, 4, 6, 8, 10, 12, or 20. Use str, dex, con, int, wis, or cha for
spellcasting_ability and saving_throws; use an empty string when spellcasting does not
apply. For spells, include all schema fields and use only V, S, M, F, DF, or XP for
components.
""",
    tools=[],
    output_schema=CharacterOutputSchema,
    output_key="character_draft",
    after_agent_callback=_return_canonical_character,
)
