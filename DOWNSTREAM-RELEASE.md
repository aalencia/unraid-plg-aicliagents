# Maintained downstream runtime fix

This fork's `downstream/runtime-boot-fix` branch packages the source fix from
upstream PR #34 for an existing layout-1 installation. It is separately maintained
and is not an official upstream release. The upstream PR branch stays source-only.

Prepared release version: **2026.10.29.02**; tag: **downstream-2026.10.29.02**.
See `downstream-release.json` for the exact source commit and artifact digests.

Version 2026.10.29.01 was rejected before activation because its readiness check
assumed `unsquashfs -version` returns zero. The pinned 4.5 executable prints its
version and returns one. Version .02 accepts zero or one only with the expected
unsquashfs version banner; timeouts, loader errors and other failures remain fatal.
The .01 tag is retained unchanged for evidence, not recommended for installation.

During a live update, preflight requires the existing plugin, matching layout,
no migration request, configured HOME/Agent Storage directories and mounted storage.
The package saves the original descriptor and source pointer under the plugin's
`downstream-rollback/2026.10.29.02` cache directory and retains older versioned
payloads. Runtime checks precede generation activation. The live-update mode then
exits before cleanup, storage/service initialization or any background worker.
The original service processes and captured generations remain available.

At boot, the standard initialization path reconstructs runtime and services using
the persisted layout-1 marker. This downstream release suppresses the unrelated
Gemini/Btrfs migration entry points and refuses a migration sentinel or unknown
layout. It is not a migration tool or a fresh-install package.

The build tool reconstructs the published archive member set with committed source
bytes and original modes, recomputes every `.plg` FILE SHA256, and pins all downloads
and fallback URLs to this fork's release tag. Do not move or overwrite a published
tag. Future changes require a new version/tag and regenerated artifacts. The
descriptor points to the pinned fork tag, so returning to upstream releases is an
explicit operator action after the upstream fix ships.

Validation includes the 15 source fault tests, actual packaged engine/runtime in
an isolated Linux root (empty tmux transfer, successful pinned tmux, repeat update),
the exact pinned Slackware SquashFS executables, unchanged HOME/Agent Storage
sentinels, executed PHP launch guards and INI parsing,
and the full live `.plg` shell flow with mount/INI-reader fixtures. Separate
independent review verifies archive content/modes, all 12 pins and negative
preflight cases. These tests do not claim a native Unraid reboot or full lifecycle
concurrency proof. Validate live layout and storage before installing; do not
reboot production as a fault-injection test.

`runtime-readonly-preflight.plg` is a diagnostic run through the authorized plugin
runner because the API does not expose arbitrary installed script reads. It only
reads source hashes, layout, configured mount paths, available space and lock state.
It deliberately exits nonzero after `AICLI_PREFLIGHT_PASS`, so Unraid does not
register it as an installed plugin. The operation's FAILED status is expected;
the explicit PASS marker is the diagnostic result.

Rollback uses the retained original descriptor and versioned artifacts via the
normal plugin installer. Confirm same-layout eligibility first and retain the
current source generation. Do not uninstall, run Repair Plugin, modify HOME/Agent
Storage, or restore user data as part of code/runtime rollback. Capture operation
logs and postflight source/runtime hashes for either installation or rollback.
