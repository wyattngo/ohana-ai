import { useCallback, useState } from "react";
import "./App.css";
import { ChannelPicker } from "./screens/ChannelPicker";
import { InboxScreen } from "./screens/Inbox";
import { ReviewCard } from "./screens/ReviewCard";
import type { PendingReplyOut } from "./lib/api";

/**
 * GD0.5 Phase P1 shell — replaces the P0 placeholder ("Hello, Ohana Seller"). Screen
 * switching is plain React state, NOT `react-router-dom` (not an installed dependency, and
 * P1's ALLOWED_FILES doesn't cover `package.json`/lockfile — see the P1 ANCHOR report
 * "Judgment calls" for the routing tradeoff this decided against Hash/BrowserRouter).
 */

type Screen =
  | { name: "channel" }
  | { name: "inbox" }
  | { name: "review"; reply: PendingReplyOut };

interface ToastState {
  message: string;
  kind: "success" | "error";
}

const TOAST_DURATION_MS = 4000;

function App() {
  const [screen, setScreen] = useState<Screen>({ name: "channel" });
  const [toast, setToast] = useState<ToastState | null>(null);

  const showToast = useCallback((message: string, kind: ToastState["kind"]) => {
    setToast({ message, kind });
    window.setTimeout(() => {
      setToast((current) => (current?.message === message ? null : current));
    }, TOAST_DURATION_MS);
  }, []);

  const showError = useCallback((message: string) => showToast(message, "error"), [showToast]);

  return (
    <div className="ohana-app">
      {screen.name === "channel" && (
        <ChannelPicker
          onConnected={() => setScreen({ name: "inbox" })}
          onError={showError}
        />
      )}

      {screen.name === "inbox" && (
        <InboxScreen
          onOpenReply={(reply) => setScreen({ name: "review", reply })}
          onError={showError}
        />
      )}

      {screen.name === "review" && (
        <ReviewCard
          reply={screen.reply}
          onBack={() => setScreen({ name: "inbox" })}
          onDecided={(status) => {
            showToast(
              status === "approved"
                ? "Đã duyệt. Tin nhắn CHƯA được gửi cho khách — worker gửi tự động chưa được triển khai."
                : "Đã từ chối. Draft sẽ không gửi khách.",
              "success",
            );
            setScreen({ name: "inbox" });
          }}
          onError={showError}
        />
      )}

      {toast && (
        <div className={`toast toast-${toast.kind}`} role="status">
          {toast.message}
        </div>
      )}
    </div>
  );
}

export default App;
