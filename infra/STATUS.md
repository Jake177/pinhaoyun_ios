# Isolated beta implementation status

Current branches: `pinhaoyun_ios` → `feat/ios-auto-backup`, companion `PinHaoYun_backend` → `feat/mobile-backup`, based on `feat/ios-core` / `feat/mobile-api`. Parent draft PRs are iOS #1 and backend #3. No production deployment, merge or TestFlight publication is included.

Version 0.2 implements manual and automatic original backup, device-local time windows, Wi-Fi/cellular policy, persistent per-account/environment settings and ledger, streaming/bounded preparation, retry/recovery and cloud-delete suppression. It retains auth/library/media management, quota, bilingual policy acknowledgement and account erasure. The updated draft policy is `2026-10-09-beta-2`; `POLICIES_APPROVED` remains false.

Sydney development stacks:

- `pinhaoyun-ios-dev` and `pinhaoyun-ios-dev-artifacts`: separate user pool/clients, buckets, DynamoDB media/deletion tables, queues/DLQs, processing/erasure functions and alarms. Immutable ImageMagick/ffmpeg layers are reused; processing has 3 GiB scratch storage and 14-day Lambda logs.
- `pinhaoyun-ios-dev-api`: scoped roles, ECR with immutable image tags, CodeBuild and an App Runner scaling configuration.
- `pinhaoyun-ios-dev-api-service`: manual deployment, API-only HTTPS, 0.5 vCPU, 1GB, minimum/maximum one instance. Runtime secrets use server roles. Test registration is allowlisted; no frontend pages are served.

API: `https://tqf3pxrgwm.ap-southeast-2.awsapprunner.com`. Health route: `/api/mobile/health`; protected routes retain shared Cookie/Bearer verification. Build runs 46 tests, a production Next.js standalone build, then container health/root-404/unauthenticated-profile checks before ECR publication.

At the verified Sydney prices, 30 days always provisioned costs about US$6.13 for 1GB memory; two active hours per day at 0.5 vCPU adds about US$2.33, for US$8.46 before builds, logs, media, processing and transfer. These are example usage calculations, not a billing cap. [AWS regional pricing](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSAppRunner/current/ap-southeast-2/index.json).

Validated: backend 46 tests, TypeScript and changed-file lint; native 15 tests on iPhone 12/iOS 27.2 and small iOS 26.5 simulator. The two native cloud cases use generated PNGs. Hosted lifecycle proof includes original integrity, exact quota, identity/ownership, Cookie compatibility, invalid Bearer rejection, deleted-content skip, concurrent duplicates, response-loss recovery, completed-but-unfinalized originals and late-event cleanup. Credentials, test email, signing team and raw outputs remain ignored local files.

Personal Team installation works without paid membership. Authentic Live Photo/iCloud export, hardware background behavior and at least three days of device use remain pending; see [device acceptance](../docs/DEVICE-ACCEPTANCE.md). Local diagnostic summaries do not fabricate executions while iOS suspends the app. Operator/contact details, approved policies, Apple membership/TestFlight, maps and purchases remain later work.

Deployment commands always select profile `pinhaoyun`, `ap-southeast-2`, the verified account and development namespace. Source snapshots exclude credentials/environment files. Initial deployment failures were diagnosed from scoped logs; only confirmed empty failed stacks were recovered. Existing production resources are untouched. Erasure workers and media lifecycle guards must remain active independently of client or API rollback.
