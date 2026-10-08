# Subsequent iterations

## Automatic camera backup

Reuse the durable transfer queue and native Photos resources. Default off; choose all existing photos or only additions after activation; video backup is a separate option. Default Wi-Fi only, with explicit Wi-Fi/cellular opt-in. Settings are device-specific.

Time windows are optional and follow the device's local timezone, including travel and daylight saving. The agreed behavior prioritizes the requested interval and permits delayed completion. iOS cannot guarantee an exact wakeup, hard cutoff, work after force quit, or completion every night. The app must state its actual pending/paused/failed state and show progress and the next user action. Limited Photos authorization backs up only accessible assets. Preserve Live Photo pairs and reconcile duplicates and in-flight transfers before advancing a backup checkpoint.

Validate on physical hardware before enabling: iCloud-only originals, locked device, low power, constrained/cellular networking, local storage shortage, suspension, force quit, expired access/presigned URLs, permission changes, account switching and deletion.

## Web feature coverage

Expand search/date/type/favorite filtering, favorites, batch operations, map footprints and location editing, profile basics/bio/signature. Prefer native controls and MapKit display while retaining the existing server location contract and transparently disclosing geocoding data flow.

## Purchases

A separate iteration will determine StoreKit/Stripe behavior for the intended storefronts, restore purchases, entitlement reconciliation, cancellation and account erasure. Current quotas and plan state are read from the existing backend; no new checkout or purchase UI ships in the core local beta.
