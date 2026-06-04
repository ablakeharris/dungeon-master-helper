"""Entry point for running the D&D agent outside of `adk run`."""

import asyncio

from dotenv import load_dotenv

load_dotenv()

from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types

from dnd_agent import root_agent

APP_NAME = "dnd_waterdeep"
USER_ID = "dm"


async def run() -> None:
    session_service = InMemorySessionService()
    session = await session_service.create_session(
        app_name=APP_NAME, user_id=USER_ID
    )
    runner = Runner(
        agent=root_agent,
        app_name=APP_NAME,
        session_service=session_service,
    )

    print("D&D 5e Waterdeep Agent")
    print("Type 'quit' to exit.\n")

    while True:
        user_input = input("You: ").strip()
        if user_input.lower() in ("quit", "exit"):
            break
        if not user_input:
            continue

        content = types.Content(
            role="user", parts=[types.Part(text=user_input)]
        )
        response_text = ""
        try:
            async for event in runner.run_async(
                user_id=USER_ID, session_id=session.id, new_message=content
            ):
                print(f"DEBUG: Event = {event}")
                print(f"DEBUG: Event type = {type(event)}")
                if event and hasattr(event, 'content'):
                    print(f"DEBUG: Event content = {event.content}")
                    if event.content and event.content.parts:
                        for part in event.content.parts:
                            print(f"DEBUG: Part = {part}, type = {type(part)}")
                            if hasattr(part, 'text') and part.text:
                                response_text += part.text
        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()

        if response_text:
            print(f"\nDM: {response_text}\n")
        else:
            print(f"\nDM: (no response)\n")


def main() -> None:
    asyncio.run(run())


if __name__ == "__main__":
    main()
