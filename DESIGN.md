---
name: "PinHaoYun iOS"
description: "A quiet native library for original photos, videos and Live Photos."
colors:
  media-badge-text: "#ffffff"
  media-badge-scrim: "rgba(0, 0, 0, 0.65)"
typography:
  brand-title:
    fontFamily: "system-ui"
    fontWeight: 700
  title2:
    fontFamily: "system-ui"
  title2-bold:
    fontFamily: "system-ui"
    fontWeight: 700
  headline:
    fontFamily: "system-ui"
  subheadline:
    fontFamily: "system-ui"
  body:
    fontFamily: "system-ui"
  footnote:
    fontFamily: "system-ui"
  caption:
    fontFamily: "system-ui"
  media-badge:
    fontFamily: "system-ui"
    fontWeight: 700
rounded:
  media-cell: "0pt"
spacing:
  grid-gap: "3pt"
  media-badge-padding: "5pt"
  transfer-row-padding: "6pt"
  content-gap: "8pt"
  stack-gap: "12pt"
  brand-vertical-padding: "8pt"
  section-gap: "20pt"
components:
  media-badge:
    backgroundColor: "{colors.media-badge-scrim}"
    textColor: "{colors.media-badge-text}"
    typography: "{typography.media-badge}"
    padding: "{spacing.media-badge-padding}"
  media-cell:
    rounded: "{rounded.media-cell}"
  date-heading:
    typography: "{typography.headline}"
    padding: "8pt 12pt"
  transfer-title:
    typography: "{typography.headline}"
  brand-mark:
    width: "48pt"
    height: "48pt"
---

# Design System: PinHaoYun iOS

## Overview

**Creative North Star: "Native photo timeline"**

PinHaoYun uses the familiar iPhone photo-library grammar: media carries the visual interest, while system navigation, readable labels and persistent state make the interface feel quiet and dependable. Brand expression comes from the existing cloud-and-puzzle mark and one blue interaction tint. System text styles, controls and materials carry the rest of the interface.

This is a source-derived record of `App/PinHaoYunApp.swift`, `App/Views/` and `App/Services/PhotoImporter.swift`, reconciled with the approved native direction. Dimensions are native points, not web pixels. Frontmatter holds observed fixed values and portable family/weight facts; `.impeccable/design.json` records native semantic colors, Dynamic Type styles and system-owned geometry that the portable token schema cannot express. No fixed substitutes are invented for dynamic native values.

This source-derived record makes no runtime, hardware, accessibility, legal or production-readiness claims. Verification evidence belongs outside the design system.

**Key Characteristics:**

- Native navigation, forms, pickers, sheets and confirmation dialogs.
- Semantic surfaces and text, with blue interaction and red attention cues.
- Square media crops, close image spacing and chronological headings.
- Dynamic system typography and SF Symbols.
- Explicit loading, transfer, recovery and deletion states.

## Colors

The UI uses an adaptive iOS palette rather than a custom light/dark hex palette. Only the media badge has constant foreground and scrim colors; their values are owned by the frontmatter.

### Primary

- **System Blue** (`Color.blue`): root `.tint(.blue)` drives interactive controls. Standard controls inherit the environment tint. Transfer symbols use `Color.accentColor`; its exact resolution is an environment/platform concern rather than an additional brand palette.
- **Attention Red** (`Color.red` and `.destructive` roles): explicit errors, failed transfers and destructive account/media actions. A destructive role or visible explanation accompanies the color.

### Neutral

- **System Background** (`Color(uiColor: .systemBackground)` and `.background`): original-media ground and opaque date-heading ground.
- **Secondary System Background** (`Color(uiColor: .secondarySystemBackground)`): square thumbnail placeholders.
- **Primary / Secondary Foreground** (native default / `.secondary`): primary content and supporting copy. The OS resolves actual appearance.
- **Media Badge White / Scrim** (`colors.media-badge-text` / `colors.media-badge-scrim`): readable status over imagery; not general page-background colors.
- **System Bar / Regular Material** (`.bar` / `.regularMaterial`): safe-area explanations and media-detail notices. These are materials, not opaque swatches.

**The Semantic Surface Rule.** Retain the native semantic color or material at its existing role; do not replace it with a sampled screenshot hex.

**The State Has Words Rule.** Pair attention color with a state label, explanatory message or destructive action title.

## Typography

**UI Font:** the platform system font (San Francisco for Latin UI, with system-selected Chinese glyphs). No custom fonts, explicit font sizes, line heights or tracking are authored. Frontmatter `system-ui` is a portable family descriptor, not a web-font instruction.

### Hierarchy

