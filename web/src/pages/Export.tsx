import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { listProjects, getExportUrl } from "../lib/api";
import { auth } from "../lib/firebase";

async function downloadWithAuth(url: string, filename: string) {
  const token = await auth.currentUser?.getIdToken();
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error("Export failed");
  const blob = await res.blob();
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

export default function Export() {
  const [projectId, setProjectId] = useState("");
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [downloading, setDownloading] = useState<string | null>(null);

  const { data: projects } = useQuery({
    queryKey: ["projects"],
    queryFn: () => listProjects(),
  });

  const params = {
    project_id: projectId || undefined,
    date_from: dateFrom || undefined,
    date_to: dateTo || undefined,
  };

  async function handleDownload(type: "csv" | "images" | "summary") {
    setDownloading(type);
    try {
      const url = getExportUrl(type, params);
      const ext = type === "csv" ? "csv" : type === "images" ? "zip" : "txt";
      await downloadWithAuth(url, `receipts.${ext}`);
    } catch (e) {
      alert(`Export failed: ${e}`);
    } finally {
      setDownloading(null);
    }
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Export</h1>

      <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-4">
        <h2 className="font-medium text-gray-900">Filters</h2>
        <div className="grid grid-cols-3 gap-4">
          <div>
            <label className="block text-sm text-gray-600 mb-1">Project</label>
            <select
              value={projectId}
              onChange={(e) => setProjectId(e.target.value)}
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
            >
              <option value="">All projects</option>
              {projects?.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm text-gray-600 mb-1">From</label>
            <input
              type="date"
              value={dateFrom}
              onChange={(e) => setDateFrom(e.target.value)}
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="block text-sm text-gray-600 mb-1">To</label>
            <input
              type="date"
              value={dateTo}
              onChange={(e) => setDateTo(e.target.value)}
              className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
            />
          </div>
        </div>
      </div>

      <div className="flex gap-3">
        <button
          onClick={() => handleDownload("csv")}
          disabled={downloading !== null}
          className="px-4 py-2 bg-green-600 text-white text-sm rounded-lg hover:bg-green-700 disabled:opacity-50 cursor-pointer"
        >
          {downloading === "csv" ? "Downloading..." : "Download CSV"}
        </button>
        <button
          onClick={() => handleDownload("images")}
          disabled={downloading !== null}
          className="px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 disabled:opacity-50 cursor-pointer"
        >
          {downloading === "images" ? "Downloading..." : "Download Images (ZIP)"}
        </button>
        <button
          onClick={() => handleDownload("summary")}
          disabled={downloading !== null}
          className="px-4 py-2 bg-purple-600 text-white text-sm rounded-lg hover:bg-purple-700 disabled:opacity-50 cursor-pointer"
        >
          {downloading === "summary" ? "Downloading..." : "Download Summary"}
        </button>
      </div>
    </div>
  );
}
