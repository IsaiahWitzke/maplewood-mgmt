import base64
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

logger = logging.getLogger(__name__)

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from google.cloud import storage
from google.cloud.firestore_v1 import FieldFilter
import vertexai
from vertexai.generative_models import GenerativeModel, Part

from app.auth import get_current_user
from app.config import settings
from app.db import db
from app.models import ExtractedData, ReceiptConfirm, ReceiptResponse, ReceiptUpdate

router = APIRouter(prefix="/receipts", tags=["receipts"])

storage_client = storage.Client(project=settings.gcp_project_id)
bucket = storage_client.bucket(settings.receipt_images_bucket)

vertexai.init(project=settings.gcp_project_id, location=settings.gcp_region)
gemini_model = GenerativeModel(settings.gemini_model)


def _upload_image_to_gcs(file_bytes: bytes, content_type: str) -> str:
    """Upload receipt image to GCS, return storage path."""
    filename = f"receipts/{uuid.uuid4()}"
    blob = bucket.blob(filename)
    blob.upload_from_string(file_bytes, content_type=content_type)
    return filename


def _get_image_url(receipt_id: str) -> str:
    """Return a URL to our own image proxy endpoint."""
    return f"/receipts/{receipt_id}/image"


RECEIPT_EXTRACTION_PROMPT = """Extract the following fields from this receipt image.
Return ONLY valid JSON with these exact keys:
{
  "vendor": "store/supplier name",
  "date": "YYYY-MM-DD format",
  "subtotal": 0.00,
  "hst": 0.00,
  "total": 0.00
}

Rules:
- subtotal = amount before tax
- hst = HST / tax amount (this is Ontario, Canada - HST is 13%)
- total = final amount paid
- If a field is not visible or unclear, use null
- Amounts must be numbers, not strings
- Date must be YYYY-MM-DD or null
"""


def _extract_receipt_with_gemini(file_bytes: bytes, mime_type: str) -> dict:
    """Use Gemini to OCR + extract receipt fields in one shot."""
    image_part = Part.from_data(data=file_bytes, mime_type=mime_type)

    response = gemini_model.generate_content(
        [RECEIPT_EXTRACTION_PROMPT, image_part],
        generation_config={
            "temperature": 0.1,
            "max_output_tokens": 1024,
            "response_mime_type": "application/json",
        },
    )

    raw_text = response.text
    logger.info("Gemini raw response: %s", raw_text)

    # Strip markdown code fences if Gemini wraps the JSON
    cleaned = raw_text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[1] if "\n" in cleaned else cleaned[3:]
        if cleaned.endswith("```"):
            cleaned = cleaned[:-3].strip()

    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError:
        logger.warning("Failed to parse Gemini response, attempting repair")
        # Try to close truncated JSON
        if not cleaned.endswith("}"):
            cleaned += '}'
        parsed = json.loads(cleaned)

    # Normalize amounts
    for key in ["subtotal", "hst", "total"]:
        if parsed.get(key) is not None:
            parsed[key] = round(float(parsed[key]), 2)

    # Add confidence (Gemini doesn't give per-field scores, use finish_reason as proxy)
    parsed["confidence"] = {}

    return parsed


def _parse_amount(value: str) -> Optional[float]:
    """Parse a dollar amount string to float."""
    if not value:
        return None
    try:
        cleaned = value.replace("$", "").replace(",", "").strip()
        return round(float(cleaned), 2)
    except (ValueError, TypeError):
        return None


def _check_validation(extracted: dict) -> bool:
    """Check if subtotal + hst ≠ total. Returns True if there's a warning."""
    subtotal = extracted.get("subtotal")
    hst = extracted.get("hst")
    total = extracted.get("total")
    if subtotal is not None and hst is not None and total is not None:
        expected = round(subtotal + hst, 2)
        return abs(expected - total) > 0.01
    return False


