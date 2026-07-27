import { defineConfig, fontProviders } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Static marketing site - zero client framework, just HTML/CSS plus one tiny
// inline script for scroll reveal and the sticky-nav blur.
export default defineConfig({
  site: "https://macopy.ilko.me",
  // English at "/" (no prefix), Russian at "/ru". The i18n block gives us the
  // astro:i18n URL helpers and Astro.currentLocale; routing/detection is handled
  // by a tiny inline script (static build has no Astro.preferredLocale).
  i18n: {
    defaultLocale: "en",
    locales: ["en", "ru"],
    routing: { prefixDefaultLocale: false },
  },
  // /en is not a canonical URL (English lives at root); send it home.
  redirects: { "/en": "/" },
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
