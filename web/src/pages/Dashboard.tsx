import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { listProjects, listReceipts, createProject, type Project } from "../lib/api";
import { Link } from "react-router-dom";
import { useState } from "react";

function fmt(n: number) {
  return n.toLocaleString("en-CA", { style: "currency", currency: "CAD" });
}

function NewProjectForm({ onClose }: { onClose: () => void }) {
  const queryClient = useQueryClient();
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");

  const mutation = useMutation({
    mutationFn: () => createProject({ name, address }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      onClose();
    },
  });

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 space-y-3">
      <input
        placeholder="Project name"
        value={name}
        onChange={(e) => setName(e.target.value)}
        className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
        autoFocus
      />
      <input
        placeholder="Address (optional)"
        value={address}
        onChange={(e) => setAddress(e.target.value)}
        className="w-full border border-gray-300 rounded px-3 py-2 text-sm"
      />
      <div className="flex gap-2">
        <button
          onClick={() => mutation.mutate()}
          disabled={!name.trim() || mutation.isPending}
          className="px-4 py-2 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 cursor-pointer"
        >
          {mutation.isPending ? "Creating..." : "Create"}
        </button>
        <button onClick={onClose} className="px-4 py-2 text-sm text-gray-600 cursor-pointer">
          Cancel
        </button>
      </div>
    </div>
  );
}

function ProjectCard({ project }: { project: Project }) {
  return (
    <Link
      to={`/projects/${project.id}`}
      className="block bg-white border border-gray-200 rounded-lg p-4 hover:border-blue-300 transition"
    >
      <div className="flex justify-between items-start">
        <div>
          <h3 className="font-medium text-gray-900">{project.name}</h3>
          {project.address && (
            <p className="text-sm text-gray-500 mt-1">{project.address}</p>
          )}
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
      <div className="mt-4 grid grid-cols-3 gap-4 text-sm">
        <div>
          <p className="text-gray-500">Materials</p>
          <p className="font-medium">{fmt(project.subtotal_sum)}</p>
        </div>
        <div>
          <p className="text-gray-500">HST (ITC)</p>
          <p className="font-medium">{fmt(project.hst_sum)}</p>
        </div>
        <div>
          <p className="text-gray-500">Receipts</p>
          <p className="font-medium">{project.receipt_count}</p>
        </div>
      </div>
    </Link>
  );
}

export default function Dashboard() {
  const [showNew, setShowNew] = useState(false);
  const { data: projects, isLoading } = useQuery({
    queryKey: ["projects"],
    queryFn: () => listProjects(),
  });
  const { data: pending } = useQuery({
    queryKey: ["receipts", "pending"],
    queryFn: () => listReceipts({ receipt_status: "pending" }),
  });

  const pendingCount = pending?.length ?? 0;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Projects</h1>
        <div className="flex items-center gap-4">
          {pendingCount > 0 && (
            <Link
              to="/pending"
              className="text-sm bg-amber-100 text-amber-700 px-3 py-1.5 rounded-full"
            >
              {pendingCount} pending receipt{pendingCount !== 1 ? "s" : ""}
            </Link>
          )}
          <button
            onClick={() => setShowNew(true)}
            className="px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 cursor-pointer"
          >
            New Project
          </button>
        </div>
      </div>

      {showNew && <NewProjectForm onClose={() => setShowNew(false)} />}

      {isLoading ? (
        <p className="text-gray-500">Loading...</p>
      ) : projects?.length === 0 ? (
        <p className="text-gray-500">No projects yet. Create one to get started.</p>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {projects?.map((p) => <ProjectCard key={p.id} project={p} />)}
        </div>
      )}
    </div>
  );
}
