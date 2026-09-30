from google.adk.agents import Agent

from dnd_agent.generated_models.Character_schema import DD5ECharacter

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
""",
    tools=[],
    output_schema=DD5ECharacter,
)
