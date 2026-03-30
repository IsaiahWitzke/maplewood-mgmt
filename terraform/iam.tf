resource "google_service_account" "backend" {
  account_id   = "maplewood-backend"
  display_name = "Maplewood Backend Service Account"
  project      = var.project_id
}

# Firestore access
resource "google_project_iam_member" "backend_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

# Cloud Storage access
resource "google_project_iam_member" "backend_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

# Vertex AI access (Gemini)
resource "google_project_iam_member" "backend_vertexai" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.backend.email}"
}
