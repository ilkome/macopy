// English content - the source of truth. ru.ts mirrors this shape
// (`satisfies typeof en`); src/i18n/index.ts guards array lengths at build time.
// Prose only. Keyboard glyphs, code samples, product-UI mockup strings and brand
// names stay literal inside their components.
export const en = {
  meta: {
    title: "MaCopy - Your clipboard, but with a memory",
    description:
      "A native macOS clipboard manager. Lives in the menu bar, opens with the press of a key, pastes with Enter. On-device OCR, smart type detection, zero telemetry.",
  },

  nav: {
    sections: [
      { id: "highlights", label: "Highlights" },
      { id: "features", label: "Features" },
      { id: "shortcuts", label: "Shortcuts" },
      { id: "how", label: "How it works" },
      { id: "install", label: "Install" },
    ],
    download: "Download",
    github: "MaCopy on GitHub",
  },

  langSwitcher: {
    label: "Language",
  },

  hero: {
    badge: "Open source · macOS native",
    title: "Your clipboard, but with a memory.",
    leadBefore:
      "A native macOS clipboard manager. Lives in the menu bar. Opens with ",
    leadAfter: " - pastes with Enter.",
    download: "Download .dmg",
    github: "View on GitHub",
    fine: "macOS 14 Sonoma or newer · Free · Open source (MIT)",
  },

  deepDive: {
    heading: "Four ideas that make a history worth keeping.",
    intro:
      "Tabs, folders, comments and link previews - the difference between a pile of old clips and something you can actually find your way around.",
    blocks: [
      {
        eyebrow: "Tabs",
        title: "Every type, already sorted.",
        body: "The moment something lands on the clipboard, MaCopy reads what it is - a link, a colour, a snippet of code, an image, plain text - and drops it into the right tab. Favorites and Folders sit alongside for the things you keep.",
        points: [
          "Nothing to tag or file - detection runs the instant you copy.",
          "Hunting for that one hex code? The Colors tab is already just colors.",
          "← → flicks between tabs without lifting a hand off the keyboard.",
        ],
      },
      {
        eyebrow: "Folders",
        title: "Collections that cut across types.",
        body: "Tabs sort by what a clip is. Folders sort by what it's for. Gather the link, the screenshot and the snippet for one project into a single folder - even though each lives in a different tab.",
        points: [
          "One clip can live in many folders at once - no copies, no clutter.",
          "Create a folder and drop the clip in, all from a single ⌘L sheet.",
          "Folders open in a three-pane view: folders, their clips, a live preview.",
        ],
      },
      {
        eyebrow: "Comments",
        title: "Leave yourself a note.",
        body: "A bare hex value or an API token tells you nothing in a week. Attach a comment and the clip gets a name in your own words - one that search can find even when the content itself is gibberish.",
        points: [
          "Give a cryptic token or hex value a name you'll actually recognise.",
          "Comments are searchable - find a clip by the note, not just its text.",
          "Saves itself as you type. ⌘W jumps straight to the note field.",
        ],
      },
      {
        eyebrow: "Links",
        title: "A link that looks like the page.",
        body: "A URL on its own is just a string. MaCopy fetches the page's title, description, image and favicon, so you recognise a link at a glance - and the Links tab groups your history by the site it came from.",
        points: [
          "Title, description, image and favicon - pulled via OpenGraph.",
          "The Links tab folds your history by site, newest and busiest first.",
          "Previews are fetched over HTTPS only; private addresses are blocked.",
        ],
      },
    ],
  },

  features: {
    heading: "Thoughtful where it counts.",
    intro:
      "The details you only notice when they're missing - reading, searching, guarding and cleaning up after itself.",
    items: [
      {
        title: "On-device OCR",
        body: "Apple's Vision framework reads English and Russian text inside screenshots. Search finds words that only ever existed as pixels.",
      },
      {
        title: "Fuzzy search",
        body: "One field filters across content, OCR text, your comments and link titles - even the app a clip came from. As you type.",
      },
      {
        title: "Smart type detection",
        body: "URLs, colors, code, images and plain text are recognized the instant you copy. That's the engine behind every tab.",
      },
      {
        title: "Private-data filter",
        body: "Honors org.nspasteboard.ConcealedType, so passwords from 1Password and Bitwarden never reach the history.",
      },
      {
        title: "Secret detection",
        body: "API keys, tokens and JWTs are caught by pattern and entropy, and kept out of your history automatically.",
      },
      {
        title: "Encrypted on disk",
        body: "History and images are stored with AES. The key lives in your Keychain and is unlocked only on this Mac.",
      },
      {
        title: "Doesn't steal focus",
        body: "A non-activating panel. The caret stays in your original field, so ⌘V lands exactly where you were typing.",
      },
      {
        title: "Quick Look",
        body: "Tap Space on any image to see it full-size, straight from the panel. No app switch, no detour.",
      },
      {
        title: "Tidies itself",
        body: "Recent clips stay; the oldest items and stale link previews are pruned automatically. The history never balloons.",
      },
    ],
  },

  hotkeys: {
    heading: "Built for hands that never leave the keyboard.",
    intro:
      "Open, search, paste - the whole loop happens before your fingers reach the trackpad.",
    actions: [
      "Show / hide panel (configurable)",
      "Navigate the list",
      "Switch tabs",
      "Paste into the previous app",
      "Copy without pasting",
      "Toggle favorite",
      "Add to folder",
      "Edit comment",
      "Edit the clip's text",
      "Duplicate a text clip",
      "Open a link in the browser",
      "Paste one of the first 9 items",
      "Delete from history",
      "Quick Look for images",
      "Hide the panel",
    ],
  },

  howItWorks: {
    heading: "Three keys. That's the whole workflow.",
    steps: [
      {
        title: "Press ⌘` to open",
        body: "The panel floats above your work without taking focus from the app underneath.",
      },
      {
        title: "Type to search",
        body: "Fuzzy matching narrows the history instantly - including text recognized inside screenshots.",
      },
      {
        title: "Hit Enter",
        body: "It pastes straight into the app you came from. The caret never moved.",
      },
    ],
  },

  privacy: {
    heading: "Everything stays on your Mac.",
    lead: "No accounts, no telemetry, no cloud sync. OCR runs on-device through Apple's Vision framework. The history is a local SQLite file - and the source code is ",
    leadLink: "on GitHub",
    leadAfter: ".",
    pills: ["No accounts", "No telemetry", "No cloud sync", "On-device OCR"],
  },

  install: {
    heading: "Install in a minute, or build it yourself.",
    cards: {
      download: {
        title: "Direct download",
        body: "Grab the signed .dmg from GitHub Releases, drag it into Applications, and right-click → Open on first launch.",
        cta: "Download .dmg",
      },
      source: {
        title: "From source",
        body: "Swift 6 toolchain (Xcode 16+). One script builds, bundles and signs the app.",
      },
      updates: {
        title: "Updates",
        body: "Automatic through Sparkle. MaCopy checks the appcast, verifies the EdDSA signature and updates itself - or trigger it from the menu bar.",
        cta: "Check for Updates →",
      },
    },
  },

  footer: {
    tagline:
      "A clipboard manager for macOS. There's only one system clipboard - MaCopy just remembers what was on it.",
    projectHeading: "Project",
    links: ["GitHub", "Releases", "License (MIT)", "ilkome.com"],
    madeOn: "Made on a Mac, for the Mac.",
  },
};
