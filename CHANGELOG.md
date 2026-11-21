# Changelog

## 3.0.0 - 2026-11-21

### Breaking changes

- Require Crystal >= 1.22.0 and < 2.0.0.
- Replace legacy parameter declarations with typed request-validation contracts.
- Preserve native structured-body types and explicit parameter decoding modes.
- Use unified template configuration and action-relative rendering conventions.

### Request handling

- Validate nested contracts, arrays and schema field constraints.
- Share request parsing and body limits across native contract entry points.
- Support temporary streamed uploads and atomic file persistence.
- Mount static directories with path containment and cache handling.
- Resolve request base addresses and client addresses through explicit trusted
  proxy configuration; provider-specific headers are opt-in.
- Add configurable pagination with consistent query and in-memory offsets.

### Rendering and server lifecycle

- Support explicit partial locals and native nested values through jbuilder.
- Add explicit empty responses and custom handler/action dependency injection.
- Validate paired server certificates and parse boolean server configuration.
- Preserve opaque request identifiers and report original exception chains.
- Drain in-flight requests during graceful shutdown before releasing resources.

### Dependencies

- Pin jbuilder to release 1.1.0.
- Pin private request-validation to release 0.1.0; authorized repository access
  is required for installation. Its source is not redistributed by Runcobo.
- Keep crsql as a development-only generator; applications have no runtime
  dependency on crsql, sqlc or Go.
