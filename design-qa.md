# Mindrop website design QA

final result: passed

**Source:** [Approved revised mockup](/Users/fatihsaglam/.codex/generated_images/01a1f9c3-bce4-7342-bda4-6737c0b33c35/exec-42a531d8-6307-40d7-8c04-f09400e43a80.png).

**Implementation:** [Desktop capture](/Users/fatihsaglam/.codex/visualizations/2026/11/20/01a1f9c3-bce4-7342-bda4-6737c0b33c35/mindrop-website-preview.jpg) and [mobile capture](/Users/fatihsaglam/.codex/visualizations/2026/11/20/01a1f9c3-bce4-7342-bda4-6737c0b33c35/mindrop-website-mobile.jpg).

**State and dimensions:** Homepage at “How it works,” with the example card loaded. The desktop browser viewport was 1440 × 1000 CSS px. The 1585 × 992 px reference was resampled proportionately to 1440 × 901 px to compare against the browser capture of that size at 1×. The mobile viewport was 390 × 844 CSS px with a 390 × 1019 px browser capture.

**Comparison:** [Full view](/Users/fatihsaglam/.codex/visualizations/2026/11/20/01a1f9c3-bce4-7342-bda4-6737c0b33c35/desktop-comparison.png), [heading detail](/Users/fatihsaglam/.codex/visualizations/2026/11/20/01a1f9c3-bce4-7342-bda4-6737c0b33c35/type-comparison.png), and [card detail](/Users/fatihsaglam/.codex/visualizations/2026/11/20/01a1f9c3-bce4-7342-bda4-6737c0b33c35/card-comparison.png). The source is on the left and the implementation is on the right in each comparison.

## Findings

- **Typography.** The local Bricolage Grotesque file loaded in the browser. Computed marketing weights are 700 and 400. The browser renders the Spotlight demo in the original system font.
- **Layout.** The three instructions align as open columns with their headings and paragraphs. They stack on mobile. No horizontal overflow was present at 320, 390, 768, or 1440 CSS px.
- **Colors.** The cream section uses `#F7F4EC` and the lower section uses `#101522`. The artwork uses the approved cobalt accent between the keyword and value. The implementation uses flat section backgrounds, an intentional difference from the subtle textures in the source.
- **Artwork.** The transparent paper-card asset has readable lettering and an unobtrusive edge on the dark background. Its raster resolution covers the desktop display width at 2×.
- **Content.** The three step headings and the sample value match the selected source. The existing copy about Siri, Shortcuts, Control Center, and Apple Watch follows the illustrated section.

## Iteration

The first comparison showed tighter, smaller headings and a slightly lower and wider paper card than the source. Adjusted the headline sizes and tracking, section spacing, and card width. Recaptured the same desktop crop and checked the mobile layout. No actionable P0–P2 differences remain.

## Interaction checks

- The “See how it works” link navigates to the instructional section.
- The Spotlight demo pauses on a readable result and accepts the play action.
- The App Store badge links to the existing Mindrop listing. The existing hero markup and demo script match the baseline byte for byte.
- The browser reported no console errors during the desktop interaction checks.
