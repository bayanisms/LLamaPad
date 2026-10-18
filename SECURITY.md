# Security

LlamaPad is a local development application with an experimental RPC integration. Use model files and clients you trust. GGUF parsers, native kernels and RPC process binary inputs and should be treated as security-sensitive components.

RPC has no authentication or encryption. Bind to loopback and use the USB tunnel where possible. Do not expose the worker port to the public Internet. Local-network inference requires an API key but uses plain HTTP; an API key does not encrypt prompts or responses.

The Mac launcher's HTTP API is loopback-only and has no key. Any process with local access may be able to use it. The app's `/health` route is public. Memory budgets reduce allocation pressure but do not isolate untrusted execution or guarantee continued availability.

Keep credentials, signing assets and provisioning profiles outside version control. Build and sign the application using your own account. Re-check dependencies and upstream security updates before distributing a new build.

For a suspected vulnerability, use the repository's private vulnerability-reporting feature when enabled, or contact its maintainers through a private channel they publish. Avoid posting credentials, exploit payloads containing private data, or personal device logs in a public issue.
