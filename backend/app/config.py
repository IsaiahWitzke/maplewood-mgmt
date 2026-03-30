from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    gcp_project_id: str = "maplewood-mgmt"
    gcp_region: str = "us-east5"
    receipt_images_bucket: str = "maplewood-mgmt-receipt-images"
    gemini_model: str = "gemini-2.5-flash"

    class Config:
        env_file = ".env"


settings = Settings()
