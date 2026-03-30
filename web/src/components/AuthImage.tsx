import { useEffect, useState } from "react";
import { auth } from "../lib/firebase";

export default function AuthImage({
  src,
  alt,
  className,
}: {
  src: string;
  alt: string;
  className?: string;
}) {
  const [blobUrl, setBlobUrl] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function fetchImage() {
      try {
        const token = await auth.currentUser?.getIdToken();
        const res = await fetch(`/api${src}`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok || cancelled) return;
        const blob = await res.blob();
        if (!cancelled) setBlobUrl(URL.createObjectURL(blob));
      } catch {
        // ignore
      }
    }

    fetchImage();
    return () => {
      cancelled = true;
      if (blobUrl) URL.revokeObjectURL(blobUrl);
    };
  }, [src]);

  if (!blobUrl) return <div className={`${className} bg-gray-100 animate-pulse`} />;
  return <img src={blobUrl} alt={alt} className={className} />;
}
