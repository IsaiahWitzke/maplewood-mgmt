from google.cloud import firestore

from app.config import settings

db = firestore.Client(project=settings.gcp_project_id)
