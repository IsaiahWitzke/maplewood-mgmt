output "receipt_images_bucket" {
  value = google_storage_bucket.receipt_images.name
}

output "backend_service_account_email" {
  value = google_service_account.backend.email
}

output "firestore_database" {
  value = google_firestore_database.default.name
}

output "cloud_run_url" {
  value = google_cloud_run_v2_service.backend.uri
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}
