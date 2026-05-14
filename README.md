# proto

Shared protobuf schemas for the `altessa-s` ecosystem. Schemas defined
here are language-agnostic and reusable across services; they are not
tied to any one application.

## Schemas

| Package | File | Description |
|---------|------|-------------|
| `io.altessa.badrequest.v1` | [`badrequest/v1/badrequest.proto`](badrequest/v1/badrequest.proto) | `BadRequest` / `FieldViolation` error detail messages (typically used as the detail payload for `google.rpc.Status` with `INVALID_ARGUMENT`). |
| `io.altessa.serviceinfo.v1` | [`serviceinfo/v1/serviceinfo.proto`](serviceinfo/v1/serviceinfo.proto), [`serviceinfo/v1/serviceinfo_service.proto`](serviceinfo/v1/serviceinfo_service.proto) | `ServiceInfo` runtime metadata + `ServiceInfoService` RPC for service introspection. |

## Generated bindings

CI publishes generated bindings to dedicated per-language repositories
(populated automatically on every push to `main` / `develop` and every
`vX.Y.Z` tag):

| Language   | Repository | Module / coordinates |
|------------|------------|----------------------|
| Go         | [`altessa-s/proto-gen-go`](https://github.com/altessa-s/proto-gen-go) | `github.com/altessa-s/proto-gen-go` |
| Java       | [`altessa-s/proto-gen-java`](https://github.com/altessa-s/proto-gen-java) | Maven artifact in GitHub Packages |
| Swift      | [`altessa-s/proto-gen-swift`](https://github.com/altessa-s/proto-gen-swift) | SwiftPM package (messages only — see repo README) |
| TypeScript | [`altessa-s/proto-gen-typescript`](https://github.com/altessa-s/proto-gen-typescript) | npm `@altessa-s/proto-gen-typescript` in GitHub Packages |
| PHP (classic) | [`altessa-s/proto-gen-php`](https://github.com/altessa-s/proto-gen-php) | Composer (VCS); uses PECL `grpc` extension |
| PHP (RoadRunner) | [`altessa-s/proto-gen-php-rr`](https://github.com/altessa-s/proto-gen-php-rr) | Composer (VCS); uses `spiral/roadrunner-grpc` |

Versioning is **tag-driven semver + branch snapshot** — see
[`docs/release.md`](docs/release.md) for the developer flow.

## Local generation

```
make proto          # all languages
make proto-go       # ephemeral; mirror of what CI publishes to proto-gen-go
make proto-java
make proto-swift
make proto-typescript
make proto-php
make proto-php-rr
```

Generated output lands under `gen/<lang>/` (gitignored).

## Linting + breaking-change checks

```
buf lint
buf breaking --against '.git#branch=main'
```

Both run automatically in CI for every PR touching schema files.

## License

MIT — see [LICENSE](LICENSE).
