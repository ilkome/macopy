import { useReveal } from "./useReveal";

const KEYS: [string, string][] = [
  ["⌘`", "Show / hide panel (configurable)"],
  ["↑ ↓", "Navigate the list"],
  ["← →", "Switch tabs"],
  ["↵", "Paste into the previous app"],
  ["⇧ ↵", "Copy without pasting"],
  ["⌘ S", "Toggle favorite"],
  ["⌘ E", "Edit comment"],
  ["⌘ ⌫", "Delete from history"],
  ["Space", "Quick Look for images"],
  ["Esc", "Hide the panel"],
];

export function Hotkeys() {
  const head = useReveal<HTMLDivElement>();
  const grid = useReveal<HTMLDivElement>(80);
  return (
    <section
      id="shortcuts"
      style={{
        background: "var(--color-tile-1)",
        color: "#fff",
        padding: "clamp(72px, 10vw, 112px) 0",
      }}
    >
      <div style={{ maxWidth: 1080, margin: "0 auto", padding: "0 24px" }}>
        <div
          ref={head}
          className="reveal"
          style={{ maxWidth: "26ch", marginBottom: 48 }}
        >
          <h2 className="t-display">Built for hands that never leave the keyboard.</h2>
          <p className="t-body" style={{ color: "var(--color-body-muted)", marginTop: 16 }}>
            Open, search, paste - the whole loop happens before your fingers
            reach the trackpad.
          </p>
        </div>

        <div
          ref={grid}
          className="reveal hotkey-grid"
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
            columnGap: 56,
          }}
        >
          {KEYS.map(([k, action], i) => (
            <div
              key={k}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 16,
                padding: "15px 0",
                borderTop: i < 2 ? "none" : "1px solid rgba(255,255,255,0.08)",
              }}
            >
              <span style={{ display: "flex", gap: 6, flex: "0 0 96px" }}>
                {k.split(" ").map((part, j) => (
                  <kbd key={j} className="kbd">
                    {part}
                  </kbd>
                ))}
              </span>
              <span className="t-body" style={{ color: "var(--color-body-muted)" }}>
                {action}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
