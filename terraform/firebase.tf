resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.apis]
}

resource "google_firebase_web_app" "web" {
  provider     = google-beta
  project      = var.project_id
  display_name = "maplewood-web"

  depends_on = [google_firebase_project.default]
}

data "google_firebase_web_app_config" "web" {
  provider   = google-beta
  project    = var.project_id
  web_app_id = google_firebase_web_app.web.app_id
}

# Identity Platform config + Google Sign-In
resource "google_identity_platform_config" "auth" {
  project = var.project_id

  authorized_domains = [
    "localhost",
    "${var.project_id}.firebaseapp.com",
    "${var.project_id}.web.app",
  ]

  sign_in {
    allow_duplicate_emails = false
  }

  depends_on = [google_firebase_project.default]
}

resource "google_identity_platform_default_supported_idp_config" "google" {
  project       = var.project_id
  idp_id        = "google.com"
  client_id     = var.google_oauth_client_id
  client_secret = var.google_oauth_client_secret
  enabled       = true

  depends_on = [google_identity_platform_config.auth]
}

# Firebase Storage - create the GCS bucket, then link to Firebase
resource "google_storage_bucket" "firebase_storage" {
  name     = "${var.project_id}.firebasestorage.app"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true

  depends_on = [google_project_service.apis]
}

resource "google_firebase_storage_bucket" "default" {
  provider  = google-beta
  project   = var.project_id
  bucket_id = google_storage_bucket.firebase_storage.name

  depends_on = [google_firebase_project.default, google_storage_bucket.firebase_storage]
}

resource "google_firebaserules_ruleset" "storage" {
  provider = google-beta
  project  = var.project_id

  source {
    files {
      name    = "storage.rules"
      content = <<-EOT
        rules_version = '2';
        service firebase.storage {
          match /b/{bucket}/o {
            match /receipts/{allPaths=**} {
              allow read, write: if request.auth != null;
            }
          }
        }
      EOT
    }
  }

  depends_on = [google_firebase_storage_bucket.default]
}

resource "google_firebaserules_release" "storage" {
  provider     = google-beta
  project      = var.project_id
  name         = "firebase.storage/${var.project_id}.firebasestorage.app"
  ruleset_name = google_firebaserules_ruleset.storage.name

  depends_on = [google_firebase_storage_bucket.default]
}

# Android app registration
resource "google_firebase_android_app" "mobile" {
  provider     = google-beta
  project      = var.project_id
  display_name = "maplewood-mobile"
  package_name = "com.maplewood.maplewood_mgmt"

  depends_on = [google_firebase_project.default]
}

output "firebase_api_key" {
  value = data.google_firebase_web_app_config.web.api_key
}

output "firebase_auth_domain" {
  value = "${var.project_id}.firebaseapp.com"
}
