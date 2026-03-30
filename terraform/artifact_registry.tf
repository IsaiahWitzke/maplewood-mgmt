resource "google_artifact_registry_repository" "backend" {
  location      = var.region
  repository_id = "maplewood-backend"
  format        = "DOCKER"
  project       = var.project_id

  depends_on = [google_project_service.apis]
}
