---
version: 1
slug: "app-views-authview-swift"
primary_target: "App/Views/AuthView.swift"
related_targets: ["App/Resources/Assets.xcassets/LoginMemories.imageset","App/Resources/Localizable.xcstrings"]
---

# Sign-in

Mode: Operate. A first-time visitor understands that PinHaoYun keeps original photo memories and can immediately enter their email and password. Existing email authentication, registration, three-page password reset, policies and deletion receipt recovery remain reachable. Native SwiftUI, iOS 17+, English/Simplified Chinese, Dynamic Type and light/dark appearance.

## Direction contract

THESIS: A small personal photo album introduces the cloud library while direct sign-in remains visible.
OWN-WORLD: Blue cloud/cyan puzzle identity, system text styles, adaptive iOS surfaces, native fields and buttons; photography supplies warmth.
STORY: Recognize a private home for photo memories, sign in or find registration/reset, and read the linked policies.
FIRST VIEWPORT: Three decorative overlapping photo prints in the upper quarter; centered brand underneath; a bold two-line headline and secondary description aligned left; a grouped email/password block, full-width sign-in action, registration/reset row and quiet policy footer. Keyboard and larger type prioritize readable, scrollable controls. Accessibility Dynamic Type places the mark above the full-width brand name, preserving full system type. Dark appearance retains transparent artwork and semantic colors.
FORM: User-approved B left-aligned refinement of candidate 3, seed e2580a94. Approved comp: Artwork/Login/B-left-aligned.png. Adapt native states and Dynamic Type rather than rasterizing controls.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Unresolved: none for implementation. Device installation uses the existing local Personal Team and development API.

## Implemented surface

`signIn` is a `GeometryReader` and `ScrollView` with a leading stack, 24 pt horizontal and 16 pt vertical padding, and content at least as tall as the available viewport. The print artwork is `LoginMemories`, centered and scaled to fit, with height `min(216, geometry.size.height * 0.28)`. It appears only with no focused field, ordinary Dynamic Type and more than 400 pt of available height. Focus hides artwork and the headline/description so the fields and actions take priority.

The transparent `BrandMark` is 56 × 56 pt. Ordinary sizes use a centered horizontal brand row with 12 pt spacing; accessibility sizes use a vertical stack with 8 pt spacing and a centered full-width name. The name retains `.title.bold()` and unrestricted Dynamic Type. The leading headline uses `.largeTitle.bold()`, supporting copy `.subheadline`, and the policy links `.footnote`. Visible accessibility-size field labels and the beta note use `.caption`. No custom fonts or fixed text-size substitutes were introduced.

The page uses `systemGroupedBackground`; its rounded credential group uses `secondarySystemGroupedBackground` and a 20 pt corner radius. Supporting copy, feedback, beta note and shared field prompts use `Color.primary.opacity(0.7)`. Ordinary fields use a leading Grid with 16 pt column spacing and 52 pt minimum field height. Accessibility sizes stack caption labels over fields, with a 4 pt gap, 44 pt minimum field height and 12 pt vertical padding. Native TextField/SecureField semantics, explicit field accessibility labels, keyboard progression and the Done action remain intact. Decorative images and duplicate visual field labels are accessibility-hidden; the sign-in headline has a header trait. Red error text includes the submitted-error accessibility-focus binding.

The primary sign-in action remains in scroll content with `.borderedProminent`, `.controlSize(.large)` and `.buttonBorderShape(.capsule)`. Registration/reset and terms/privacy use `ViewThatFits` to switch between horizontal and vertical arrangements. Secondary links, policy links/reload and conditional deletion-receipt recovery have at least 44 pt authored heights. Sign-in hides the navigation bar; authentication substeps retain native Form sections, inline titles, system back navigation and bottom safe-area action bars. Agreement, validation, resend and recovery paths remain part of the existing authentication flow.

## Artwork and provenance

`Artwork/Login/B-left-aligned.png` is the approved 853 × 1844 concept; its prompt and approval record are retained in `B-left-aligned.prompt.txt` and `B-left-aligned.json`. The shipping decorative artwork was generated separately with `image_gen.imagegen` from that reference: `Artwork/Login/Memories.png` (1536 × 1024), with prompt `Memories.prompt.txt` and provenance/export rules in `Memories.json`. Origin: `exec-39104946-2e93-4833-a30c-c20497acf6ef.png`.

`App/Resources/Assets.xcassets/LoginMemories.imageset/memories.png` is the trimmed 1200 × 782 lossless PNG. Both master and shipping asset carry real alpha; opaque white print borders and translucent shadows remain. The asset catalog renders it as original artwork, using the same raster in light/dark appearances. Café left, mountain lake in front and coastal path right are synthetic decorative photos. Interface controls and text remain native views.

## Finish evidence

Final disposition: **ship**, as recorded in `.impeccable/review/login-finish-verdict.md`. F1 is resolved by the accessibility-size vertical branding, without font shrinking or a Dynamic Type cap. The same-path final iPhone 12 simulator captures cover Chinese light/dark, maximum accessibility size in dark mode and scrolled actions; the supplemental English light capture shows the ordinary-size composition. This is simulator screenshot evidence, with the review/verdict's stated coverage.

The builder reported a successful native compile, 13 passing existing tests and two explicitly credential-gated AWS tests skipped, followed by installation of physical build 6. Installation does not establish observed phone UI, VoiceOver, complete reset-flow or three-day backup acceptance. Those checks are not certified by this design documentation.
