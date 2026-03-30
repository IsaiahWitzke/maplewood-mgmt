import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  listReceipts,
  listProjects,
  confirmReceipt,
  retryReceipt,
  deleteReceipt,
  type Receipt,
  type Project,
} from "../lib/api";
import { useState } from "react";
import AuthImage from "../components/AuthImage";

function fmt(n: number | null | undefined) {
  if (n == null) return "—";
  return n.toLocaleString("en-CA", { style: "currency", currency: "CAD" });
}

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    uploading: "bg-gray-100 text-gray-600",
    processing: "bg-blue-100 text-blue-600",
    pending: "bg-amber-100 text-amber-700",
    failed: "bg-red-100 text-red-600",
  };
  return (
    <span className={`text-xs px-2 py-0.5 rounded ${colors[status] ?? "bg-gray-100"}`}>
      {status}
    </span>
  );
}

function ReceiptCard({
  receipt,
  projects,
}: {
  receipt: Receipt;
  projects: Project[];
}) {
  const queryClient = useQueryClient();
  const [selectedProject, setSelectedProject] = useState(
    projects[0]?.id ?? ""
  );

  const confirm = useMutation({
    mutationFn: () => confirmReceipt(receipt.id, selectedProject),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["receipts"] });
      queryClient.invalidateQueries({ queryKey: ["projects"] });
    },
  });

  const retry = useMutation({
    mutationFn: () => retryReceipt(receipt.id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["receipts"] }),
  });

  const remove = useMutation({
    mutationFn: () => deleteReceipt(receipt.id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["receipts"] }),
  });

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
      <div className="flex items-center justify-between">
        <StatusBadge status={receipt.status} />
        {receipt.has_validation_warning && (
          <span className="text-xs text-amber-600">⚠ Subtotal + HST ≠ Total</span>
        )}
      </div>

      {receipt.image_url && (
        <AuthImage
          src={receipt.image_url}
          alt="Receipt"
          className="w-full max-h-48 object-contain bg-gray-50 rounded"
        />
      )}

      <div className="grid grid-cols-2 gap-2 text-sm">
        <div>
          <span className="text-gray-500">Vendor:</span>{" "}
          {receipt.extracted.vendor || "—"}
        </div>
        <div>
          <span className="text-gray-500">Date:</span>{" "}
          {receipt.extracted.date ?? "—"}
        </div>
        <div>
          <span className="text-gray-500">Subtotal:</span>{" "}
          {fmt(receipt.extracted.subtotal)}
        </div>
        <div>
          <span className="text-gray-500">HST:</span>{" "}
          {fmt(receipt.extracted.hst)}
        </div>
        <div>
          <span className="text-gray-500">Total:</span>{" "}
          {fmt(receipt.extracted.total)}
        </div>
      </div>

      {receipt.ocr_error && (
        <p className="text-xs text-red-600 bg-red-50 p-2 rounded">
          Error: {receipt.ocr_error}
        </p>
      )}

      {(receipt.status === "pending" || receipt.status === "failed") && (
        <div className="flex items-center gap-2">
          {receipt.status === "pending" && (
            <>
              <select
                value={selectedProject}
                onChange={(e) => setSelectedProject(e.target.value)}
                className="flex-1 border border-gray-300 rounded px-2 py-1.5 text-sm"
              >
                {projects.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
              <button
                onClick={() => confirm.mutate()}
                disabled={!selectedProject || confirm.isPending}
                className="px-3 py-1.5 bg-green-600 text-white text-sm rounded hover:bg-green-700 disabled:opacity-50 cursor-pointer"
              >
                {confirm.isPending ? "..." : "Confirm"}
              </button>
            </>
          )}
          {receipt.status === "failed" && (
            <button
              onClick={() => retry.mutate()}
              disabled={retry.isPending}
              className="px-3 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 cursor-pointer"
            >
              {retry.isPending ? "..." : "Retry OCR"}
            </button>
          )}
          <button
            onClick={() => remove.mutate()}
            disabled={remove.isPending}
            className="px-3 py-1.5 text-sm text-red-600 hover:text-red-800 cursor-pointer"
          >
            Delete
          </button>
        </div>
      )}
    </div>
  );
}

export default function PendingQueue() {
  const { data: receipts, isLoading: rcptsLoading } = useQuery({
    queryKey: ["receipts", "pending-all"],
    queryFn: async () => {
      const [pending, failed, processing] = await Promise.all([
        listReceipts({ receipt_status: "pending" }),
        listReceipts({ receipt_status: "failed" }),
        listReceipts({ receipt_status: "processing" }),
      ]);
      return [...processing, ...pending, ...failed];
    },
  });

  const { data: projects } = useQuery({
    queryKey: ["projects"],
    queryFn: () => listProjects(),
  });

  if (rcptsLoading) return <p className="text-gray-500">Loading...</p>;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Pending Receipts</h1>

      {!receipts || receipts.length === 0 ? (
        <p className="text-gray-500">No pending receipts. All caught up!</p>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {receipts.map((r) => (
            <ReceiptCard key={r.id} receipt={r} projects={projects ?? []} />
          ))}
        </div>
      )}
    </div>
  );
}
