import type { ComponentType, SVGProps } from "react";
import { IconKey, IconBolt, IconReturn } from "./icons";
import { useReveal } from "./useReveal";

const STEPS: { Icon: ComponentType<SVGProps<SVGSVGElement>>; n: string; title: string; body: string }[] = [
  {
    Icon: IconKey,
    n: "01",
    title: "Press ⌘` to open",
    body: "The panel floats above your work without taking focus from the app underneath.",
  },
  {
    Icon: IconBolt,
    n: "02",
    title: "Type to search",
    body: "Fuzzy matching narrows the history instantly - including text recognized inside screenshots.",
  },
  {
    Icon: IconReturn,
    n: "03",
    title: "Hit Enter",
    body: "It pastes straight into the app you came from. The caret never moved.",
  },
];

function Step({ s, delay }: { s: (typeof STEPS)[number]; delay: number }) {
  const ref = useReveal<HTMLDivElement>(delay);
  const { Icon } = s;
  return (
    <div ref={ref} className="reveal">
      <span style={{ color: "var(--color-primary)", display: "block", marginBottom: 18 }}>
        <Icon width={32} height={32} />
      </span>
      <span
        className="t-fine"
        style={{ fontFamily: "var(--font-mono)", color: "var(--color-ink-48)" }}
      >
        {s.n}
      </span>
      <h3 className="t-tagline" style={{ marginTop: 6, marginBottom: 10 }}>
        {s.title}
      </h3>
      <p className="t-body" style={{ color: "var(--color-ink-80)", maxWidth: "30ch" }}>
        {s.body}
      </p>
    </div>
  );
}

export function HowItWorks() {
  const head = useReveal<HTMLDivElement>();
  return (
    <section id="how" style={{ background: "var(--color-parchment)", padding: "clamp(72px, 10vw, 112px) 0" }}>
      <div style={{ maxWidth: 1080, margin: "0 auto", padding: "0 24px" }}>
        <div ref={head} className="reveal" style={{ marginBottom: 56 }}>
          <h2 className="t-display">Three keys. That's the whole workflow.</h2>
        </div>
        <div
          className="steps-grid"
          style={{ display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: 40 }}
        >
          {STEPS.map((s, i) => (
            <Step key={s.n} s={s} delay={i * 90} />
          ))}
        </div>
      </div>
    </section>
  );
}
