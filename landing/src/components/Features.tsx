import type { ComponentType, SVGProps } from "react";
import {
  IconTags,
  IconScan,
  IconSearch,
  IconLink,
  IconShield,
  IconFocus,
} from "./icons";
import { useReveal } from "./useReveal";

type Feature = {
  Icon: ComponentType<SVGProps<SVGSVGElement>>;
  title: string;
  body: string;
};

const FEATURES: Feature[] = [
  {
    Icon: IconTags,
    title: "Smart type detection",
    body: "URLs, colors, images, code and plain text are sorted automatically into Favorites, All, URLs, Images, Colors and Code tabs.",
  },
  {
    Icon: IconScan,
    title: "On-device OCR",
    body: "Vision reads text inside screenshots in Russian and English. Search finds words that only ever existed as pixels.",
  },
  {
    Icon: IconSearch,
    title: "Fuzzy search",
    body: "Filters across content, OCR text, your comments and the name of the app the clip came from - as you type.",
  },
  {
    Icon: IconLink,
    title: "Link previews",
    body: "For URLs, MaCopy pulls the title, description and image via OpenGraph, so a link looks like the page behind it.",
  },
  {
    Icon: IconShield,
    title: "Private data filter",
    body: "Honors org.nspasteboard.ConcealedType. Passwords from 1Password and Bitwarden never enter the history.",
  },
  {
    Icon: IconFocus,
    title: "Doesn't steal focus",
    body: "A non-activating NSPanel. The caret stays in your original field, so ⌘V lands exactly where you were typing.",
  },
];

function Card({ f, delay }: { f: Feature; delay: number }) {
  const ref = useReveal<HTMLDivElement>(delay);
  const { Icon } = f;
  return (
    <div
      ref={ref}
      className="reveal"
      style={{
        background: "var(--color-canvas)",
        border: "1px solid var(--color-hairline)",
        borderRadius: 18,
        padding: 28,
      }}
    >
      <span style={{ color: "var(--color-primary)", display: "block", marginBottom: 18 }}>
        <Icon />
      </span>
      <h3 className="t-body-strong" style={{ marginBottom: 8 }}>
        {f.title}
      </h3>
      <p className="t-body" style={{ color: "var(--color-ink-80)" }}>
        {f.body}
      </p>
    </div>
  );
}

export function Features() {
  const head = useReveal<HTMLDivElement>();
  return (
    <section id="features" style={{ background: "var(--color-canvas)", padding: "clamp(72px, 10vw, 112px) 0" }}>
      <div style={{ maxWidth: 1080, margin: "0 auto", padding: "0 24px" }}>
        <div ref={head} className="reveal" style={{ maxWidth: "22ch", marginBottom: 56 }}>
          <h2 className="t-display">Everything you copied. Right where you left it.</h2>
        </div>
        <div
          className="feature-grid"
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
            gap: 20,
          }}
        >
          {FEATURES.map((f, i) => (
            <Card key={f.title} f={f} delay={(i % 3) * 80} />
          ))}
        </div>
      </div>
    </section>
  );
}
