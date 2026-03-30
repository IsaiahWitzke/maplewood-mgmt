# Terraform (Partially Active)

**Status: Mostly deprecated. Firebase Auth resources are still in use.**

This Terraform config originally provisioned the full backend stack (Cloud Run, Firestore, GCS, Document AI). We've pivoted to a serverless Flutter-only approach.

## Still in use
- `firebase.tf` — Firebase project, web app registration, Identity Platform config, Google Sign-In provider
- API enablement for `identitytoolkit.googleapis.com`

## No longer needed
- `cloud_run.tf` / `iam.tf` — backend service (not deployed)
- `firestore.tf` — replaced by Google Sheets
- `storage.tf` — replaced by Google Drive
- `document_ai.tf` — deleted (replaced by Gemini)

The Cloud Run service, Firestore, and GCS bucket cost $0 at rest, so they're left in place but unused.
