import { Logo } from "./Logo";
import { LICENSE, RELEASES, REPO, SITE, VERSION } from "./links";

const LINKS: { label: string; href: string }[] = [
  { label: "GitHub", href: REPO },
  { label: "Releases", href: RELEASES },
  { label: "License (MIT)", href: LICENSE },
  { label: "ilkome.com", href: SITE },
];

export function Footer() {
  return (
    <footer style={{ background: "var(--color-parchment)", padding: "64px 0 40px" }}>
      <div style={{ maxWidth: 1080, margin: "0 auto", padding: "0 24px" }}>
        <div
          className="footer-row"
          style={{
            display: "flex",
            alignItems: "flex-start",
            justifyContent: "space-between",
            gap: 32,
            flexWrap: "wrap",
          }}
        >
          <div style={{ maxWidth: "32ch" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
              <span style={{ borderRadius: 9, overflow: "hidden", display: "block", width: 34, height: 34 }}>
                <Logo size={34} />
              </span>
              <span className="t-tagline">MaCopy</span>
            </div>
            <p className="t-caption" style={{ color: "var(--color-ink-48)" }}>
              A clipboard manager for macOS. There's only one system clipboard -
              MaCopy just remembers what was on it.
            </p>
          </div>

          <nav style={{ display: "flex", gap: 48, flexWrap: "wrap" }}>
            <div style={{ display: "flex", flexDirection: "column" }}>
              <span className="t-caption" style={{ fontWeight: 600, marginBottom: 8 }}>
                Project
              </span>
              {LINKS.map((l) => (
                <a
                  key={l.label}
                  href={l.href}
                  target="_blank"
                  rel="noreferrer"
                  className="t-body footer-link"
                  style={{ color: "var(--color-ink-80)", textDecoration: "none", lineHeight: 2.1 }}
                >
                  {l.label}
                </a>
              ))}
            </div>
          </nav>
        </div>

        <div
          style={{
            marginTop: 48,
            paddingTop: 22,
            borderTop: "1px solid var(--color-hairline)",
            display: "flex",
            justifyContent: "space-between",
            gap: 16,
            flexWrap: "wrap",
          }}
        >
          <span className="t-fine" style={{ color: "var(--color-ink-48)" }}>
            © 2026 ilkome · v{VERSION}
          </span>
          <span className="t-fine" style={{ color: "var(--color-ink-48)" }}>
            Made on a Mac, for the Mac.
          </span>
        </div>
      </div>
    </footer>
  );
}
