# Mobile API contract

All requests are JSON over HTTPS in hosted environments. Local simulator development uses loopback HTTP. Every protected route verifies Cognito issuer, RS256 signature, allowed client audience, expiry, `token_use=id`, verified email and the account lifecycle. `Authorization: Bearer <idToken>` is authoritative; an invalid value never falls back to a cookie. `X-Access-Token` is optional except for Cognito profile updates, and when present is verified against the same subject and client. Web Cookie authentication remains supported.

## Authentication

`POST /api/mobile/auth/{operation}` supports `sign-in`, `sign-up`, `confirm-sign-up`, `resend-code`, `refresh`, `sign-out`, `forgot-password`, `confirm-forgot-password`.

Sign-in: `{email,password}`. Response: `{idToken,accessToken,refreshToken,expiresIn,username,sub,email,requiresConsent}`. Refresh: `{refreshToken,username}`; the username is the returned Cognito subject, not an inferred email alias. Sign-out revokes the device refresh token. Verification/reset take `email`, `code`, and `password` where applicable.

Registration also takes `preferredUsername`, `givenName`, `familyName`, `gender` (`Male`, `Female`, `Other`) and the policy acknowledgement fields below. Existing required user-pool attributes are preserved.

## Policies

`GET /api/mobile/policies` returns `{version,isDraft,terms:{en,zh},privacy:{en,zh}}`. `POST /api/mobile/consent` takes `{acceptedTerms:true,acknowledgedPrivacy:true,termsVersion,privacyVersion}`. Registration uses the same fields. Timestamps are assigned by the server and bound to the authenticated subject. A mobile session without current acknowledgement can reach the consent route, but cannot access protected media.

## Media

Existing `/api/videos/list`, `/api/user/profile`, `/api/videos/delete` and multipart routes keep their Web-compatible response shapes, including the `videos` array that contains both photos and videos.

`POST /api/media/urls`: `{id,type:"PHOTO"|"VIDEO"}` → fresh `{originalUrl,originalPhotoUrl,liveVideoUrl,thumbnailUrl,expiresAt}`. Media is looked up under the authenticated owner; caller-supplied bucket/key paths are not used for this operation.

Multipart: `init → part → PUT presigned URL → complete → notify`; `status` recovers S3 part numbers/ETags and recognizes an already-completed object. Notify is transactionally idempotent and preserves metadata produced asynchronously by Lambda. Live Photo image and motion use one photo ID, with `mediaRole=image` / `liveVideo`, and finalize sequentially. Original limits and quick content hashes remain compatible with the Web client.

## Account erasure

`POST /api/user/delete-account`: `{confirm:true,requestId?,receipt?}`; requires authentication within the last five minutes. Clients may generate a UUID plus 32 random bytes encoded as 43-character base64url and persist them securely **before** sending. Repeating the same proof returns the same receipt while the job is active.

Response `202`: `{requestId,receipt,requestedAt,deleteBy,state}`. `POST /api/user/deletion-status` uses `{requestId,receipt}` and does not require an account token, so status remains available after revocation. Incorrect proofs return 404 and disclose no account information.

The job freezes shared access, revokes credentials, cleans objects/versions/multipart uploads and partition data, waits for processing to quiesce, cleans again, deletes Cognito and strips personal identifiers from its completion receipt. Leases, SQS retry/DLQ, scheduled recovery and deadline alarms prevent a dropped client request or a failed dispatch from losing the job. Client Photos libraries are unaffected.