| Token / native style | Observed use |
| --- | --- |
| `brand-title` / `.title.bold()` | Authentication brand name. |
| Native navigation title | Root Library, Transfers and Account use the default large-title behavior; detail, account deletion, policy and media information explicitly use inline titles. |
| `title2` / `.title2` | Placeholder symbols and deletion-receipt status. |
| `title2-bold` / `.title2.bold()` | Consent and account-deletion introductions. |
| `headline` / `.headline` | Date headings, transfer filenames and account identity. |
| `subheadline` / `.subheadline` | Account email and storage summary. |
| `body` / `.body` or native default | Forms, explanations, policy reading and ordinary actions. |
| `footnote` / `.footnote` | Supporting notes, transfer errors and recovery notices. |
| `caption` / `.caption` | Transfer state and completed-byte counter; the counter also uses `.monospacedDigit()`. |
| `media-badge` / `.caption2.bold()` | Live Photo marker and video duration. |

**The System Type Rule.** Keep semantic text styles so Dynamic Type can resize them; do not convert this table into fixed point-size constants. Transfer filenames allow two lines at ordinary sizes and unrestricted wrapping at accessibility sizes. State and byte counts can stack vertically when width is constrained.

English is the string-catalog source language, with Simplified Chinese entries. Native labels use localized keys; explicitly computed action/state labels use `String(localized:)`. Dates and byte counts use locale-aware formatters. Filenames, backend messages and policy bodies remain content. Runtime localization coverage and truncation are not certified by this document.

## Layout

Root sections use `TabView`, each with its own `NavigationStack`. Hierarchy uses native pushes; focused tasks use sheets. Safe areas, bar metrics, form/list insets and ordinary `.padding()` remain system-owned.

- **Grid:** adaptive `LazyVGrid`, minimum cell width 110 pt, `grid-gap` between rows and columns. Cells are square, thumbnails fill and clip. Column count follows available width; no authored breakpoints exist.
- **Chronology:** day sections use `section-gap` in a leading-aligned `LazyVStack` with pinned headers. Headings use `content-gap` vertically and `stack-gap` horizontally, full width with semantic background.
- **Transfers:** native `List` rows use leading stacks with `content-gap` and `transfer-row-padding` vertically. State and uploaded/total bytes share a row or stack at constrained widths. In-progress and history sections remain separate; completed rows use compact padding.
- **Forms:** authentication, account, consent, deletion and metadata use native `Form` sections, without a bespoke card layout.
- **Brand introduction:** `brand-mark` size, `stack-gap`, `brand-vertical-padding` and a clear form-row background.
- **Touch:** The Library add action has an explicit 44 × 44 pt frame; the filter uses a visible icon-and-title label with at least 44 pt height. Other controls rely on native controls; effective targets require runtime verification.
- **Detail:** only the background extends outside safe areas. Controls occupy native bars and safe-area insets. Originals fit without cropping; root tabs are hidden.

The interface is iPhone-first. Its adaptive grid does not establish a custom tablet or split-view composition. Orientation and actual viewport behavior require app verification.

## Elevation & Depth

There are no authored shadows, gradients or custom blur layers. Native grouped sections, image contrast, pinned heading backgrounds and system materials provide separation. Transfer explanations live in a native DisclosureGroup; detail progress, success and recovery notices use `.regularMaterial`. Bars, sheets, dialogs and standard controls retain platform treatment.

**The Native Material Rule.** Use the existing system material for notices and bars; do not turn those components into custom floating cards or hand-built glass.

There are no authored animation curves, durations, transitions or motion tokens. Navigation, presentation, progress and media playback use native controls. This records the absence of custom motion; it does not certify playback or Reduce Motion behavior.

## Shapes

Media thumbnails are square with clipped contents and no added corner radius or border. Overlaid Live Photo/video labels use `Capsule()`, whose rounding follows rendered height rather than a fixed radius. Inner padding and edge inset both use `media-badge-padding`.

System button styles, form sections, fields, menus, pickers, dialogs and sheets own their shapes. No custom card family, border-width scale or corner-radius scale exists. The opaque cloud-and-puzzle artwork is an identity asset; its navy/white artwork is not a second UI palette.

## Components

### Buttons

Use the implemented platform hierarchy: `.borderedProminent` for authentication, consent and the empty Library add action, `.bordered` for transfer Retry, `.borderless` for transfer cancellation, `.plain` for media links and native form-row/toolbar buttons elsewhere. Destructive actions use `.destructive`; the account-deletion navigation link is explicitly red. Native disabled/pressed appearances remain intact; no custom hover treatment exists.

Busy form actions keep their title and show a trailing `ProgressView` after a spacer. Authentication/consent submission and sign-out disable while busy. Authentication substeps use a local NavigationStack path, system back controls, compact task titles, screen-scoped focus progression and a keyboard Done action. Long-form primary actions occupy a bottom safe-area bar. Save/export controls disable during loading or saving.

### Inputs / Fields

Native `TextField`, `SecureField`, `Toggle` and `Picker` appear in forms. Email uses an email keyboard/content type, without automatic capitalization or autocorrection. Password and code fields use matching content types; codes use the number pad. Errors are visible text or labels in separate sections. No custom field border, focus glow or radius is authored.

### Navigation

