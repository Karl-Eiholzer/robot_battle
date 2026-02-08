import uuid
from fastapi import Header, HTTPException, status
from redis_client import redis_client
from config import Config


def generate_api_key() -> str:
    """Generate a unique API key using UUID"""
    return str(uuid.uuid4())


def generate_player_id() -> str:
    """Generate a unique player ID"""
    return f"player_{uuid.uuid4().hex[:12]}"


def store_player_key(player_id: str, api_key: str):
    """
    Store API key for player in Redis with bidirectional mapping
    - player:{player_id}:api_key → api_key
    - api_key:{api_key} → player_id (for reverse lookup)
    """
    # Store player_id → api_key mapping
    player_key = f"player:{player_id}:api_key"
    redis_client.client.set(player_key, api_key, ex=Config.TTL_PLAYER_SESSION)

    # Store api_key → player_id reverse mapping
    api_key_key = f"api_key:{api_key}"
    redis_client.client.set(api_key_key, player_id, ex=Config.TTL_PLAYER_SESSION)


def verify_api_key(api_key: str) -> str:
    """
    Verify API key and return player_id
    Returns None if invalid
    """
    api_key_key = f"api_key:{api_key}"
    player_id = redis_client.client.get(api_key_key)
    return player_id


def refresh_api_key_ttl(api_key: str):
    """Refresh TTL for API key to keep session alive"""
    player_id = verify_api_key(api_key)
    if player_id:
        # Refresh both mappings
        player_key = f"player:{player_id}:api_key"
        api_key_key = f"api_key:{api_key}"

        redis_client.client.expire(player_key, Config.TTL_PLAYER_SESSION)
        redis_client.client.expire(api_key_key, Config.TTL_PLAYER_SESSION)


async def get_current_player(x_api_key: str = Header(..., description="API key for authentication")) -> str:
    """
    FastAPI dependency to verify API key and return player_id
    Raises HTTPException if invalid
    """
    player_id = verify_api_key(x_api_key)

    if not player_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired API key"
        )

    # Refresh TTL on valid request to keep session alive
    refresh_api_key_ttl(x_api_key)

    return player_id
