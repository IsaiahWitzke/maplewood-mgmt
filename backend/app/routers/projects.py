from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from google.cloud.firestore_v1 import FieldFilter

from app.auth import get_current_user
from app.db import db
from app.models import ProjectCreate, ProjectResponse, ProjectUpdate

router = APIRouter(prefix="/projects", tags=["projects"])


def _compute_project_totals(project_id: str) -> dict:
    """Compute receipt totals for a project from confirmed receipts."""
    receipts = (
        db.collection("receipts")
        .where(filter=FieldFilter("projectId", "==", project_id))
        .where(filter=FieldFilter("status", "==", "confirmed"))
        .stream()
    )

    count = 0
    subtotal_sum = 0.0
    hst_sum = 0.0
    total_sum = 0.0

    for r in receipts:
        data = r.to_dict()
        extracted = data.get("extracted", {})
        count += 1
        subtotal_sum += extracted.get("subtotal", 0) or 0
        hst_sum += extracted.get("hst", 0) or 0
        total_sum += extracted.get("total", 0) or 0

    return {
        "receipt_count": count,
        "subtotal_sum": round(subtotal_sum, 2),
        "hst_sum": round(hst_sum, 2),
        "total_sum": round(total_sum, 2),
    }


def _doc_to_project(doc_id: str, data: dict, include_totals: bool = True) -> ProjectResponse:
    """Convert Firestore doc to ProjectResponse."""
    totals = _compute_project_totals(doc_id) if include_totals else {}
    return ProjectResponse(
        id=doc_id,
        owner_uid=data["ownerUid"],
        name=data["name"],
        description=data.get("description", ""),
        address=data.get("address", ""),
        status=data.get("status", "active"),
        created_at=data["createdAt"],
        updated_at=data.get("updatedAt", data["createdAt"]),
        last_receipt_added_at=data.get("lastReceiptAddedAt"),
        **totals,
    )


@router.post("", response_model=ProjectResponse, status_code=status.HTTP_201_CREATED)
async def create_project(body: ProjectCreate, user: dict = Depends(get_current_user)):
    now = datetime.now(timezone.utc)
    doc_ref = db.collection("projects").document()
    doc_data = {
        "ownerUid": user["uid"],
        "name": body.name,
        "description": body.description,
        "address": body.address,
        "status": "active",
        "createdAt": now,
        "updatedAt": now,
        "lastReceiptAddedAt": None,
    }
    doc_ref.set(doc_data)
    return _doc_to_project(doc_ref.id, doc_data, include_totals=False)


@router.get("", response_model=list[ProjectResponse])
async def list_projects(
    status_filter: Optional[str] = None,
    user: dict = Depends(get_current_user),
):
    query = db.collection("projects").where(
        filter=FieldFilter("ownerUid", "==", user["uid"])
    )
    if status_filter:
        query = query.where(filter=FieldFilter("status", "==", status_filter))

    projects = []
    for doc in query.stream():
        projects.append(_doc_to_project(doc.id, doc.to_dict()))

    # Sort client-side to avoid Firestore composite index requirement
    projects.sort(key=lambda p: p.last_receipt_added_at or p.created_at, reverse=True)
    return projects


@router.get("/{project_id}", response_model=ProjectResponse)
async def get_project(project_id: str, user: dict = Depends(get_current_user)):
    doc = db.collection("projects").document(project_id).get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Project not found")
    data = doc.to_dict()
    if data["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Project not found")
    return _doc_to_project(doc.id, data)


@router.patch("/{project_id}", response_model=ProjectResponse)
async def update_project(
    project_id: str,
    body: ProjectUpdate,
    user: dict = Depends(get_current_user),
):
    doc_ref = db.collection("projects").document(project_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Project not found")
    data = doc.to_dict()
    if data["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Project not found")

    updates = {"updatedAt": datetime.now(timezone.utc)}
    if body.name is not None:
        updates["name"] = body.name
    if body.description is not None:
        updates["description"] = body.description
    if body.address is not None:
        updates["address"] = body.address
    if body.status is not None:
        updates["status"] = body.status

    doc_ref.update(updates)
    data.update(updates)
    return _doc_to_project(project_id, data)


@router.delete("/{project_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_project(project_id: str, user: dict = Depends(get_current_user)):
    doc_ref = db.collection("projects").document(project_id)
    doc = doc_ref.get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Project not found")
    if doc.to_dict()["ownerUid"] != user["uid"]:
        raise HTTPException(status_code=404, detail="Project not found")
    doc_ref.delete()
