terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

# Enable required GCP APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "firestore.googleapis.com",
    "aiplatform.googleapis.com",  # Vertex AI (Gemini)
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "firebase.googleapis.com",
    "identitytoolkit.googleapis.com", # Firebase Auth
    "firebasestorage.googleapis.com",
    "firebaserules.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}
