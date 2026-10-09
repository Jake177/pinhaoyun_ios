# PinHaoYun iOS

Native SwiftUI iPhone client, iOS 17+, Simplified Chinese and English. Version 0.2 is a personal-device automatic-backup beta using separate Sydney AWS resources. Production Web accounts and storage remain untouched.

## Run

Open `PinHaoYun.xcodeproj`, select the `PinHaoYun` scheme, then build for a simulator or paired iPhone. The development configuration points to the isolated HTTPS API:

`https://tqf3pxrgwm.ap-southeast-2.awsapprunner.com`

For physical devices, sign into Xcode and choose your own Personal Team. Put local overrides in ignored `Config/Local.xcconfig`:

```text
DEVELOPMENT_TEAM = YOUR_PERSONAL_TEAM_ID
# Optional local simulator API override:
# API_BASE_URL = http:/$()/127.0.0.1:3000
```

Free Personal Team signing supports local device testing and requires periodic re-signing/reinstallation; TestFlight requires Apple Developer Program membership. Xcode's signing account and the iPhone's iCloud account can differ. Developer Mode and the developer certificate must be trusted on the device.

To run the companion backend locally with its ignored development environment:

```sh
cd ../PinHaoYun_backend
pnpm install --frozen-lockfile
pnpm exec next dev --hostname 127.0.0.1 --port 3000 --webpack
```

Hosted development registration is restricted to the configured test email allowlist. Read and acknowledge the visibly marked draft policies before using this beta. Do not place AWS credentials, client secrets, tokens or private test details in tracked files or the app bundle.

## Capabilities

- Email authentication, registration/verification, password reset, refresh and explicit server-recorded policy acknowledgement.
- Password reset uses email → code → matching new-password/confirmation pages. As agreed, Cognito verifies the code at final save; incorrect/expired codes return to the code page.
- Capture-time photo/video library, Live Photo preview, original downloads/sharing, cloud deletion and storage/plan display.
- Durable multipart transfers with recovery, retry, cancellation and background URLSession. Limits remain 2GB per original and 10MiB per part. Manual original preparation requires keeping the app open until enqueue.
- Automatic backup under **Account → Automatic backup**, with status and waiting reasons in Transfers. Default off, only newly accessible assets, videos off, Wi-Fi only, no daily window. Enabling asks for explicit scope confirmation.
- Existing-photo opt-in, independent video and cellular options, and a local-time daily window that can cross midnight and follows timezone/DST changes. Started items may finish outside the window.
- PhotoKit baseline IDs and incremental reconciliation include old photos imported later. Limited access processes only selected assets; hidden/unsupported/oversized originals are excluded or show a reason. Live Photo image and motion stay one backup item regardless of the video switch.
- Per-account/environment settings and ledger, at most three staged automatic items, cancellable original streaming, storage checks and local-file cleanup. Turning backup off preserves automatic progress; manual work runs independently. Sign-out cancels unfinished transfers and turns backup off.
- Cloud deletion suppresses automatic re-upload by content fingerprint; manual restoration remains available. Device Photos deletion does not delete cloud copies.
- Account erasure with reauthentication, immediate access blocking, async cleanup and a durable receipt. The isolated test account is separate from production; production compatibility covers shared Web/iOS accounts.
- Local beta diagnostics export contains execution times, device/network state and counts, without photos, email, filenames or credentials. Diagnostics are not uploaded automatically.

iOS schedules background work and cannot guarantee a precise start or work after force quit. Reopening resumes checks. Actual PhotoKit/iCloud/background behavior requires the physical-device acceptance process below.

## Validation and infrastructure

Current evidence: **46 backend tests**, TypeScript and changed-file lint pass; **15 native tests pass on iPhone 12/iOS 27.2 and the small iOS 26.5 simulator**, including two explicitly enabled synthetic-cloud transport checks. Hosted lifecycle integration verifies byte integrity, exact quota, owner/token isolation, Web Cookie compatibility, deletion suppression, late-event cleanup, concurrent duplicates, lost-init response replay and completed-original recovery/cancellation. Synthetic tests do not establish authentic Live Photo export or background scheduling reliability.

- `infra/template.py` / `scripts/deploy-staging.mjs`: isolated Cognito, S3, DynamoDB, queues, processing/erasure functions and alarms. Reuses immutable processing layers with scoped IAM and 14-day Lambda logs.
- `infra/api-template.py` / `scripts/deploy-api.mjs`: ECR, CodeBuild and manually deployed API-only App Runner, 0.5 vCPU, 1GB, maximum one instance. Container checks run before publication. Secrets are read at runtime.
- `scripts/integration-test.mjs`, `backup-integration-test.mjs`, `erasure-test.mjs` and `erasure-completion.mjs`: disposable isolated fixtures only. Configuration/credentials/proofs use ignored local files with mode `0600`.

Use Product → Test for the 13 local regression checks. Two cloud checks skip unless synthetic fixture credentials and the approved development endpoint are supplied as `TEST_RUNNER_PH_INTEGRATION_EMAIL`, `TEST_RUNNER_PH_INTEGRATION_PASSWORD`, `TEST_RUNNER_PH_INTEGRATION_BASE_URL`. They restore the prior Keychain session. Simulator visual QA may explicitly set `TEST_RUNNER_PH_KEEP_QA_SESSION=1`; physical-device tests always restore the prior session.

After adding source/resource files, run `python3 scripts/generate-project.py` to maintain stable Xcode references. There are no third-party Swift packages.

See [device acceptance](docs/DEVICE-ACCEPTANCE.md), [API contract](docs/API.md), [release evidence](docs/RELEASE.md) and [infrastructure status](infra/STATUS.md). Authentic Photos/iCloud tests and three days of real-device records are pending. Operator/contact details and final policies, membership, TestFlight, production rollout, maps and purchases remain later gates.
