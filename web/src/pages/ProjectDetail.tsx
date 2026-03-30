import { useParams, Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getProject, listReceipts, type Receipt } from "../lib/api";

function fmt(n: number | null | undefined) {
  if (n == null) return "—";
  return n.toLocaleString("en-CA", { style: "currency", currency: "CAD" });
}

function ReceiptTable({ receipts }: { receipts: Receipt[] }) {
  const subtotalSum = receipts.reduce((s, r) => s + (r.extracted.subtotal ?? 0), 0);
  const hstSum = receipts.reduce((s, r) => s + (r.extracted.hst ?? 0), 0);
  const totalSum = receipts.reduce((s, r) => s + (r.extracted.total ?? 0), 0);

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-200 text-left text-gray-500">
            <th className="py-2 pr-4 font-medium">Date</th>
            <th className="py-2 pr-4 font-medium">Vendor</th>
            <th className="py-2 pr-4 font-medium text-right">Subtotal</th>
            <th className="py-2 pr-4 font-medium text-right">HST</th>
            <th className="py-2 pr-4 font-medium text-right">Total</th>
            <th className="py-2 font-medium">Status</th>
          </tr>
        </thead>
        <tbody>
          {receipts.map((r) => (
            <tr
              key={r.id}
              className={`border-b border-gray-100 ${
                r.has_validation_warning ? "bg-amber-50" : ""
              }`}
            >
              <td className="py-2 pr-4">{r.extracted.date ?? "—"}</td>
              <td className="py-2 pr-4">{r.extracted.vendor || "—"}</td>
              <td className="py-2 pr-4 text-right font-mono">{fmt(r.extracted.subtotal)}</td>
              <td className="py-2 pr-4 text-right font-mono">{fmt(r.extracted.hst)}</td>
              <td className="py-2 pr-4 text-right font-mono">{fmt(r.extracted.total)}</td>
              <td className="py-2">
                {r.has_validation_warning && (
                  <span className="text-amber-600 text-xs mr-1" title="Subtotal + HST ≠ Total">
                    ⚠
                  </span>
                )}
                <span className="text-xs text-gray-500">{r.status}</span>
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-gray-300 font-medium">
            <td className="py-2 pr-4" colSpan={2}>
              Total ({receipts.length} receipts)
            </td>
            <td className="py-2 pr-4 text-right font-mono">{fmt(subtotalSum)}</td>
            <td className="py-2 pr-4 text-right font-mono">{fmt(hstSum)}</td>
            <td className="py-2 pr-4 text-right font-mono">{fmt(totalSum)}</td>
            <td></td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}

export default function ProjectDetail() {
  const { id } = useParams<{ id: string }>();

  const { data: project, isLoading: projLoading } = useQuery({
    queryKey: ["projects", id],
    queryFn: () => getProject(id!),
    enabled: !!id,
  });

  const { data: receipts, isLoading: rcptsLoading } = useQuery({
    queryKey: ["receipts", { project_id: id }],
    queryFn: () => listReceipts({ project_id: id }),
    enabled: !!id,
  });

  if (projLoading || rcptsLoading) return <p className="text-gray-500">Loading...</p>;
  if (!project) return <p className="text-gray-500">Project not found.</p>;

  return (
    <div className="space-y-6">
      <div>
        <Link to="/" className="text-sm text-blue-600 hover:underline">
          ← Back to projects
        </Link>
      </div>

      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{project.name}</h1>
          {project.address && <p className="text-gray-500 mt-1">{project.address}</p>}
        </div>
        <span
          className={`text-xs px-2 py-1 rounded ${
            project.status === "active"
              ? "bg-green-100 text-green-700"
              : "bg-gray-100 text-gray-600"
          }`}
        >
          {project.status}
        </span>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-sm text-gray-500">Materials (Subtotal)</p>
          <p className="text-xl font-bold">{fmt(project.subtotal_sum)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-sm text-gray-500">HST (ITC)</p>
          <p className="text-xl font-bold">{fmt(project.hst_sum)}</p>
        </div>
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <p className="text-sm text-gray-500">Total</p>
          <p className="text-xl font-bold">{fmt(project.total_sum)}</p>
        </div>
      </div>

      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <h2 className="text-lg font-medium text-gray-900 mb-4">Receipts</h2>
        {receipts && receipts.length > 0 ? (
          <ReceiptTable receipts={receipts} />
        ) : (
          <p className="text-gray-500 text-sm">No receipts yet.</p>
        )}
      </div>
    </div>
  );
}
