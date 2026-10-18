# Contributing

Use the source map in `docs/ARCHITECTURE.md` and the build instructions in `docs/BUILDING.md`. Keep changes focused and describe their user-visible behavior, relevant validation and limits. Review generated code before submitting it and disclose substantial AI assistance where the receiving project's policy requires it.

Application changes belong in the SwiftUI/Core/native layers where possible. Engine changes must preserve the pinned-source relationship and matching app/coordinator behavior. Preserve upstream license headers. Keep the consolidated engine patch current and record separate source-archive adjustments.

Performance changes need repeated comparisons with fixed models, prompts, samplers and settings. Record first-token latency, generation speed, memory pressure and thermal behavior. Compare outputs as well as timings. Keep experimental tuning opt-in until it has been qualified for the intended model and devices.

This release deliberately excludes test suites and private run records. Contributors can use their own validation infrastructure; include concise sanitized results rather than device logs or personal paths. Do not commit models, signing material, cache directories, generated binaries or credentials.

Before packaging your release, regenerate `SOURCE_MANIFEST.json`, verify its hashes and follow `docs/RELEASING.md`. Changes to the upstream project should follow its own contribution policies; this package is an independent integration.