The system tab bar uses Library (`photo.on.rectangle`), Transfers (`arrow.up.arrow.down`) and Account (`person.crop.circle`). Library filtering uses a native `Menu`/`Picker` with its current selection continuously visible; filtered empty results offer Show all media. Add is a toolbar action. Detail retains the system back path, hides root tabs and puts save, share, information and cloud deletion in the native bottom toolbar. Policy/information sheets provide Done.

### Native Sections and Notices

Account/authentication content uses `Form` sections; transfers and deletion receipts use `List`. There is no custom card primitive. Explanatory bars use `safeAreaInset` and system material, with no invented fixed height.

### Media Cell and Badge

A media cell keeps a neutral square until a thumbnail is available; its fallback is a photo/video SF Symbol in secondary foreground. A loaded image fills the clipped square. Video duration or LIVE status appears in a white-on-dark capsule at the bottom leading edge, with an SF Symbol and the media-badge text style. Media links expose filenames and opening hints. The badge is descriptive, not a filter chip.

### Transfer Row

Rows preserve `TransferRecord.id` identity. A filename, readable state, monospaced uploaded/total bytes and unfinished progress remain visible. Failed rows expose an error and Retry; unfinished rows expose Cancel upload. Symbols are `checkmark.circle.fill` for completed, `exclamationmark.circle` for failed `xmark.circle` for cancelled and `arrow.up.circle` otherwise. State text accompanies the symbol.

History is scoped to the signed-in owner. Normal Account sign-out cancels unfinished uploads after confirmation and keeps completed/cancelled rows associated with their original owner; another account does not see those rows.

### Empty, Loading and Recovery States

`ContentUnavailableView` handles empty Library/Transfers and unavailable media. The empty Library offers the add action. `ProgressView` handles loading. Media recovery names the failed action: loading, saving, file preparation or cloud deletion. Photos permission recovery offers Open Settings and file sharing. There is no skeleton or illustration system.

Account data and policy loading have independent state. Initial account loading uses a labeled `ProgressView`; policy loading and its error/retry remain in the Privacy section. A policy failure does not hide an already-loaded storage summary. Consent separates policy-loading errors from agreement-submission errors, with corresponding reload and submit actions. Reloading consent policy resets agreement; Agree and continue requires an available policy, explicit agreement and no active submission.

### Confirmation and Receipt Recovery

Account sign-out presents a native confirmation dialog when the current owner has unfinished uploads. Its destructive action explicitly says Cancel uploads and sign out, and the explanation identifies what is cancelled and what is kept. With no unfinished uploads, Account sign-out proceeds directly. This is a consequence-specific dialog, not a replacement for native navigation.

The deletion receipt remains a native list with readable requested/checking/completed status, dates when available, last checked time and a non-repeatable status check while loading. Return to sign in dismisses that view without erasing the saved receipt. Authentication exposes Check account deletion when a saved receipt exists, restoring the same status path. Receipt presentation stays separate from a promise that deletion has completed.

### Brand Asset

The AppIcon and BrandMark PNGs are 1024 × 1024 rasters of the pre-existing vector in `Artwork/AppIcon.svg`, produced by `scripts/render-icon.mjs`. Both carry origin metadata under PNG `impeccable:prompt`. The sign-in mark is decorative and accessibility-hidden. Preserve artwork and provenance; other UI icons use SF Symbols.

## Do's and Don'ts

### Do:

- **Do** retain native navigation, grouped forms, sheets and confirmation dialogs.
- **Do** preserve semantic colors, system text styles and native materials at their existing roles.
- **Do** use the observed spacing tokens for the matching grid, heading, badge and transfer-row patterns.
- **Do** keep transfer/deletion states readable in words, with available recovery actions.
- **Do** label icon-only actions and media meaningfully, and keep controls inside safe areas.
- **Do** use the English/Simplified Chinese string catalog and locale-aware date/byte formatting for new UI copy.

### Don't:

- **Don't** replace dynamic native colors, type, control geometry or ordinary padding with sampled fixed values.
- **Don't** add custom global navigation, a web icon library, a shadow system or hand-built glass to these surfaces.
- **Don't** crop originals in detail just because thumbnails use square crops.
- **Don't** turn a media badge into a filter chip or the identity artwork's navy into a second UI tint.
- **Don't** infer completed accessibility, localization, Dark Mode or device QA from source-derived rules.

## UX interaction refinements

The original preparation session is shared only between Library and Transfers. It reports processed item counts before durable enqueue, supports stopping preparation after the current export returns, and leaves already-queued uploads running. Authentication changes stop further enqueue for the previous owner. Failed exports can be selected again; temporary files that were not enqueued are removed.

Photo detail uses a native UIScrollView for pinch/double-tap zoom, adjustable accessibility actions and Reset zoom. Live Photos have visible playback guidance and a button equivalent. Video item failures expose a loading retry. Media information supports filename selection and copying.

Account-erasure cleanup happens only after server acceptance, using the captured owner after tokens are cleared. A rejected request retains original files, multipart progress and history. Policy reading uses optional server-provided headings and paragraphs; legacy plain text remains available and the existing consent version and wording are unchanged.
