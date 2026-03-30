import csv
import io
import zipfile
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from google.cloud import storage
from google.cloud.firestore_v1 import FieldFilter

from app.auth import get_current_user
from app.config import settings
from app.db import db

router = APIRouter(prefix="/export", tags=["export"])

storage_client = storage.Client(project=settings.gcp_project_id)
bucket = storage_client.bucket(settings.receipt_images_bucket)


def _get_filtered_receipts(
    user_uid: str,
    project_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> list[dict]:
    """Fetch confirmed receipts matching filters."""
    query = db.collection("receipts").where(
        filter=FieldFilter("ownerUid", "==", user_uid)
    ).where(
        filter=FieldFilter("status", "==", "confirmed")
    )

    if project_id:
        query = query.where(filter=FieldFilter("projectId", "==", project_id))

    results = []
    for doc in query.stream():
        data = doc.to_dict()
        data["_id"] = doc.id

        # Client-side date filtering
        if date_from or date_to:
            receipt_date = data.get("extracted", {}).get("date", "")
            if receipt_date:
                if date_from and receipt_date < date_from:
                    continue
                if date_to and receipt_date > date_to:
                    continue

        results.append(data)

    return results


def _get_project_name(project_id: str) -> str:
    """Look up project name by ID."""
    doc = db.collection("projects").document(project_id).get()
    if doc.exists:
        return doc.to_dict().get("name", "Unknown")
    return "Unknown"


@router.get("/csv")
async def export_csv(
    project_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """Export receipts as CSV."""
    receipts = _get_filtered_receipts(user["uid"], project_id, date_from, date_to)

    # Build project name cache
    project_names: dict[str, str] = {}
    for r in receipts:
        pid = r.get("projectId")
        if pid and pid not in project_names:
            project_names[pid] = _get_project_name(pid)

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["Date", "Vendor", "Project", "Subtotal", "HST", "Total"])

    for r in receipts:
        ext = r.get("extracted", {})
        writer.writerow([
            ext.get("date", ""),
            ext.get("vendor", ""),
            project_names.get(r.get("projectId", ""), ""),
            ext.get("subtotal", ""),
            ext.get("hst", ""),
            ext.get("total", ""),
        ])

    output.seek(0)
    timestamp = datetime.utcnow().strftime("%Y%m%d")
    filename = f"receipts_{timestamp}.csv"

    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


@router.get("/images")
async def export_images(
    project_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """Export receipt images as a zip file."""
    receipts = _get_filtered_receipts(user["uid"], project_id, date_from, date_to)

    if not receipts:
        raise HTTPException(status_code=404, detail="No receipts found for the given filters")

    # Build project name cache
    project_names: dict[str, str] = {}
    for r in receipts:
        pid = r.get("projectId")
        if pid and pid not in project_names:
            project_names[pid] = _get_project_name(pid)

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for r in receipts:
            storage_path = r.get("imageStoragePath")
            if not storage_path:
                continue

            blob = bucket.blob(storage_path)
            try:
                image_bytes = blob.download_as_bytes()
            except Exception:
                continue

            # Organize by project folder
            ext = r.get("extracted", {})
            project_name = project_names.get(r.get("projectId", ""), "Unassigned")
            # Sanitize folder name
            project_name = "".join(c for c in project_name if c.isalnum() or c in " -_").strip()
            date_str = ext.get("date", "unknown")
            vendor = ext.get("vendor", "unknown")
            vendor = "".join(c for c in vendor if c.isalnum() or c in " -_").strip()

            # Guess extension from storage path or default to jpg
            file_ext = "jpg"
            if "." in storage_path:
                file_ext = storage_path.rsplit(".", 1)[-1]

            filename = f"{project_name}/{date_str}_{vendor}_{r['_id'][:8]}.{file_ext}"
            zf.writestr(filename, image_bytes)

    zip_buffer.seek(0)
    timestamp = datetime.utcnow().strftime("%Y%m%d")

    return StreamingResponse(
        iter([zip_buffer.getvalue()]),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename=receipts_{timestamp}.zip"},
    )


@router.get("/summary")
async def export_summary(
    project_id: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    """Export a summary as plain text (PDF generation can be added later)."""
    receipts = _get_filtered_receipts(user["uid"], project_id, date_from, date_to)

    # Group by project
    by_project: dict[str, list[dict]] = {}
    for r in receipts:
        pid = r.get("projectId", "unassigned")
        by_project.setdefault(pid, []).append(r)

    # Build project name cache
    project_names: dict[str, str] = {}
    for pid in by_project:
        if pid != "unassigned":
            project_names[pid] = _get_project_name(pid)

    lines = []
    lines.append("RECEIPT SUMMARY")
    lines.append(f"Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}")
    if date_from or date_to:
        lines.append(f"Date range: {date_from or 'start'} to {date_to or 'present'}")
    lines.append("")

    grand_subtotal = 0.0
    grand_hst = 0.0
    grand_total = 0.0

    for pid, project_receipts in by_project.items():
        name = project_names.get(pid, "Unassigned")
        lines.append(f"{'='*60}")
        lines.append(f"Project: {name}")
        lines.append(f"{'='*60}")

        proj_subtotal = 0.0
        proj_hst = 0.0
        proj_total = 0.0

        for r in project_receipts:
            ext = r.get("extracted", {})
            s = ext.get("subtotal", 0) or 0
            h = ext.get("hst", 0) or 0
            t = ext.get("total", 0) or 0
            proj_subtotal += s
            proj_hst += h
            proj_total += t

            lines.append(
                f"  {ext.get('date', 'N/A'):12s} "
                f"{ext.get('vendor', 'N/A'):30s} "
                f"${s:>9.2f}  "
                f"${h:>7.2f}  "
                f"${t:>9.2f}"
            )

        lines.append(f"  {'':12s} {'':30s} {'─'*30}")
        lines.append(
            f"  {'':12s} {'Project Total':30s} "
            f"${proj_subtotal:>9.2f}  "
            f"${proj_hst:>7.2f}  "
            f"${proj_total:>9.2f}"
        )
        lines.append(f"  Receipts: {len(project_receipts)}")
        lines.append("")

        grand_subtotal += proj_subtotal
        grand_hst += proj_hst
        grand_total += proj_total

    lines.append(f"{'='*60}")
    lines.append(
        f"GRAND TOTAL: "
        f"Subtotal ${grand_subtotal:,.2f}  "
        f"HST ${grand_hst:,.2f}  "
        f"Total ${grand_total:,.2f}"
    )
    lines.append(f"Total receipts: {len(receipts)}")
    lines.append(f"Total ITC (HST) claimable: ${grand_hst:,.2f}")

    content = "\n".join(lines)
    timestamp = datetime.utcnow().strftime("%Y%m%d")

    return StreamingResponse(
        iter([content]),
        media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename=summary_{timestamp}.txt"},
    )
