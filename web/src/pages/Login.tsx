import { useAuth } from "../lib/auth";
import { Navigate } from "react-router-dom";

export default function Login() {
  const { user, loading, signIn } = useAuth();

  if (loading) return <div className="flex items-center justify-center h-screen">Loading...</div>;
  if (user) return <Navigate to="/" replace />;

  return (
    <div className="flex items-center justify-center h-screen bg-gray-50">
      <div className="text-center space-y-6">
        <h1 className="text-3xl font-bold text-gray-900">Maplewood</h1>
        <p className="text-gray-600">Construction Project Management</p>
        <button
          onClick={signIn}
          className="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition cursor-pointer"
        >
          Sign in with Google
        </button>
      </div>
    </div>
  );
}
