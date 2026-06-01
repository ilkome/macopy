import { PanelMockup } from "./PanelMockup";
import { IconDownload, IconGitHub } from "./icons";
import { DOWNLOAD, REPO } from "./links";
import { useReveal } from "./useReveal";

export function Hero() {
  const left = useReveal<HTMLDivElement>();
  const right = useReveal<HTMLDivElement>(120);

  return (
    <section
      id="top"
      style={{
        background: "var(--color-parchment)",
        paddingTop: "clamp(72px, 12vh, 132px)",
        paddingBottom: "clamp(64px, 10vh, 120px)",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          maxWidth: 1080,
          margin: "0 auto",
          padding: "0 24px",
          display: "grid",
          gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)",
          gap: "clamp(32px, 5vw, 64px)",
          alignItems: "center",
        }}
        className="hero-grid"
      >
        <div ref={left} className="reveal">
          <span
            className="t-caption"
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 8,
              padding: "5px 12px",
              borderRadius: 9999,
              background: "#fff",
              border: "1px solid var(--color-hairline)",
              color: "var(--color-ink-80)",
              marginBottom: 22,
            }}
          >
            <span
              style={{ width: 7, height: 7, borderRadius: 9999, background: "#34c759" }}
            />
            Open source · macOS native
          </span>

          <h1 className="t-hero" style={{ maxWidth: 14 + "ch" }}>
            Your clipboard, but with a memory.
          </h1>

          <p
            className="t-lead"
            style={{ color: "var(--color-ink-80)", marginTop: 22, maxWidth: "30ch" }}
          >
            A native macOS clipboard manager. Lives in the menu bar. Opens with{" "}
            <kbd
              style={{
                fontFamily: "var(--font-mono)",
                fontSize: "0.82em",
                padding: "2px 8px",
                borderRadius: 8,
                background: "#fff",
                border: "1px solid var(--color-hairline)",
              }}
            >
              ⌘`
            </kbd>{" "}
            - pastes with Enter.
          </p>

          <div style={{ display: "flex", flexWrap: "wrap", gap: 14, marginTop: 32 }}>
            <a href={DOWNLOAD} className="btn btn-primary">
              <IconDownload /> Download .dmg
            </a>
            <a href={REPO} target="_blank" rel="noreferrer" className="btn btn-ghost">
              <IconGitHub /> View on GitHub
            </a>
          </div>

          <p className="t-fine" style={{ color: "var(--color-ink-48)", marginTop: 18 }}>
            macOS 14 Sonoma or newer · Free · Open source (MIT)
          </p>
        </div>

        <div
          ref={right}
          className="reveal"
          style={{ display: "flex", justifyContent: "center" }}
        >
          <PanelMockup />
        </div>
      </div>
    </section>
  );
}
