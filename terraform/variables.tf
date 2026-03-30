variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "maplewood-mgmt"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-east5" # Columbus, Ohio
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-east5-a"
}

variable "google_oauth_client_id" {
  description = "OAuth 2.0 client ID for Google Sign-In"
  type        = string
}

variable "google_oauth_client_secret" {
  description = "OAuth 2.0 client secret for Google Sign-In"
  type        = string
  sensitive   = true
}
