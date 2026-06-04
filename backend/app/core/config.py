from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "CultureQuest"
    app_version: str = "0.1.0"
    debug: bool = False

    mongo_uri: str
    mongo_db: str = "culturequest"

    redis_url: str

    secret_key: str
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60

    flower_server_host: str = "0.0.0.0"
    flower_server_port: int = 9090
    fl_min_clients: int = 2
    fl_rounds: int = 10

    openai_api_key: str = ""

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
