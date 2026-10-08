# Core beta validation and release

## Environment

- Xcode 27.0; deployment target iOS 17; iOS 27 and iOS 26.5 simulator runtimes installed.
- Separate iOS and backend feature branches.
- `pinhaoyun-ios-dev` / `pinhaoyun-ios-dev-artifacts`, Sydney region, AWS profile `pinhaoyun`.
- Existing production storage, user pool and running Web deployment have not been modified.

## Confirmed evidence

- Backend TypeScript passes; ESLint reports zero errors and 20 pre-existing warnings; 34 Vitest tests pass, including real RSA signature, issuer, audience, expiry, token-use and cross-token identity checks.
- Real isolated AWS integration verifies mobile sign-in/refresh/consent, legacy browser Cookie compatibility, invalid Bearer rejection, multipart resume, idempotent finalization, duplicate detection, thumbnail processing, original-byte integrity and cross-account isolation.
- A controlled email registration, delivered verification code, confirmation and first sign-in were tested successfully. The test address and credentials are kept out of Git.
- Account erasure was verified against Cognito, the whole DynamoDB partition, original/thumbnail/profile storage and an anonymized completion receipt. Another account remained accessible. Same-email registration obtained a different identity; old tokens were denied and a simulated late object from the erased subject was removed without recreating media.
- Native simulator compilation and all six XCTest checks passed (five core checks plus one explicitly enabled cloud integration check). The core checks reopen the disk-backed multipart/Live Photo pair store and round-trip Keychain receipts. The Swift background upload reaches isolated S3, finalizes the media and downloads byte-identical original content. Native login, library and original preview were exercised on the small iPhone simulator. The full six-test run also passes on the iPhone 17 Pro Max / iOS 26.5 simulator, including overlapping queue recovery and exact quota delta checks. The test action uses the standard non-debugging launcher after the local debugger-attached runner stalled.

- Manual native UI checks include Chinese small-phone library/original/save, English large-phone sign-in/library/transfers/account, dark appearance, accessibility-large text and scroll-reachable deletion controls. The system picker imported PNG, HEIC and JPEG fixtures and a synthetic H.264 MOV; AVKit playback succeeded. Concurrent completion exposed a cancelled-refresh error, which was fixed and the three-item import reverified.
- Real isolated Lambda reprocessing verifies JPEG/video thumbnails and metadata after fixing known-length S3 upload bodies and first-frame extraction for short videos. Atomic DynamoDB checks reject writes after account inactivation, subject replacement or profile removal; the temporary proof fixture was removed.
- Development media functions have 3 GiB temporary storage; deployment applies 14-day Lambda log retention. Photo metadata and enrichment warnings no longer log precise coordinates or account details. Production logging and retention still require their separate audit.

- Finish corrections preserve secure deletion proof when returning to sign-in, retain per-owner transfer history and confirm unfinished-upload cancellation on sign-out, and add independent policy loading/retry recovery. Regression tests cover receipt navigation and transfer-history preservation.
- Independent finish review marked all three scored corrections resolved. It validated the three new failure/recovery/confirmation captures alongside the earlier native captures; consent and receipt recovery remain source-and-test evidence only. This verdict covers those corrections for the local beta, not whole-app or hardware certification.

## Remaining release gates

- VoiceOver, landscape and minimum-OS runtime checks remain additional release validation.
- Physical iPhone verification: authentic Live Photo pair export/playback/save, iCloud-only assets, large videos, locking/backgrounding, force quit, connectivity changes, constrained data and low disk space. Simulator behavior does not establish hardware background reliability.
- Operator/legal entity, support contact, distribution countries, final bilingual terms and actual retention review. `POLICIES_APPROVED` remains false in development; production mobile authentication refuses unapproved policy configuration.
- If any production account has an active subscription, provide and verify the existing cancellation integration and the legally required billing-record treatment before enabling account erasure there. No new purchase flow is included in this beta.
- Apple Developer Program / Team ID, device signing, App Store Connect record and TestFlight upload. The user currently chose local testing without membership.

## Production rollout order

1. Review and merge the narrowly scoped backend compatibility PR after tests. Keep Web UI behavior and its data keys/path conventions.
2. Provision production-only mobile client/secrets, deletion queue/jobs/worker/alarms with resource-scoped roles. Audit object versions, backups, retained account data and deletion completion monitoring.
3. Deploy the API's signature/identity verification and owner-sub upload metadata before activating lifecycle enforcement in processing functions. Drain old processing and in-flight transfers before enabling production erasure. Preserve old media visibility; validate timeline index coverage before enabling the existing index read path.
4. Grant processing roles `dynamodb:ConditionCheckItem` on their media table before deploying lifecycle-aware processors and the erasure worker; transaction permissions are documented in [AWS transaction IAM guidance](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html). Verify shared Cookie/Bearer access and an explicitly controlled production test account.
5. Approve final policies, configure the production mobile environment, validate physical devices, then distribute through TestFlight after signing is available.

Rollback must not re-enable requests for DELETING accounts, resurrect media tombstones or remove deletion jobs. Keep the erasure worker and alarms running independently of the mobile app and Web frontend deployment.

Privacy-manifest categories follow [Apple’s collected-data definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype), including account identifiers; final App Store privacy answers must be reviewed against the production configuration.
