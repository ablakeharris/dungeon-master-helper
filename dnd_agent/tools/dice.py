import random
import re


def roll_dice(notation: str) -> dict:
    """Roll dice using standard D&D notation (e.g. '2d6', '1d20+5', '4d6-1').

    Args:
        notation: Dice notation string like '2d6', '1d20+5', '3d8-2'.

    Returns:
        A dict with the individual rolls, modifier, and total.
    """
    match = re.fullmatch(r"(\d+)d(\d+)([+-]\d+)?", notation.strip().lower())
    if not match:
        return {"error": f"Invalid dice notation: '{notation}'. Use format like '2d6' or '1d20+5'."}

    count = int(match.group(1))
    sides = int(match.group(2))
    modifier = int(match.group(3)) if match.group(3) else 0

    if count < 1 or count > 100:
        return {"error": "Number of dice must be between 1 and 100."}
    if sides < 2 or sides > 100:
        return {"error": "Number of sides must be between 2 and 100."}

    rolls = [random.randint(1, sides) for _ in range(count)]
    total = sum(rolls) + modifier

    return {
        "notation": notation,
        "rolls": rolls,
        "modifier": modifier,
        "total": total,
    }
