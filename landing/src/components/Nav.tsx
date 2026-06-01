import { useEffect, useState } from "react";
import { Logo } from "./Logo";
import { IconGitHub } from "./icons";
import { DOWNLOAD, REPO } from "./links";

const SECTIONS = [
  { id: "features", label: "Features" },
  { id: "shortcuts", label: "Shortcuts" },
  { id: "how", label: "How it works" },
  { id: "install", label: "Install" },
];

export function Nav() {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header
      style={{
        position: "sticky",
        top: 0,
        zIndex: 50,
        height: 52,
        background: scrolled
          ? "rgba(245, 245, 247, 0.8)"
          : "rgba(245, 245, 247, 0)",
        backdropFilter: scrolled ? "saturate(180%) blur(20px)" : "none",
        WebkitBackdropFilter: scrolled ? "saturate(180%) blur(20px)" : "none",
        borderBottom: scrolled
          ? "1px solid rgba(0,0,0,0.06)"
          : "1px solid transparent",
        transition: "background 0.3s ease, border-color 0.3s ease",
      }}
    >
      <div
        style={{
          maxWidth: 1080,
          margin: "0 auto",
          height: "100%",
          padding: "0 24px",
          display: "flex",
          alignItems: "center",
          gap: 20,
        }}
      >
        <a
          href="#top"
          style={{ display: "flex", alignItems: "center", gap: 10, textDecoration: "none", color: "var(--color-ink)" }}
        >
          <span style={{ borderRadius: 8, overflow: "hidden", display: "block", width: 26, height: 26 }}>
            <Logo size={26} />
          </span>
          <span className="t-tagline" style={{ fontSize: 19 }}>
            MaCopy
          </span>
        </a>

        <nav
          className="t-caption"
          style={{ display: "flex", gap: 26, marginLeft: 8 }}
          data-nav
        >
          {SECTIONS.map((s) => (
            <a
              key={s.id}
              href={`#${s.id}`}
              style={{ color: "var(--color-ink-80)", textDecoration: "none" }}
              className="nav-link"
            >
              {s.label}
            </a>
          ))}
        </nav>

        <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 14 }}>
          <a
            href={REPO}
            target="_blank"
            rel="noreferrer"
            aria-label="MaCopy on GitHub"
            style={{ color: "var(--color-ink)", display: "flex" }}
            className="nav-gh"
          >
            <IconGitHub />
          </a>
          <a href={DOWNLOAD} className="btn btn-primary" style={{ padding: "7px 16px", fontSize: 14 }}>
            Download
          </a>
        </div>
      </div>
    </header>
  );
}
