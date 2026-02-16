import os
from dotenv import load_dotenv

# Load environment variables from .env file if it exists
load_dotenv()

class Config:
    """Application configuration"""

    # Redis configuration
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

    # API configuration
    API_SECRET = os.getenv("API_SECRET", "dev_secret_key")

    # Environment
    ENVIRONMENT = os.getenv("ENVIRONMENT", "development")

    # TTL settings (in seconds)
    TTL_ACTIVE_GAME = 24 * 60 * 60  # 24 hours
    TTL_COMPLETED_GAME = 1 * 60 * 60  # 1 hour
    TTL_PLAYER_SESSION = 48 * 60 * 60  # 48 hours

    # Game settings
    DEFAULT_MAX_PLAYERS = 4
    MIN_PLAYERS = 2
    MAX_PLAYERS = 8

    @classmethod
    def validate(cls):
        """Validate that required configuration is present"""
        required_vars = ["REDIS_URL", "API_SECRET"]
        missing = [var for var in required_vars if not getattr(cls, var)]

        if missing:
            raise ValueError(f"Missing required environment variables: {', '.join(missing)}")

    @classmethod
    def is_production(cls) -> bool:
        """Check if running in production environment"""
        return cls.ENVIRONMENT == "production"

# Validate configuration on import
Config.validate()
