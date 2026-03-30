import { useState, useCallback } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { uploadReceipt, type Receipt } from "../lib/api";
import { useNavigate } from "react-router-dom";

export default function Upload() {
  const [dragOver, setDragOver] = useState(false);
  const [result, setResult] = useState<Receipt | null>(null);
  const queryClient = useQueryClient();
  const navigate = useNavigate();

  const mutation = useMutation({
    mutationFn: uploadReceipt,
    onSuccess: (data) => {
      setResult(data);
      queryClient.invalidateQueries({ queryKey: ["receipts"] });
    },
  });

  const handleFiles = useCallback(
    (files: FileList | null) => {
      if (!files || files.length === 0) return;
      mutation.mutate(files[0]);
    },
    [mutation]
  );

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setDragOver(false);
      handleFiles(e.dataTransfer.files);
    },
    [handleFiles]
  );

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Upload Receipt</h1>

      <div
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={handleDrop}
        className={`border-2 border-dashed rounded-lg p-12 text-center transition ${
          dragOver
            ? "border-blue-400 bg-blue-50"
            : "border-gray-300 bg-white"
        }`}
      >
        {mutation.isPending ? (
          <div className="space-y-2">
            <p className="text-gray-600">Uploading & running OCR...</p>
            <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto" />
          </div>
        ) : (
          <div className="space-y-3">
            <p className="text-gray-600">Drag and drop a receipt image here, or</p>
            <label className="inline-block px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 cursor-pointer">
              Choose File
              <input
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => handleFiles(e.target.files)}
              />
            </label>
          </div>
        )}
      </div>

      {mutation.isError && (
        <p className="text-red-600 text-sm">
          Error: {mutation.error.message}
        </p>
      )}

      {result && (
        <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
          <h2 className="font-medium text-gray-900">Receipt uploaded!</h2>
          <div className="grid grid-cols-2 gap-2 text-sm">
            <div>
              <span className="text-gray-500">Status:</span> {result.status}
            </div>
            <div>
              <span className="text-gray-500">Vendor:</span>{" "}
              {result.extracted.vendor || "—"}
            </div>
            <div>
              <span className="text-gray-500">Date:</span>{" "}
              {result.extracted.date ?? "—"}
            </div>
            <div>
              <span className="text-gray-500">Total:</span>{" "}
              {result.extracted.total != null
                ? `$${result.extracted.total.toFixed(2)}`
                : "—"}
            </div>
          </div>
          <button
            onClick={() => navigate("/pending")}
            className="px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 cursor-pointer"
          >
            Go to Pending Queue to review
          </button>
        </div>
      )}
    </div>
  );
}
