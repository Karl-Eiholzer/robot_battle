"""
Invite code generation for game joining.
Generates memorable 2-word codes like "golden-dragon".
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

# Every noun pairs with every adjective (~3,850 codes); none repeats an adjective
NOUNS = [
    "apex", "arrow", "atlas", "atom", "beacon", "bear", "blade", "castle", "cipher",
    "circuit", "citadel", "code", "comet", "core", "cosmos", "crown", "delta",
    "dragon", "eagle", "echo", "engine", "falcon", "flame", "fortress", "galaxy",
    "ghost", "grid", "haven", "hawk", "horizon", "hunter", "island", "knight",
    "lion", "lunar", "matrix", "mech", "moon", "nebula", "nexus", "ninja", "omega",
    "orbit", "palace", "phoenix", "pixel", "portal", "prism", "pulse", "quest",
    "raven", "realm", "rebel", "ridge", "rocket", "saber", "scout", "sector",
    "shark", "signal", "spark", "sphere", "spire", "star", "station", "summit",
    "surge", "temple", "tiger", "titan", "tower", "vault", "vector", "vertex",
    "viper", "void", "volt", "vortex", "wave", "wolf", "zero", "zone"
]


def generate_invite_code(redis_client: 'RedisClient' = None, max_retries: int = 20) -> str:
    """
    Generate a unique 2-word invite code.
    Format: adjective-noun (e.g., "golden-dragon")

    Args:
        redis_client: Optional RedisClient to check for collisions
        max_retries: Maximum attempts to find unique code

    Returns:
        A unique invite code string

    Raises:
        RuntimeError: If unable to generate unique code after max_retries
    """
    for attempt in range(max_retries):
        # Generate random 2-word code
        adjective = random.choice(ADJECTIVES)
        noun = random.choice(NOUNS)
        code = f"{adjective}-{noun}"

        # If no redis client provided, return immediately
        if redis_client is None:
            return code

        # Check for collision
        if redis_client.get_invite_code_info(code) is None:
            return code

    # Failed to generate unique code
    raise RuntimeError(f"Failed to generate unique invite code after {max_retries} attempts")
