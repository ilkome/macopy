import { useReveal } from "./useReveal";
import { REPO } from "./links";

const POINTS = [
  "No accounts",
  "No telemetry",
  "No cloud sync",
  "On-device OCR",
];

export function Privacy() {
  const ref = useReveal<HTMLDivElement>();
  return (
    <section
      style={{
        background: "var(--color-void)",
        color: "#fff",
        padding: "clamp(80px, 12vw, 140px) 0",
      }}
    >
      <div
        ref={ref}
        className="reveal"
        style={{ maxWidth: 820, margin: "0 auto", padding: "0 24px", textAlign: "center" }}
      >
        <h2 className="t-display" style={{ marginBottom: 22 }}>
          Everything stays on your Mac.
        </h2>
        <p
          className="t-lead"
          style={{ color: "var(--color-body-muted)", fontWeight: 300, margin: "0 auto", maxWidth: "40ch" }}
        >
          No accounts, no telemetry, no cloud sync. OCR runs on-device through
          Apple's Vision framework. The history is a local SQLite file - and the
          source code is{" "}
          <a href={REPO} target="_blank" rel="noreferrer" className="link-dark">
            on GitHub
          </a>
          .
        </p>

        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            justifyContent: "center",
            gap: 12,
            marginTop: 40,
          }}
        >
          {POINTS.map((p) => (
            <span
              key={p}
              className="t-caption"
              style={{
                padding: "8px 16px",
                borderRadius: 9999,
                border: "1px solid rgba(255,255,255,0.16)",
                color: "#fff",
              }}
            >
              {p}
            </span>
          ))}
        </div>
      </div>
    </section>
  );
}
