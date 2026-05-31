# proto

Shared protobuf schemas for the `altessa-s` ecosystem. Everything here is
language-agnostic and reusable across services; nothing is tied to a single
application. CI publishes generated bindings for six languages to dedicated
per-language repositories (see [Generated bindings](#generated-bindings)).

## Repository layout

```
services/
  badrequest/v1/        # error-detail payload for INVALID_ARGUMENT
  serviceinfo/v1/       # runtime service-introspection RPC
type/v1/               # general-purpose value types (Contact, FileRef, …)
```

`services/<name>/v1/` holds an RPC contract plus any messages it needs.
`type/v1/` is a flat collection of small, reusable value types that have
no Google-published equivalent.

## Conventions

These apply uniformly to every schema in this repo.

- **proto3** with explicit `optional` on nullable scalar fields.
- Field names are `snake_case`; messages and enums are `PascalCase`.
- Each file declares `package io.altessa.<name>.v1;` matching its
  directory, plus consistent `go_package`, `java_package`,
  `java_multiple_files = true`, and an MIT license header.
- **Reuse Google common types** before defining our own. Where a concept
  has a canonical [`google.type.*`](https://github.com/googleapis/googleapis/tree/master/google/type)
  or [`google.protobuf.*`](https://protobuf.dev/reference/protobuf/google.protobuf/)
  message — `LatLng`, `PostalAddress`, `Money`, `Date`, `Timestamp`,
  `Duration`, … — we use it directly.
- **No string dates / int64 epochs.** Wall-clock moments are
  `google.protobuf.Timestamp`; calendar dates are `google.type.Date`;
  durations are `google.protobuf.Duration`.
- **Field semantics via [`(google.api.field_behavior)`](https://google.aip.dev/203).**
  We tag fields as `REQUIRED` / `OUTPUT_ONLY` / `IMMUTABLE` instead of
  shipping `*Create` / `*Update` companion messages — callers and codegen
  tools derive the create/update/`FieldMask` contracts from the
  annotations.
- No custom validation extensions. Standard `(google.api.field_behavior)`
  is enough; documented invariants (e.g. "end_date MUST be ≥ start_date")
  are enforced by producers.

### Design notes (deliberate AIP deviations)

- **`id` vs `name` ([AIP-148](https://google.aip.dev/148)).** Value types
  in `type/v1` use `string id` for stable identifiers of sub-entries
  (e.g. one element of a `repeated Contact` list). They are NOT
  resources in [AIP-122](https://google.aip.dev/122)/148 sense — there
  is no per-Contact CRUD RPC namespace, and no `google.api.resource`
  annotation. If a value type is ever promoted to a first-class
  resource with CRUD methods, that promotion will be done in a new
  package (`io.altessa.<name>.v1`) and will introduce a `string name`
  field per AIP-148; the original value type keeps its `id` shape
  unchanged.
- **Pagination `offset` extension ([AIP-158](https://google.aip.dev/158)).**
  `type/v1/Pagination` follows AIP-158 for `page_size` and `page_token`
  but additionally carries an `int32 offset` field. AIP-158 discourages
  offset-based pagination; we keep it because some collections
  (small, slow-changing, admin-only) are easier to navigate by offset
  than by minting opaque tokens. `page_token` and `offset` are mutually
  exclusive.
- **`SortDirection` zero value ([AIP-126](https://google.aip.dev/126)).**
  `SORT_DIRECTION_ASC = 0` is the natural default; a separate
  `_UNSPECIFIED` sentinel would add noise without information. Lint
  waiver in `buf.yaml`.

### Backwards-compatibility posture (AIP-180)

Until `vX.0.0` is tagged on `main`, schemas under `type/v1/` and
`services/<name>/v1/` are mutable and may be reshaped freely. **After
the first `vX.0.0` tag**, every package is frozen per
[AIP-180](https://google.aip.dev/180): no field removal, no type
changes, no renumbering, no movement into/out of `oneof`. Wire-breaking
evolution happens by adding a `v2` package alongside `v1`.

## Schemas

| Package | Files | Purpose |
|---|---|---|
| `io.altessa.badrequest.v1` | [`services/badrequest/v1/`](services/badrequest/v1/) | `BadRequest` / `FieldViolation` error-detail payload for `google.rpc.Status` with `INVALID_ARGUMENT`. |
| `io.altessa.serviceinfo.v1` | [`services/serviceinfo/v1/`](services/serviceinfo/v1/) | `ServiceInfo` runtime metadata + `ServiceInfoService.Get` RPC for service introspection. |
| `io.altessa.type.v1` | [`type/v1/`](type/v1/) | General-purpose value types — see [type/v1](#typev1). |

## services/badrequest/v1

A structured error-detail contract for requests that fail input
validation. It is designed to be carried as the detail payload of a
`google.rpc.Status` with code `INVALID_ARGUMENT`, so a single failed call
can report every offending field at once instead of bailing on the first.

A `BadRequest` carries a list of `FieldViolation`s. Each violation has:

- `field_path` — dotted/indexed path for humans
  (`"user.address.street"`, `"items[2].name"`).
- `message` — human-readable explanation.
- `code` — application-specific stable identifier (e.g. `"too_short"`,
  `"not_unique"`), suitable for client-side i18n or branching logic.
- `field_path_components` — the same path in structured form (field
  number, name, type, repeated index, map key), so clients can locate the
  field programmatically without parsing the string path.

The `FieldType` enum mirrors `google.protobuf.FieldDescriptorProto.Type`
as an open proto3 enum, which keeps the schema usable from PHP and other
generators that disallow proto2 closed-enum dependencies.

### Server (Go)

Attach a `BadRequest` to an `INVALID_ARGUMENT` status using
`google.golang.org/grpc/status`:

```go
import (
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
    "google.golang.org/protobuf/proto"

    badrequestv1 "github.com/altessa-s/proto-gen-go/services/badrequest/v1"
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

    badrequestv1 "github.com/altessa-s/proto-gen-go/services/badrequest/v1"
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

## services/serviceinfo/v1

A uniform runtime-introspection contract every service in the ecosystem
can expose. A single RPC —
`ServiceInfoService.Get(google.protobuf.Empty) returns (ServiceInfo)` —
returns identity (`service_name`, `service_description`, `service_id`),
version (`full_version` plus structured `SemanticVersion`), build
provenance (`build_time`, `branch`, `commit`, `build_tags`), liveness
(`start_time`, `uptime`), distributed-leadership status (`leader`,
`leader_id`), and arbitrary `metadata` for service-specific tags.

Every field on `ServiceInfo` is tagged `OUTPUT_ONLY` — clients never set
them. Time-shaped fields use the canonical types:

- `build_time`, `start_time` — `google.protobuf.Timestamp`
- `uptime` — `google.protobuf.Duration`

Typical uses: a `/info`-style diagnostic endpoint on prod, correlating
logs and metrics with the exact build that produced them, and discovering
the active leader from any follower in a clustered deployment.

### Server (Go)

```go
import (
    "context"
    "time"

    "google.golang.org/grpc"
    "google.golang.org/protobuf/proto"
    "google.golang.org/protobuf/types/known/durationpb"
    "google.golang.org/protobuf/types/known/emptypb"
    "google.golang.org/protobuf/types/known/timestamppb"

    serviceinfov1 "github.com/altessa-s/proto-gen-go/services/serviceinfo/v1"
)

type Server struct {
    serviceinfov1.UnimplementedServiceInfoServiceServer
    buildTime time.Time
    startedAt time.Time
}

func (s *Server) Get(ctx context.Context, _ *emptypb.Empty) (*serviceinfov1.ServiceInfo, error) {
    return &serviceinfov1.ServiceInfo{
        ServiceName: "billing-api",
        ServiceId:   proto.String("billing-api-7c9f"),
        Leader:      true,
        FullVersion: "1.4.2+build.873",
        SemanticVersion: &serviceinfov1.ServiceInfo_SemanticVersion{
            Major: 1, Minor: 4, Patch: 2,
        },
        BuildTime: timestamppb.New(s.buildTime),
        Branch:    proto.String("main"),
        Commit:    proto.String("a1b2c3d4e5f6"),
        StartTime: timestamppb.New(s.startedAt),
        Uptime:    durationpb.New(time.Since(s.startedAt)),
    }, nil
}

func register(g *grpc.Server, srv *Server) {
    serviceinfov1.RegisterServiceInfoServiceServer(g, srv)
}
```

`proto.String` comes from `google.golang.org/protobuf/proto` and is the
idiomatic way to set proto3 `optional` scalar fields. `timestamppb.New` /
`durationpb.New` build the well-known wrappers from `time.Time` and
`time.Duration` respectively.

### Client (grpcurl)

```bash
grpcurl -plaintext \
  -proto services/serviceinfo/v1/serviceinfo_service.proto \
  -import-path . \
  localhost:9090 \
  io.altessa.serviceinfo.v1.ServiceInfoService/Get
```

If the server registers gRPC reflection, drop `-proto` and `-import-path`
and call the method directly.

## type/v1

A flat collection of small, domain-neutral value types reused across
services.

| Message / Enum | Use it for | Notes |
|---|---|---|
| [`Contact`](type/v1/contact.proto) | Generic contact endpoint with a stable `id` and a typed `value` oneof (`email` / `phone` / `social_handle`) | `phone` is a `google.type.PhoneNumber`, so country code and extension are preserved structurally. `id` lets parent messages address a single entry in a `repeated Contact` list for partial updates. |
| [`DatePeriod`](type/v1/date_period.proto) | Calendar-date range, inclusive on both ends (billing periods, leave windows, …) | Composed of two `google.type.Date`. Use `google.type.Interval` for wall-clock ranges. |
| [`DocumentRef`](type/v1/document_ref.proto) | User-facing document = file + display title/description | Wraps `FileRef`. |
| [`FileRef`](type/v1/file_ref.proto) | Reference to a file held in object storage / CDN, with optional metadata | Storage-agnostic — no bucket / backend identifier. |
| [`Gender`](type/v1/gender.proto) | Minimal biological-sex enum | Intentionally limited to `UNSPECIFIED` / `MALE` / `FEMALE`. Extend in downstream schemas if richer identity is needed. |
| [`Label`](type/v1/label.proto) | Short text tag with stable id and optional display color | Color is `google.type.Color`. |
| [`LocationPrivacy`](type/v1/location_privacy.proto) | Privacy / coarsening level applied to a user's geolocation before exposure | Coarsening is the producer's responsibility. |
| [`MoneyRange`](type/v1/money_range.proto) | Inclusive range between two monetary amounts | Both bounds use `google.type.Money` and must share the same `currency_code`. |
| [`OrganizationType`](type/v1/organization_type.proto) | Coarse legal form: individual entrepreneur vs registered legal entity | Jurisdiction-specific subtypes belong in domain schemas. |
| [`Pagination`](type/v1/pagination.proto) | List-request pagination parameters | Field names and types follow [AIP-158](https://google.aip.dev/158): `int32 page_size` + `string page_token`. Adds an `int32 offset` for token-inconvenient collections; `page_token` and `offset` are mutually exclusive. |
| [`SortDirection`](type/v1/sort_direction.proto) | Ordering direction for list responses | `SORT_DIRECTION_ASC` is the default. |

### Go example

```go
import (
    "google.golang.org/genproto/googleapis/type/date"

    typev1 "github.com/altessa-s/proto-gen-go/type/v1"
)

period := &typev1.DatePeriod{
    StartDate: &date.Date{Year: 2026, Month: 5, Day: 1},
    EndDate:   &date.Date{Year: 2026, Month: 5, Day: 31},
}
```

## Generated bindings

CI publishes generated bindings to dedicated per-language repositories,
populated automatically on every push to `main` / `develop` and every
`vX.Y.Z` tag.

| Language | Repository | Module / coordinates |
|---|---|---|
| Go | [`altessa-s/proto-gen-go`](https://github.com/altessa-s/proto-gen-go) | `github.com/altessa-s/proto-gen-go` |
| Java | [`altessa-s/proto-gen-java`](https://github.com/altessa-s/proto-gen-java) | Maven artifact in GitHub Packages |
| Swift | [`altessa-s/proto-gen-swift`](https://github.com/altessa-s/proto-gen-swift) | SwiftPM package (messages only — see repo README) |
| TypeScript | [`altessa-s/proto-gen-typescript`](https://github.com/altessa-s/proto-gen-typescript) | npm `@altessa-s/proto-gen-typescript` in GitHub Packages |
| PHP (classic) | [`altessa-s/proto-gen-php`](https://github.com/altessa-s/proto-gen-php) | Composer (VCS); uses PECL `grpc` extension |
| PHP (RoadRunner) | [`altessa-s/proto-gen-php-rr`](https://github.com/altessa-s/proto-gen-php-rr) | Composer (VCS); uses `spiral/roadrunner-grpc` |

**Versioning.** Tag `vX.Y.Z` on `main` produces a SemVer release in every
language repo. Pushes to `main` and `develop` publish branch snapshots
under matching branches in each language repo.

## Build & lint

This repo's schemas depend on
[`buf.build/googleapis/googleapis`](https://buf.build/googleapis/googleapis)
for `google/type/*`, `google/api/field_behavior.proto`, etc. Fetch the
dependency once before lint or generation:

```
buf dep update
```

Then:

```
buf lint
buf breaking --against '.git#branch=main'

make proto          # all languages
make proto-go       # ephemeral; mirror of what CI publishes to proto-gen-go
make proto-java
make proto-swift
make proto-typescript
make proto-php
make proto-php-rr
```

Generated output lands under `gen/<lang>/` (gitignored). `buf lint` and
`buf breaking` run automatically in CI for every PR touching schema
files.

## License

MIT — see [LICENSE](LICENSE).