def _doc_to_receipt(doc_id: str, data: dict) -> ReceiptResponse:
    """Convert Firestore doc to ReceiptResponse."""
    extracted_data = data.get("extracted", {})
    image_path = data.get("imageStoragePath", "")

    return ReceiptResponse(
        id=doc_id,
        owner_uid=data["ownerUid"],
        project_id=data.get("projectId"),
        status=data["status"],
        image_storage_path=image_path,
        image_url=_get_image_url(doc_id) if image_path else None,
        extracted=ExtractedData(**extracted_data),
        has_validation_warning=data.get("hasValidationWarning", False),
        ocr_error=data.get("ocrError"),
        created_at=data["createdAt"],
        confirmed_at=data.get("confirmedAt"),
    )


@router.post("/upload", response_model=ReceiptResponse, status_code=status.HTTP_201_CREATED)
async def upload_receipt(
    file: UploadFile = File(...),
    user: dict = Depends(get_current_user),
):
    """Upload a receipt image, run OCR, return extracted data as pending receipt."""
    file_bytes = await file.read()
    content_type = file.content_type or "image/jpeg"

    # Upload to GCS
    storage_path = _upload_image_to_gcs(file_bytes, content_type)

    # Create receipt doc in "processing" state
    now = datetime.now(timezone.utc)
    doc_ref = db.collection("receipts").document()
    doc_data = {
        "ownerUid": user["uid"],
        "projectId": None,
        "status": "processing",
        "imageStoragePath": storage_path,
        "extracted": {},
        "hasValidationWarning": False,
        "ocrError": None,
        "createdAt": now,
        "confirmedAt": None,
    }
    doc_ref.set(doc_data)

    # Run OCR
    try:
        extracted = _extract_receipt_with_gemini(file_bytes, content_type)
        has_warning = _check_validation(extracted)

        doc_ref.update({
            "status": "pending",
            "extracted": extracted,
            "hasValidationWarning": has_warning,
        })
        doc_data["status"] = "pending"
        doc_data["extracted"] = extracted
        doc_data["hasValidationWarning"] = has_warning
    except Exception as e:
        logger.exception("OCR failed for receipt %s", doc_ref.id)
        doc_ref.update({
            "status": "failed",
            "ocrError": str(e),
        })
        doc_data["status"] = "failed"
        doc_data["ocrError"] = str(e)

    return _doc_to_receipt(doc_ref.id, doc_data)


@router.get("/{receipt_id}/image")
async def get_receipt_image(receipt_id: str, user: dict = Depends(get_current_user)):
    """Stream receipt image from GCS."""
    from fastapi.responses import Response

    doc = db.collection("receipts").document(receipt_id).get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Receipt not found")
    data = doc.to_dict()
    if data["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Receipt not found")

    storage_path = data.get("imageStoragePath")
    if not storage_path:
        raise HTTPException(status_code=404, detail="No image")

    blob = bucket.blob(storage_path)
    image_bytes = blob.download_as_bytes()
    content_type = blob.content_type or "image/jpeg"
    return Response(content=image_bytes, media_type=content_type)


