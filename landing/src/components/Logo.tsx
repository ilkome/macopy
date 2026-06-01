/** MaCopy squircle mark - the card-stack clipboard history. Brand asset. */
export function Logo({ size = 96 }: { size?: number }) {
  return (
    <svg
      viewBox="0 0 1024 1024"
      width={size}
      height={size}
      aria-hidden="true"
      style={{ display: "block" }}
    >
      <defs>
        <linearGradient id="mc-bg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#5E5CE6" />
          <stop offset="1" stopColor="#BF5AF2" />
        </linearGradient>
        <linearGradient id="mc-hl" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffffff" stopOpacity="0.18" />
          <stop offset="0.5" stopColor="#ffffff" stopOpacity="0" />
        </linearGradient>
      </defs>
      <rect width="1024" height="1024" rx="229" fill="url(#mc-bg)" />
      <rect width="1024" height="1024" rx="229" fill="url(#mc-hl)" />
      <rect x="260" y="210" width="360" height="460" rx="48" fill="#fff" fillOpacity="0.4" />
      <rect x="332" y="282" width="360" height="460" rx="48" fill="#fff" fillOpacity="0.65" />
      <rect x="404" y="354" width="360" height="460" rx="48" fill="#fff" />
      <rect
        width="1024"
        height="1024"
        rx="229"
        fill="none"
        stroke="#fff"
        strokeOpacity="0.08"
        strokeWidth="2"
      />
    </svg>
  );
}
