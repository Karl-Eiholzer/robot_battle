"""
Invite code generation for game joining.
Generates memorable 3-word codes like "forest-tiger-moon".
"""
import random
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from redis_client import RedisClient

# Word lists for invite code generation
ADJECTIVES = [
    "ancient", "brave", "bright", "calm", "cosmic", "crystal", "dark", "deep",
    "distant", "electric", "emerald", "fast", "fierce", "frozen", "gentle", "golden",
    "hidden", "iron", "jade", "laser", "lucky", "magic", "mighty", "mystic",
    "neon", "nova", "ocean", "plasma", "quantum", "rapid", "ruby", "shadow",
    "silent", "silver", "solar", "sonic", "steel", "storm", "swift", "thunder",
    "turbo", "ultra", "velvet", "violet", "wild", "winter", "zen"
]

NOUNS = [
    "apex", "arrow", "atom", "bear", "blade", "comet", "crown", "delta",
    "dragon", "eagle", "echo", "falcon", "flame", "ghost", "hawk", "hunter",
    "knight", "laser", "lion", "lunar", "mech", "nebula", "ninja", "omega",
    "phoenix", "pixel", "prism", "pulse", "quest", "raven", "rebel", "rocket",
    "saber", "scout", "shark", "signal", "spark", "star", "surge", "titan",
    "tiger", "viper", "volt", "wave", "wolf", "zero"
]

OBJECTS = [
    "atlas", "beacon", "castle", "cipher", "circuit", "citadel", "code", "core",
    "cosmos", "crystal", "engine", "fortress", "galaxy", "grid", "haven", "horizon",
    "island", "matrix", "moon", "nexus", "orbit", "palace", "portal", "prism",
    "realm", "ridge", "sector", "sphere", "spire", "station", "summit", "temple",
    "tower", "vault", "vector", "vertex", "void", "vortex", "zone"
]


def generate_invite_code(redis_client: 'RedisClient' = None, max_retries: int = 10) -> str:
    """
    Generate a unique 3-word invite code.
    Format: adjective-noun-object (e.g., "golden-dragon-castle")

    Args:
        redis_client: Optional RedisClient to check for collisions
        max_retries: Maximum attempts to find unique code

    Returns:
        A unique invite code string

    Raises:
        RuntimeError: If unable to generate unique code after max_retries
    """
    for attempt in range(max_retries):
        # Generate random 3-word code
        adjective = random.choice(ADJECTIVES)
        noun = random.choice(NOUNS)
        obj = random.choice(OBJECTS)
        code = f"{adjective}-{noun}-{obj}"

        # If no redis client provided, return immediately
        if redis_client is None:
            return code

        # Check for collision
        if redis_client.get_invite_code_info(code) is None:
            return code

    # Failed to generate unique code
    raise RuntimeError(f"Failed to generate unique invite code after {max_retries} attempts")
