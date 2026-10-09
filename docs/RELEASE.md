# Core and automatic-backup beta validation

## 0.2 personal-device beta — 9 October 2026

- Isolated HTTPS App Runner API is deployed, with 0.5 vCPU, 1GB, maximum one instance, a health check, runtime secrets, API-only routing, signup allowlist and a CodeBuild container smoke check. Production is unchanged.
- Automatic backup, local daily windows, limited-access guidance, account/environment ledger, bounded original preparation, automatic retry/pause/recovery, cloud-delete suppression and local diagnostics are implemented. First activation asks for scope confirmation and Photos permission; signing in does not request Photos access.
- Current backend validation: **46 Vitest tests**, TypeScript and changed-file ESLint pass. The existing Web environment retains its workspace/build configuration; API container policy is kept in `deploy/pnpm-workspace.mobile.yaml`.
- **15 XCTest checks pass on iPhone 12 / iOS 27.2**: 13 local regressions plus manual and automatic generated-image cloud transport. Exact original bytes/quota, concurrent resume and automatic skip after cloud deletion are included. A cloud-enabled simulator run also passes all 15 on small iOS 26.5; after adding full reconciliation for unreadable PhotoKit history, the final 13 local checks pass again (two opt-in cloud cases skip). Core tests cover midnight/DST/travel, durable baseline/settings, pause isolation, credentials during offline refresh and interrupted preparation recovery.
- Real hosted lifecycle integration passes 16 categories: original bytes/exact quota, token/owner isolation, Web Cookie compatibility, authoritative bad-Bearer rejection, suppression, in-flight/late-event cleanup, manual restore, duplicates, lost-init response replay, concurrent duplicate finalization, completed-original lease recovery and cancellation.
- The core auth/upload/erasure regression cycle passes again with new disposable accounts. Full partition/object/Cognito removal, anonymized receipts, immediate denial, another account's access and same-email new-subject/late-old-object isolation are verified. Existing simulator QA fixture files were preserved and restored.
- Small-phone UI checks verify Chinese defaults/first-scope confirmation, zero queued existing assets in new-only mode, automatic PhotoKit export of a later-imported 2008 JPEG, correct capture-date library placement, time controls/waiting status, and English dark accessibility-large wrapping and scroll-reachable settings. VoiceOver and large-phone backup settings remain additional validation.
- Personal Team signing and installation succeeded. Signing identifiers remain only in ignored local configuration. Membership and TestFlight remain deferred.
- Build 3 splits password reset into email, code and new-password/confirmation pages. Password mismatch prevents save; incorrect/expired codes return to the code page. The agreed Cognito integration checks the code during final save, not at local Continue. Chinese small-phone checks confirm five digits keep Continue disabled, six enable it, and the next page contains two separate secure fields. No real password was entered by automation. Build 3's 13 local checks pass again on the iPhone, including empty/mismatched/case-different/weak confirmation cases; two optional cloud checks skip.
- Authentic iCloud/Live Photo and background/network scenarios remain pending. The [physical-device acceptance record](DEVICE-ACCEPTANCE.md) explicitly separates generated transport fixtures, simulator evidence and actual hardware use. Three-day/72-hour acceptance has not started.

The earlier core evidence below remains historical; it does not certify the new backup UI or hardware scheduling.

## Environment

- Xcode 27.0; deployment target iOS 17; iOS 27 and iOS 26.5 simulator runtimes installed.
- Separate iOS and backend feature branches.
- `pinhaoyun-ios-dev` / `pinhaoyun-ios-dev-artifacts`, Sydney region, AWS profile `pinhaoyun`.
- Existing production storage, user pool and running Web deployment have not been modified.

## Earlier core evidence

- Backend TypeScript passes; ESLint reports zero errors and 20 pre-existing warnings; 34 Vitest tests pass, including real RSA signature, issuer, audience, expiry, token-use and cross-token identity checks.
- Real isolated AWS integration verifies mobile sign-in/refresh/consent, legacy browser Cookie compatibility, invalid Bearer rejection, multipart resume, idempotent finalization, duplicate detection, thumbnail processing, original-byte integrity and cross-account isolation.
- A controlled email registration, delivered verification code, confirmation and first sign-in were tested successfully. The test address and credentials are kept out of Git.
- Account erasure was verified against Cognito, the whole DynamoDB partition, original/thumbnail/profile storage and an anonymized completion receipt. Another account remained accessible. Same-email registration obtained a different identity; old tokens were denied and a simulated late object from the erased subject was removed without recreating media.
- Native simulator compilation and all nine XCTest checks passed (eight core checks plus one explicitly enabled cloud integration check). The core checks reopen the disk-backed multipart/Live Photo pair store and round-trip Keychain receipts. The Swift background upload reaches isolated S3, finalizes the media and downloads byte-identical original content. Native login, library and original preview were exercised on the small iPhone simulator. The full nine-test run also passes on the iPhone 17 Pro Max / iOS 26.5 simulator, including overlapping queue recovery and exact quota delta checks. The test action uses the standard non-debugging launcher after the local debugger-attached runner stalled.

