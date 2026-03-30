# Backend (Deprecated)

**Status: Deprecated — not in use.**

This FastAPI backend was built as part of the original architecture (Cloud Run + Firestore + GCS). We've since pivoted to a serverless approach where the Flutter mobile app calls Google APIs directly:

- **Gemini API** for receipt OCR (replaces the `/receipts/upload` endpoint)
- **Google Sheets API** for data storage (replaces Firestore)
- **Google Drive API** for image storage (replaces GCS)

No backend is needed. The Flutter app in `../mobile/` handles everything client-side with OAuth.

This code is kept for reference but is not deployed or maintained.
