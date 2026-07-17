import "./App.css";

/**
 * GD0.5 Phase P0 placeholder shell. Real screens (ChannelPicker / Inbox / ReviewCard) land
 * in Phase P1 (spec 04 §7) — this only proves the build pipeline + static mount + token
 * injection work end-to-end before P1 wires live data.
 */
function App() {
  return (
    <main className="ohana-shell">
      <h1>Hello, Ohana Seller</h1>
      <p>GĐ0.5 scaffold — seller screens land in Phase P1.</p>
    </main>
  );
}

export default App;