- Manual native UI checks include Chinese small-phone library/original/save, English large-phone sign-in/library/transfers/account, dark appearance, accessibility-large text and scroll-reachable deletion controls. The system picker imported PNG, HEIC and JPEG fixtures and a synthetic H.264 MOV; AVKit playback succeeded. Concurrent completion exposed a cancelled-refresh error, which was fixed and the three-item import reverified.
- Real isolated Lambda reprocessing verifies JPEG/video thumbnails and metadata after fixing known-length S3 upload bodies and first-frame extraction for short videos. Atomic DynamoDB checks reject writes after account inactivation, subject replacement or profile removal; the temporary proof fixture was removed.
- Development media functions have 3 GiB temporary storage; deployment applies 14-day Lambda log retention. Photo metadata and enrichment warnings no longer log precise coordinates or account details. Production logging and retention still require their separate audit.

- Finish corrections preserve secure deletion proof when returning to sign-in, retain per-owner transfer history and confirm unfinished-upload cancellation on sign-out, and add independent policy loading/retry recovery. Regression tests cover receipt navigation and transfer-history preservation.
- An earlier independent finish review marked all three scored corrections resolved. It validated the three new failure/recovery/confirmation captures alongside the earlier native captures; consent and receipt recovery remain source-and-test evidence only. This verdict covers those corrections for the local beta, not whole-app or hardware certification.

## UX refinements (9 October 2026)

- Authentication now uses native back navigation, compact substep titles, inline validation, keyboard focus/Done and bottom primary actions for long forms. Registration keeps required Cognito attributes and places legal links beside explicit agreement.
- Library filters keep their selected text visible and distinguish filtered-empty results. Original preparation reports processed counts and partial failures before durable enqueue, with a stop request that prevents further enqueue once the current export returns. Four known QA originals were imported and reached completed transfer history. Transfers group active work/history, display uploaded/total bytes, and collapse background help.
- Original photos use native pinch/double-tap zoom with adjustable accessibility and reset. Double-tap 250% zoom and the reset action were exercised in the simulator. Media recovery actions match preview, save, export, deletion or permission failure. Live Photo playback has a visible button equivalent; hardware playback remains a gate.
- Account-erasure rejection/acceptance is covered by a mocked HTTP regression check with actual local files, multipart state and owner-scoped records. Rejection retains work; accepted erasure clears only the captured owner after token removal. The real native background-upload check also passes against isolated AWS.
- Optional bilingual policy reading sections preserve all four legacy text bodies byte-for-byte and keep the same consent version; the live localhost API comparison passed. No policy acceptance was performed through the UI during this refinement.
- Current UI checks cover English library/filter selection, four-item preparation summary and completed transfer history, account/storage and sectioned policy reading, plus dark accessibility-large library/transfers on iPhone 17 Pro Max. A separate iPhone SE 3 / iOS 26.5 simulator verifies Chinese registration, native back navigation, surname/given-name order, reachable agreement/primary action, inline email validation and keyboard Next/Done. The existing iOS 27 small simulator failed to finish startup through the build/run tool; a fresh isolated iOS 26.5 small simulator was used successfully instead. No simulator contents were erased. Consent, reset-confirmation and receipt rendering still need further targeted UI evidence; full VoiceOver and physical Live Photo checks remain gates.

## Remaining release gates

- VoiceOver, landscape and minimum-OS runtime checks remain additional release validation.
- Physical iPhone verification: authentic Live Photo pair export/playback/save, iCloud-only assets, large videos, locking/backgrounding, force quit, connectivity changes, constrained data and low disk space. Simulator behavior does not establish hardware background reliability.
- Operator/legal entity, support contact, distribution countries, final bilingual terms and actual retention review. `POLICIES_APPROVED` remains false in development; production mobile authentication refuses unapproved policy configuration.
- If any production account has an active subscription, provide and verify the existing cancellation integration and the legally required billing-record treatment before enabling account erasure there. No new purchase flow is included in this beta.
- Apple Developer Program membership, release signing, App Store Connect record and TestFlight upload. Local Personal Team signing is working; the user chose local testing without membership.

## Production rollout order

1. Review and merge the narrowly scoped backend compatibility PR after tests. Keep Web UI behavior and its data keys/path conventions.
2. Provision production-only mobile client/secrets, deletion queue/jobs/worker/alarms with resource-scoped roles. Audit object versions, backups, retained account data and deletion completion monitoring.
3. Deploy the API's signature/identity verification and owner-sub upload metadata before activating lifecycle enforcement in processing functions. Drain old processing and in-flight transfers before enabling production erasure. Preserve old media visibility; validate timeline index coverage before enabling the existing index read path.
4. Grant processing roles `dynamodb:ConditionCheckItem` on their media table before deploying lifecycle-aware processors and the erasure worker; transaction permissions are documented in [AWS transaction IAM guidance](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html). Verify shared Cookie/Bearer access and an explicitly controlled production test account.
5. Approve final policies, configure the production mobile environment, validate physical devices, then distribute through TestFlight after signing is available.

Rollback must not re-enable requests for DELETING accounts, resurrect media tombstones or remove deletion jobs. Keep the erasure worker and alarms running independently of the mobile app and Web frontend deployment.

Privacy-manifest categories follow [Apple’s collected-data definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype), including account identifiers; final App Store privacy answers must be reviewed against the production configuration.
