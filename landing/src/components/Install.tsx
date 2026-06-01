import { useReveal } from "./useReveal";
import { IconDownload } from "./icons";
import { DOWNLOAD, REPO } from "./links";

function CodeBlock({ children }: { children: string }) {
  return (
    <pre
      style={{
        fontFamily: "var(--font-mono)",
        fontSize: 13,
        lineHeight: 1.6,
        background: "var(--color-tile-1)",
        color: "#f2f2f7",
        borderRadius: 11,
        padding: "14px 16px",
        overflowX: "auto",
        margin: 0,
      }}
    >
      <code>{children}</code>
    </pre>
  );
}

export function Install() {
  const head = useReveal<HTMLDivElement>();
  const c1 = useReveal<HTMLDivElement>(0);
  const c2 = useReveal<HTMLDivElement>(80);
  const c3 = useReveal<HTMLDivElement>(160);

  const card: React.CSSProperties = {
    background: "var(--color-canvas)",
    border: "1px solid var(--color-hairline)",
    borderRadius: 18,
    padding: 28,
    display: "flex",
    flexDirection: "column",
    gap: 16,
  };

  return (
    <section id="install" style={{ background: "var(--color-canvas)", padding: "clamp(72px, 10vw, 112px) 0" }}>
      <div style={{ maxWidth: 1080, margin: "0 auto", padding: "0 24px" }}>
        <div ref={head} className="reveal" style={{ marginBottom: 56, maxWidth: "24ch" }}>
          <h2 className="t-display">Install in a minute, or build it yourself.</h2>
        </div>

        <div
          className="install-grid"
          style={{ display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: 20, alignItems: "start" }}
        >
          <div ref={c1} className="reveal" style={card}>
            <h3 className="t-body-strong">Direct download</h3>
            <p className="t-body" style={{ color: "var(--color-ink-80)", flex: 1 }}>
              Grab the signed <code style={{ fontFamily: "var(--font-mono)", fontSize: 14 }}>.dmg</code> from GitHub
              Releases, drag it into Applications, and right-click → Open on first launch.
            </p>
            <a href={DOWNLOAD} className="btn btn-primary" style={{ alignSelf: "flex-start" }}>
              <IconDownload /> Download .dmg
            </a>
          </div>

          <div ref={c2} className="reveal" style={card}>
            <h3 className="t-body-strong">From source</h3>
            <p className="t-body" style={{ color: "var(--color-ink-80)" }}>
              Swift 6 toolchain (Xcode 16+). One script builds, bundles and signs the app.
            </p>
            <CodeBlock>{`git clone ${REPO}
cd macopy
./build-app.sh`}</CodeBlock>
          </div>

          <div ref={c3} className="reveal" style={card}>
            <h3 className="t-body-strong">Updates</h3>
            <p className="t-body" style={{ color: "var(--color-ink-80)", flex: 1 }}>
              Automatic through Sparkle. MaCopy checks the appcast, verifies the
              EdDSA signature and updates itself - or trigger it from the menu bar.
            </p>
            <a href={REPO} target="_blank" rel="noreferrer" className="link t-body" style={{ alignSelf: "flex-start" }}>
              Check for Updates →
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
