from datetime import datetime
from typing import Optional

from pydantic import BaseModel


# --- Projects ---


class ProjectCreate(BaseModel):
    name: str
    description: str = ""
    address: str = ""


class ProjectUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    address: Optional[str] = None
    status: Optional[str] = None  # "active" | "completed"


class ProjectResponse(BaseModel):
    id: str
    owner_uid: str
    name: str
    description: str
    address: str
    status: str
    created_at: datetime
    updated_at: datetime
    last_receipt_added_at: Optional[datetime] = None
    # Computed totals (from confirmed receipts)
    receipt_count: int = 0
    subtotal_sum: float = 0.0
    hst_sum: float = 0.0
    total_sum: float = 0.0


# --- Receipts ---


class ExtractedData(BaseModel):
    vendor: str = ""
    date: Optional[str] = None
    subtotal: Optional[float] = None
    hst: Optional[float] = None
    total: Optional[float] = None
    confidence: dict = {}  # per-field confidence scores


class ReceiptResponse(BaseModel):
    id: str
    owner_uid: str
    project_id: Optional[str] = None
    status: str  # uploading | processing | pending | failed | confirmed
    image_storage_path: str
    image_url: Optional[str] = None
    extracted: ExtractedData = ExtractedData()
    has_validation_warning: bool = False
    ocr_error: Optional[str] = None
    created_at: datetime
    confirmed_at: Optional[datetime] = None


class ReceiptConfirm(BaseModel):
    project_id: str


class ReceiptUpdate(BaseModel):
    project_id: Optional[str] = None
    vendor: Optional[str] = None
    date: Optional[str] = None
    subtotal: Optional[float] = None
    hst: Optional[float] = None
    total: Optional[float] = None
