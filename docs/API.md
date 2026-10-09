# Mobile API contract

All requests are JSON over HTTPS in hosted environments. Local simulator development uses loopback HTTP. Every protected route verifies Cognito issuer, RS256 signature, allowed client audience, expiry, `token_use=id`, verified email and the account lifecycle. `Authorization: Bearer <idToken>` is authoritative; an invalid value never falls back to a cookie. `X-Access-Token` is optional except for Cognito profile updates, and when present is verified against the same subject and client. Web Cookie authentication remains supported.

## Authentication

`POST /api/mobile/auth/{operation}` supports `sign-in`, `sign-up`, `confirm-sign-up`, `resend-code`, `refresh`, `sign-out`, `forgot-password`, `confirm-forgot-password`.

Sign-in: `{email,password}`. Response: `{idToken,accessToken,refreshToken,expiresIn,username,sub,email,requiresConsent}`. Refresh: `{refreshToken,username}`; the username is the returned Cognito subject, not an inferred email alias. Sign-out revokes the device refresh token. Verification/reset take `email`, `code`, and `password` where applicable.

Registration also takes `preferredUsername`, `givenName`, `familyName`, `gender` (`Male`, `Female`, `Other`) and the policy acknowledgement fields below. Existing required user-pool attributes are preserved.

The app's three-page password reset collects email, then a six-digit code, then two matching new-password entries. The code is retained only in view memory; Cognito validates it together with the password during `confirm-forgot-password`. The code page's Continue checks format and makes no verification-success claim. Incorrect/expired responses return to that page. Cognito requires code and password together in [ConfirmForgotPassword](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_ConfirmForgotPassword.html); no standalone verification service is added.

## Policies

`GET /api/mobile/policies` returns `{version,isDraft,terms:{en,zh},privacy:{en,zh}}`, with optional `reading:{terms:{en,zh},privacy:{en,zh}}`; each reading document contains `title` and `sections:[{title,text}]`. The reading extension preserves the legacy text bodies and consent version; clients fall back to plain text when it is absent. `POST /api/mobile/consent` takes `{acceptedTerms:true,acknowledgedPrivacy:true,termsVersion,privacyVersion}`. Registration uses the same fields. Timestamps are assigned by the server and bound to the authenticated subject. A mobile session without current acknowledgement can reach the consent route, but cannot access protected media.

## Media

Existing `/api/videos/list`, `/api/user/profile`, `/api/videos/delete` and multipart routes keep their Web-compatible response shapes, including the `videos` array that contains both photos and videos.

`POST /api/media/urls`: `{id,type:"PHOTO"|"VIDEO"}` → fresh `{originalUrl,originalPhotoUrl,liveVideoUrl,thumbnailUrl,expiresAt}`. Media is looked up under the authenticated owner; caller-supplied bucket/key paths are not used for this operation.

Multipart: `init → part → PUT presigned URL → complete → notify`; `status` recovers S3 part numbers/ETags and recognizes an already-completed object. Notify is transactionally idempotent and preserves metadata produced asynchronously by Lambda. Live Photo image and motion use one photo ID, with `mediaRole=image` / `liveVideo`, and finalize sequentially. Original limits and quick content hashes remain compatible with the Web client.

### Automatic backup and recovery

`init` accepts optional `uploadSource:"automatic"|"manual"` (omitted means manual) and `requestId` (UUID). New clients persist the request ID before initialization. Replaying an exact owned reservation returns the same upload ID/key with `resumed:true`; reconcile `status` before sending further parts. Conflicting reservations return `409` / `UPLOAD_IN_PROGRESS`. Optional fields preserve legacy callers.

Automatic initialization may return `{skipped:true,skipReason:"CLOUD_DELETED"}` without creating an upload or reserving quota. Existing live duplicates can still return the legacy duplicate result. Server reservations bind the source, fingerprint, resource role, owner and request ID; later requests cannot change that source. Media deletion writes its fingerprint marker atomically before dispatch. Initialization, completion, finalization and processing recheck lifecycle/ownership; rejected in-flight automatic work returns `410` / `CLOUD_DELETED` and releases its reservation/originals. Manual re-upload remains possible.

Concurrent uploads of identical content finalize to one canonical media record and charge once. `notify` may return `{ok:true,duplicate:true,photoId}`; use that canonical ID for the remaining Live Photo resource. New motion uploads use a request-specific suffix; old clients keep the existing path convention.

Completed originals awaiting `notify` retain their quota lease across expiry/recovery. Explicit `abort` also discards completed-but-unfinalized originals. Processing writes are fenced by reservation/request ID, media lifecycle and account subject, including late callbacks after cancellation. Account erasure clears backup deletion markers with the entire owner partition.

`GET /api/mobile/health` is an unauthenticated, non-cached health check. API-only hosting allows the selected mobile/media/user routes, rejects other pages and restricts registration to a runtime-configured test allowlist. Mobile auth refresh credentials remain 30-day credentials. Current development policy version: `2026-10-09-beta-2`, still a draft.

## Account erasure

`POST /api/user/delete-account`: `{confirm:true,requestId?,receipt?}`; requires authentication within the last five minutes. Clients may generate a UUID plus 32 random bytes encoded as 43-character base64url and persist them securely **before** sending. Repeating the same proof returns the same receipt while the job is active.

Response `202`: `{requestId,receipt,requestedAt,deleteBy,state}`. `POST /api/user/deletion-status` uses `{requestId,receipt}` and does not require an account token, so status remains available after revocation. Incorrect proofs return 404 and disclose no account information.

The job freezes shared access, revokes credentials, cleans objects/versions/multipart uploads and partition data, waits for processing to quiesce, cleans again, deletes Cognito and strips personal identifiers from its completion receipt. Leases, SQS retry/DLQ, scheduled recovery and deadline alarms prevent a dropped client request or a failed dispatch from losing the job. Client Photos libraries are unaffected.
