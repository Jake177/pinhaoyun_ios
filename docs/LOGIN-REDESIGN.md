# Album sign-in · 0.2.0 build 6

The user approved the B left-aligned composition on 12 October 2026: overlapping illustrative photo prints, centered cloud/puzzle branding, a leading headline/description and immediately available email sign-in. `AuthView` renders all text and controls natively. The photo stack is a transparent generated asset; its reference, prompt and export provenance are in `Artwork/Login/`.

The sign-in surface uses adaptive system grouped backgrounds, system type and the existing light/dark brand asset. Keyboard focus removes the decorative introduction, while the form stays scrollable. Accessibility sizes use vertical branding and labeled stacked fields; secondary and policy actions can stack. Error messages retain the entered credentials. Registration, the three-page Cognito reset, policy reading and saved deletion-receipt recovery retain their existing behavior.

## Validation

- Native simulator and signed physical-device builds succeeded. Final build 6 was installed in place on the paired iPhone 12 and launched successfully; its installed bundle version was verified. No app uninstall or account sign-out was performed.
- Existing XCTest regression suite: 13 passed, 0 failed, 2 credential-gated cloud tests skipped. The final correction changed only brand layout at accessibility sizes; the corrected simulator and device builds also compiled successfully.
- iOS 26.5 simulator captures cover the iPhone 12 in light/dark Chinese, maximum accessibility text and its scrolled actions, plus ordinary English. Smaller iPhone SE checks covered keyboard Next/Go/Done, invalid sign-in feedback with synthetic credentials, registration's initially unchecked agreement, the reset entry and privacy sheet dismissal.
- The independent reviewer identified one Dynamic Type brand-wrapping issue. After correction, the reviewer scored that issue resolved and returned `ship` at the fix-verdict scope.
- Raster provenance scan: 3 files, 0 missing. Artwork does not use private Photos-library content.

Captured UI is simulator evidence. Physical-device UI and VoiceOver were not observed, and this UI change does not establish a new complete password-reset or three-day automatic-backup acceptance result. Existing device backups and release acceptance remain tracked separately.

Local captures and review reports are in ignored `.impeccable/review/`; build, install, launch and version-check records are in ignored `build/login-qa/`. The default UI uses English or Simplified Chinese according to device language and follows device appearance.