@router.post("/{receipt_id}/confirm", response_model=ReceiptResponse)
async def confirm_receipt(
    receipt_id: str,
    body: ReceiptConfirm,
    user: dict = Depends(get_current_user),
):
    """Confirm a pending receipt and assign it to a project."""
    doc_ref = db.collection("receipts").document(receipt_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Receipt not found")
    data = doc.to_dict()
    if data["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Receipt not found")

    # Verify project exists and belongs to user
    project_doc = db.collection("projects").document(body.project_id).get()
    if not project_doc.exists or project_doc.to_dict()["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=400, detail="Invalid project")

    now = datetime.now(timezone.utc)
    doc_ref.update({
        "projectId": body.project_id,
        "status": "confirmed",
        "confirmedAt": now,
    })

    # Update project's lastReceiptAddedAt
    db.collection("projects").document(body.project_id).update({
        "lastReceiptAddedAt": now,
        "updatedAt": now,
    })

    data["projectId"] = body.project_id
    data["status"] = "confirmed"
    data["confirmedAt"] = now
    return _doc_to_receipt(receipt_id, data)


@router.patch("/{receipt_id}", response_model=ReceiptResponse)
async def update_receipt(
    receipt_id: str,
    body: ReceiptUpdate,
    user: dict = Depends(get_current_user),
):
    """Edit extracted fields or move receipt between projects."""
    doc_ref = db.collection("receipts").document(receipt_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Receipt not found")
    data = doc.to_dict()
    if data["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Receipt not found")

    updates = {}
    extracted = data.get("extracted", {})

    if body.project_id is not None:
        # Verify new project
        project_doc = db.collection("projects").document(body.project_id).get()
        if not project_doc.exists or project_doc.to_dict()["ownerUid"] != user["uid"]:
            raise HTTPException(status_code=400, detail="Invalid project")
        updates["projectId"] = body.project_id

    if body.vendor is not None:
        extracted["vendor"] = body.vendor
    if body.date is not None:
        extracted["date"] = body.date
    if body.subtotal is not None:
        extracted["subtotal"] = body.subtotal
    if body.hst is not None:
        extracted["hst"] = body.hst
    if body.total is not None:
        extracted["total"] = body.total

    updates["extracted"] = extracted
    updates["hasValidationWarning"] = _check_validation(extracted)

    doc_ref.update(updates)
    data.update(updates)
    return _doc_to_receipt(receipt_id, data)


@router.delete("/{receipt_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_receipt(receipt_id: str, user: dict = Depends(get_current_user)):
    """Delete a receipt and its image from GCS."""
    doc_ref = db.collection("receipts").document(receipt_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Receipt not found")
    data = doc.to_dict()
    if data["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Receipt not found")

    # Delete image from GCS
    storage_path = data.get("imageStoragePath")
    if storage_path:
        blob = bucket.blob(storage_path)
        blob.delete()

    doc_ref.delete()


@router.post("/{receipt_id}/retry", response_model=ReceiptResponse)
async def retry_ocr(receipt_id: str, user: dict = Depends(get_current_user)):
    """Retry OCR on a failed receipt."""
    doc_ref = db.collection("receipts").document(receipt_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Receipt not found")
    data = doc.to_dict()
    if data["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Receipt not found")
    if data["status"] != "failed":
        raise HTTPException(status_code=400, detail="Receipt is not in failed state")

    # Re-download image from GCS and retry OCR
    storage_path = data["imageStoragePath"]
    blob = bucket.blob(storage_path)
    file_bytes = blob.download_as_bytes()
    content_type = blob.content_type or "image/jpeg"

    doc_ref.update({"status": "processing", "ocrError": None})

    try:
        extracted = _extract_receipt_with_gemini(file_bytes, content_type)
        has_warning = _check_validation(extracted)
        doc_ref.update({
            "status": "pending",
            "extracted": extracted,
            "hasValidationWarning": has_warning,
        })
        data["status"] = "pending"
        data["extracted"] = extracted
        data["hasValidationWarning"] = has_warning
        data["ocrError"] = None
    except Exception as e:
        doc_ref.update({"status": "failed", "ocrError": str(e)})
        data["status"] = "failed"
        data["ocrError"] = str(e)

    return _doc_to_receipt(receipt_id, data)


@router.get("", response_model=list[ReceiptResponse])
async def list_receipts(
    project_id: Optional[str] = None,
    receipt_status: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """List receipts with optional filters."""
    query = db.collection("receipts").where(
        filter=FieldFilter("ownerUid", "==", user["uid"])
    )

    if project_id:
        query = query.where(filter=FieldFilter("projectId", "==", project_id))
    if receipt_status:
        query = query.where(filter=FieldFilter("status", "==", receipt_status))

    receipts = []
    for doc in query.stream():
        data = doc.to_dict()
        # Client-side date filtering (Firestore can't filter on nested fields easily)
        if date_from or date_to:
            receipt_date = data.get("extracted", {}).get("date")
            if receipt_date:
                if date_from and receipt_date < date_from:
                    continue
                if date_to and receipt_date > date_to:
                    continue
        receipts.append(_doc_to_receipt(doc.id, data))

    return receipts
