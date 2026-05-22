# proto

Shared protobuf schemas for the `altessa-s` ecosystem. Schemas defined
here are language-agnostic and reusable across services; they are not
tied to any one application.

## Schemas

| Package | File | Description |
|---------|------|-------------|
| `io.altessa.badrequest.v1` | [`badrequest/v1/badrequest.proto`](badrequest/v1/badrequest.proto) | `BadRequest` / `FieldViolation` error detail messages (typically used as the detail payload for `google.rpc.Status` with `INVALID_ARGUMENT`). |
| `io.altessa.serviceinfo.v1` | [`serviceinfo/v1/serviceinfo.proto`](serviceinfo/v1/serviceinfo.proto), [`serviceinfo/v1/serviceinfo_service.proto`](serviceinfo/v1/serviceinfo_service.proto) | `ServiceInfo` runtime metadata + `ServiceInfoService` RPC for service introspection. |

## BadRequest

`io.altessa.badrequest.v1` is a structured error-detail contract for requests
that fail input validation. It's designed to be carried as the detail payload
of a `google.rpc.Status` with code `INVALID_ARGUMENT`, so a single failed call
can report every offending field at once instead of bailing on the first one.

A `BadRequest` carries a list of `FieldViolation`s. Each violation has:

- `field_path` — dotted/indexed path for humans (`"user.address.street"`,
  `"items[2].name"`).
- `message` — human-readable explanation.
- `code` — application-specific stable identifier (e.g. `"too_short"`,
  `"not_unique"`), suitable for client-side i18n or branching logic.
- `field_path_components` — the same path in structured form (field number,
  name, type, repeated index, map key), so clients can locate the field
  programmatically without parsing the string path.

The `FieldType` enum mirrors `google.protobuf.FieldDescriptorProto.Type` as an
open proto3 enum, which keeps the schema usable from PHP and other generators
that disallow proto2 closed-enum dependencies.

### Server (Go)

Attach a `BadRequest` to an `INVALID_ARGUMENT` status using
`google.golang.org/grpc/status`:

```go
import (
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
    "google.golang.org/protobuf/proto"

    badrequestv1 "github.com/altessa-s/proto-gen-go/badrequest/v1"
)

func invalidArgument(violations ...*badrequestv1.FieldViolation) error {
    st := status.New(codes.InvalidArgument, "request validation failed")
    detail := &badrequestv1.BadRequest{FieldViolations: violations}
    st, err := st.WithDetails(detail)
    if err != nil {
        return status.Error(codes.Internal, "failed to attach error detail")
    }
    return st.Err()
}

// Example: reject a CreateUser request with two field problems.
func validateCreateUser(req *CreateUserRequest) error {
    return invalidArgument(
        &badrequestv1.FieldViolation{
            FieldPath: proto.String("user.email"),
            Message:   proto.String("must be a valid email address"),
            Code:      proto.String("invalid_format"),
        },
        &badrequestv1.FieldViolation{
            FieldPath: proto.String("user.age"),
            Message:   proto.String("must be >= 18"),
            Code:      proto.String("out_of_range"),
        },
    )
}
```

### Client (Go)

Unpack the detail from any returned `error`:

```go
import (
    "google.golang.org/grpc/status"

    badrequestv1 "github.com/altessa-s/proto-gen-go/badrequest/v1"
)

if st, ok := status.FromError(err); ok {
    for _, d := range st.Details() {
        if br, ok := d.(*badrequestv1.BadRequest); ok {
            for _, v := range br.GetFieldViolations() {
                log.Printf("field=%s code=%s msg=%s",
                    v.GetFieldPath(), v.GetCode(), v.GetMessage())
            }
        }
    }
}
```

## ServiceInfo

`io.altessa.serviceinfo.v1` is a uniform runtime-introspection contract every
service in the ecosystem can expose. A single RPC —
`ServiceInfoService.Get(google.protobuf.Empty) returns (ServiceInfo)` — returns
identity (`service_name`, `service_description`, `service_id`), version
(`full_version` plus structured `SemanticVersion`), build provenance
(`build_time`, `branch`, `commit`, `build_tags`), liveness (`start_time`,
`uptime`), distributed-leadership status (`is_leader`, `leader_id`), and
arbitrary `metadata` for service-specific tags.

Typical uses: a `/info` style diagnostic endpoint on prod, correlating logs and
metrics with the exact build that produced them, and discovering the active
leader from any follower in a clustered deployment.

### Server (Go)

Using the published Go bindings from
[`proto-gen-go`](https://github.com/altessa-s/proto-gen-go):

```go
import (
    "context"
    "time"

    "google.golang.org/grpc"
    "google.golang.org/protobuf/proto"
    "google.golang.org/protobuf/types/known/emptypb"

    serviceinfov1 "github.com/altessa-s/proto-gen-go/serviceinfo/v1"
)

type Server struct {
    serviceinfov1.UnimplementedServiceInfoServiceServer
    startedAt time.Time
}

func (s *Server) Get(ctx context.Context, _ *emptypb.Empty) (*serviceinfov1.ServiceInfo, error) {
    return &serviceinfov1.ServiceInfo{
        ServiceName: "billing-api",
        ServiceId:   proto.String("billing-api-7c9f"),
        IsLeader:    true,
        FullVersion: "1.4.2+build.873",
        SemanticVersion: &serviceinfov1.ServiceInfo_SemanticVersion{
            Major: 1, Minor: 4, Patch: 2,
        },
        BuildTime: "2026-05-10T11:22:03Z",
        Branch:    proto.String("main"),
        Commit:    proto.String("a1b2c3d4e5f6"),
        StartTime: proto.String(s.startedAt.UTC().Format(time.RFC3339)),
        Uptime:    proto.Uint64(uint64(time.Since(s.startedAt).Seconds())),
    }, nil
}

func register(g *grpc.Server, srv *Server) {
    serviceinfov1.RegisterServiceInfoServiceServer(g, srv)
}
```

`proto.String` / `proto.Uint64` come from `google.golang.org/protobuf/proto`
and are the idiomatic way to set proto3 `optional` scalar fields.

### Client (grpcurl)

```bash
grpcurl -plaintext \
  -proto serviceinfo/v1/serviceinfo_service.proto \
  -import-path . \
  localhost:9090 \
  io.altessa.serviceinfo.v1.ServiceInfoService/Get
```

If the server registers gRPC reflection, drop `-proto` and `-import-path` and
call the method directly.

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
