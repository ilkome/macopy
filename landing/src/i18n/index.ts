import { en } from "./en";
import { ru } from "./ru";

export const languages = ["en", "ru"] as const;
export type Lang = (typeof languages)[number];
export const defaultLang: Lang = "en";

const ui: Record<Lang, typeof en> = { en, ru };

export function useTranslations(lang: Lang) {
  return ui[lang];
}

// astro build does not type-check, and `satisfies typeof en` in ru.ts cannot compare
// array lengths - a short/long RU array would silently drop or misalign zipped rows.
// This runs at SSG import time, so a mismatch fails the build instead of shipping.
const lengthGuards: [string, number, number][] = [
  ["nav.sections", en.nav.sections.length, ru.nav.sections.length],
  ["deepDive.blocks", en.deepDive.blocks.length, ru.deepDive.blocks.length],
  ["features.items", en.features.items.length, ru.features.items.length],
  ["hotkeys.actions", en.hotkeys.actions.length, ru.hotkeys.actions.length],
  ["howItWorks.steps", en.howItWorks.steps.length, ru.howItWorks.steps.length],
  ["privacy.pills", en.privacy.pills.length, ru.privacy.pills.length],
  ["footer.links", en.footer.links.length, ru.footer.links.length],
];
for (const [name, a, b] of lengthGuards) {
  if (a !== b) throw new Error(`i18n length mismatch in ${name}: en=${a} ru=${b}`);
}
en.deepDive.blocks.forEach((block, i) => {
  const other = ru.deepDive.blocks[i].points.length;
  if (block.points.length !== other) {
    throw new Error(`i18n length mismatch in deepDive.blocks[${i}].points: en=${block.points.length} ru=${other}`);
  }
});
