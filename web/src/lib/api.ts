import { auth } from "./firebase";

const BASE_URL = "/api";

async function getHeaders(): Promise<HeadersInit> {
  const user = auth.currentUser;
  if (!user) throw new Error("Not authenticated");
  const token = await user.getIdToken();
  return {
    Authorization: `Bearer ${token}`,
  };
}

async function request<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const headers = await getHeaders();
  const res = await fetch(`${BASE_URL}${path}`, {
    ...options,
    headers: { ...headers, ...options.headers },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API ${res.status}: ${body}`);
  }
  if (res.status === 204) return undefined as T;
  return res.json();
}

// --- Projects ---

export interface Project {
  id: string;
  owner_uid: string;
  name: string;
  description: string;
  address: string;
  status: string;
  created_at: string;
  updated_at: string;
  last_receipt_added_at: string | null;
  receipt_count: number;
  subtotal_sum: number;
  hst_sum: number;
  total_sum: number;
}

export function listProjects(status?: string) {
  const params = status ? `?status_filter=${status}` : "";
  return request<Project[]>(`/projects${params}`);
}

export function getProject(id: string) {
  return request<Project>(`/projects/${id}`);
}

export function createProject(data: { name: string; description?: string; address?: string }) {
  return request<Project>("/projects", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
}

export function updateProject(id: string, data: Record<string, unknown>) {
  return request<Project>(`/projects/${id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
}

export function deleteProject(id: string) {
  return request<void>(`/projects/${id}`, { method: "DELETE" });
}

// --- Receipts ---

export interface ExtractedData {
  vendor: string;
  date: string | null;
  subtotal: number | null;
  hst: number | null;
  total: number | null;
  confidence: Record<string, number>;
}

export interface Receipt {
  id: string;
  owner_uid: string;
  project_id: string | null;
  status: string;
  image_storage_path: string;
  image_url: string | null;
  extracted: ExtractedData;
  has_validation_warning: boolean;
  ocr_error: string | null;
  created_at: string;
  confirmed_at: string | null;
}

export function listReceipts(params?: {
  project_id?: string;
  receipt_status?: string;
  date_from?: string;
  date_to?: string;
}) {
  const searchParams = new URLSearchParams();
  if (params?.project_id) searchParams.set("project_id", params.project_id);
  if (params?.receipt_status) searchParams.set("receipt_status", params.receipt_status);
  if (params?.date_from) searchParams.set("date_from", params.date_from);
  if (params?.date_to) searchParams.set("date_to", params.date_to);
  const qs = searchParams.toString();
  return request<Receipt[]>(`/receipts${qs ? `?${qs}` : ""}`);
}

export function uploadReceipt(file: File) {
  const formData = new FormData();
  formData.append("file", file);
  return request<Receipt>("/receipts/upload", {
    method: "POST",
    body: formData,
  });
}

export function confirmReceipt(id: string, projectId: string) {
  return request<Receipt>(`/receipts/${id}/confirm`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ project_id: projectId }),
  });
}

export function updateReceipt(id: string, data: Record<string, unknown>) {
  return request<Receipt>(`/receipts/${id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
}

export function deleteReceipt(id: string) {
  return request<void>(`/receipts/${id}`, { method: "DELETE" });
}

export function retryReceipt(id: string) {
  return request<Receipt>(`/receipts/${id}/retry`, { method: "POST" });
}

// --- Export ---

export function getExportUrl(
  type: "csv" | "images" | "summary",
  params?: { project_id?: string; date_from?: string; date_to?: string }
) {
  const searchParams = new URLSearchParams();
  if (params?.project_id) searchParams.set("projectId", params.project_id);
  if (params?.date_from) searchParams.set("dateFrom", params.date_from);
  if (params?.date_to) searchParams.set("dateTo", params.date_to);
  const qs = searchParams.toString();
  return `${BASE_URL}/export/${type}${qs ? `?${qs}` : ""}`;
}
