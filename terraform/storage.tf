resource "google_storage_bucket" "receipt_images" {
  name     = "${var.project_id}-receipt-images"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true

  # Move to Nearline after 90 days (slightly cheaper, still fast access)
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # Move to Coldline after 1 year (cheap storage for old receipts)
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  depends_on = [google_project_service.apis]
}
