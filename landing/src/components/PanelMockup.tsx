/* A faithful recreation of MaCopy's floating NSPanel - this is the hero
   "product render". It carries the single system drop-shadow. */

const TABS = ["Favorites", "All", "URLs", "Images", "Colors", "Code"] as const;

type Item = {
  app: string;
  appColor: string;
  glyph: string;
  preview: string;
  kind?: "url" | "color" | "code" | "image" | "text";
  meta: string;
  swatch?: string;
};

const ITEMS: Item[] = [
  {
    app: "Safari",
    appColor: "#1d9bf0",
    glyph: "S",
    preview: "https://developer.apple.com/design/human-interface-guidelines",
    kind: "url",
    meta: "Human Interface Guidelines - Apple Developer",
  },
  {
    app: "VS Code",
    appColor: "#2f7bd6",
    glyph: "{ }",
    preview: "const panel = NSPanel(.nonactivatingPanel)",
    kind: "code",
    meta: "MaCopyPanel.swift",
  },
  {
    app: "Figma",
    appColor: "#a259ff",
    glyph: "F",
    preview: "#5E5CE6",
    kind: "color",
    meta: "Brand / Indigo",
    swatch: "#5E5CE6",
  },
  {
    app: "Notes",
    appColor: "#febc2e",
    glyph: "N",
    preview: "Pick up oat milk, sparkling water, and a clipboard manager.",
    kind: "text",
    meta: "Shopping list",
  },
  {
    app: "Terminal",
    appColor: "#1d1d1f",
    glyph: ">_",
    preview: "./build-app.sh && open \"MaCopy by ilkome.app\"",
    kind: "code",
    meta: "zsh - macopy",
  },
];

function KindBadge({ kind }: { kind?: Item["kind"] }) {
  if (!kind || kind === "text") return null;
  const label = kind.toUpperCase();
  return (
    <span
      className="t-fine"
      style={{
        fontFamily: "var(--font-mono)",
        fontSize: 10,
        letterSpacing: "0.04em",
        color: "#7a7a7a",
        border: "1px solid rgba(0,0,0,0.10)",
        borderRadius: 5,
        padding: "2px 5px",
      }}
    >
      {label}
    </span>
  );
}

export function PanelMockup() {
  return (
    <div
      role="img"
      aria-label="The MaCopy floating panel showing clipboard history with tabs for Favorites, All, URLs, Images, Colors and Code."
      style={{
        width: "100%",
        maxWidth: 440,
        borderRadius: 18,
        background: "rgba(250, 250, 252, 0.86)",
        backdropFilter: "saturate(180%) blur(20px)",
        WebkitBackdropFilter: "saturate(180%) blur(20px)",
        border: "1px solid rgba(0,0,0,0.06)",
        boxShadow: "var(--shadow-product)",
        overflow: "hidden",
        userSelect: "none",
      }}
    >
      {/* Search field - pill, matching the CTA grammar */}
      <div style={{ padding: "14px 14px 8px" }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            height: 38,
            padding: "0 14px",
            borderRadius: 9999,
            background: "#fff",
            border: "1px solid rgba(0,0,0,0.08)",
          }}
        >
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#7a7a7a" strokeWidth="2" strokeLinecap="round">
            <circle cx="11" cy="11" r="6.5" />
            <path d="m20 20-3.6-3.6" />
          </svg>
          <span className="t-caption" style={{ color: "#7a7a7a" }}>
            Search history
          </span>
          <span
            aria-hidden
            style={{
              marginLeft: "auto",
              width: 1.5,
              height: 16,
              background: "#0066cc",
              animation: "mc-caret 1.1s steps(1) infinite",
            }}
          />
        </div>
      </div>

      {/* Tabs */}
      <div
        style={{
          display: "flex",
          gap: 6,
          padding: "0 14px 12px",
          overflow: "hidden",
        }}
      >
        {TABS.map((t, i) => (
          <span
            key={t}
            className="t-fine"
            style={{
              fontWeight: i === 1 ? 600 : 400,
              padding: "5px 10px",
              borderRadius: 9999,
              color: i === 1 ? "#fff" : "#333",
              background: i === 1 ? "#0066cc" : "rgba(0,0,0,0.05)",
            }}
          >
            {t}
          </span>
        ))}
      </div>

      {/* History list */}
      <div style={{ padding: "0 8px 10px" }}>
        {ITEMS.map((it, i) => {
          const selected = i === 0;
          return (
            <div
              key={i}
              style={{
                display: "flex",
                gap: 11,
                alignItems: "flex-start",
                padding: "10px 12px",
                borderRadius: 11,
                background: selected ? "#0066cc" : "transparent",
                color: selected ? "#fff" : "#1d1d1f",
              }}
            >
              {/* Source app icon chip */}
              {it.swatch ? (
                <span
                  style={{
                    flex: "0 0 auto",
                    width: 26,
                    height: 26,
                    borderRadius: 7,
                    background: it.swatch,
                    border: "1px solid rgba(0,0,0,0.12)",
                  }}
                />
              ) : (
                <span
                  style={{
                    flex: "0 0 auto",
                    width: 26,
                    height: 26,
                    borderRadius: 7,
                    background: it.appColor,
                    color: "#fff",
                    display: "grid",
                    placeItems: "center",
                    fontFamily: "var(--font-mono)",
                    fontSize: 11,
                    fontWeight: 600,
                  }}
                >
                  {it.glyph}
                </span>
              )}

              <span style={{ minWidth: 0, flex: 1 }}>
                <span
                  style={{
                    display: "block",
                    fontFamily:
                      it.kind === "code" || it.kind === "color"
                        ? "var(--font-mono)"
                        : "var(--font-text)",
                    fontSize: it.kind === "code" || it.kind === "color" ? 13 : 14,
                    fontWeight: 400,
                    lineHeight: 1.3,
                    whiteSpace: "nowrap",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                  }}
                >
                  {it.preview}
                </span>
                <span
                  className="t-fine"
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 7,
                    marginTop: 4,
                    color: selected ? "rgba(255,255,255,0.78)" : "#7a7a7a",
                  }}
                >
                  <span>{it.app}</span>
                  <span style={{ opacity: 0.5 }}>·</span>
                  <span
                    style={{
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {it.meta}
                  </span>
                </span>
              </span>

              <span style={{ flex: "0 0 auto", paddingTop: 2 }}>
                {selected ? (
                  <span
                    className="t-fine"
                    style={{
                      fontFamily: "var(--font-mono)",
                      fontSize: 11,
                      color: "rgba(255,255,255,0.9)",
                      border: "1px solid rgba(255,255,255,0.4)",
                      borderRadius: 5,
                      padding: "2px 6px",
                    }}
                  >
                    ↵
                  </span>
                ) : (
                  <KindBadge kind={it.kind} />
                )}
              </span>
            </div>
          );
        })}
      </div>

      {/* Footer hint strip */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 14,
          padding: "10px 16px",
          borderTop: "1px solid rgba(0,0,0,0.06)",
          color: "#7a7a7a",
        }}
      >
        <span className="t-fine">↵ Paste</span>
        <span className="t-fine">⇧↵ Copy</span>
        <span className="t-fine">⌘S Favorite</span>
        <span className="t-fine" style={{ marginLeft: "auto" }}>
          5 items
        </span>
      </div>
    </div>
  );
}
