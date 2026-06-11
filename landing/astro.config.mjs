import { defineConfig, fontProviders } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Static marketing site - zero client framework, just HTML/CSS plus one tiny
// inline script for scroll reveal and the sticky-nav blur.
export default defineConfig({
  site: "https://ilkome.com",
  // Inter is the cross-platform fallback after SF Pro. Astro's Fonts API
  // downloads it from Google at build time, self-hosts the woff2 (no runtime
  // third-party request), and emits preload + size-adjusted metric fallbacks.
  fonts: [
    {
      provider: fontProviders.google(),
      name: "Inter",
      cssVariable: "--font-inter",
      weights: [300, 400, 600],
      styles: ["normal"],
      subsets: ["latin"],
      // Deep fallbacks appended after Inter inside var(--font-inter).
      fallbacks: ["system-ui", "sans-serif"],
    },
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
