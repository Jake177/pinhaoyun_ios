# Implementation status

Two sibling checkouts: `pinhaoyun_ios` on `feat/ios-core`, `PinHaoYun_backend` on `feat/mobile-api`.

Implemented: native SwiftUI auth/library/transfers/account flows; selected original and Live Photo resource export; disk-backed multipart upload and background URLSession; Keychain, downloads/sharing, versioned policy acknowledgement and deletion receipt. The companion backend supports shared Cookie/Bearer verification, mobile authentication, idempotent upload finalization/recovery, lifecycle-aware processing, and account-erasure jobs with retries, leases and alarms.

Validation: backend TypeScript passes; 29 Vitest tests pass. ESLint has zero errors and 20 existing warnings. Real isolated AWS integration covers authentication/refresh/consent, Web Cookie compatibility, rejected invalid or mismatched tokens, cross-account access, multipart resume, duplicate detection, accounting, thumbnail generation and original-byte integrity. Controlled-email registration and verification succeeded. Erasure completed with no remaining user partition or storage prefixes, another account remained accessible, and same-email re-registration rejected old credentials/late objects.

Native: Xcode 27.0 builds successfully with iOS 17 minimum. Three core tests pass, including reopening a disk-backed transfer store and Keychain receipt storage. A separate Swift background upload test passes against localhost + isolated AWS, with byte-identical original download. Test action runs without debugger attachment to avoid a local runner hang. Final simulator interaction/appearance checks are in progress; physical-device background and real Live Photo verification remain gates.

AWS: isolated `pinhaoyun-ios-dev` and `pinhaoyun-ios-dev-artifacts` stacks are deployed in ap-southeast-2 through profile `pinhaoyun`. Initial creation reached the account Lambda concurrency floor; only confirmed empty initial resources were recovered, then dedicated concurrency was replaced with per-job leases. Local configuration and secrets are ignored; raw secret values are not printed. Production resources and deployments are unchanged.

Backend draft PR: https://github.com/Jake177/PinHaoYun/pull/3. iOS PR and final UI review pending. The API currently runs locally against development AWS; no publicly hosted staging API or TestFlight build has been published.

Release gates: authentic HEIC/video/Live Photo and iCloud asset tests on physical iPhone; background/locking/force-quit/network/low-disk cases; operator/support details and approved bilingual policies; Apple membership, signing and TestFlight distribution. The user chose local testing without Apple membership. Automatic backup, maps and purchases remain later iterations per the approved plan.
