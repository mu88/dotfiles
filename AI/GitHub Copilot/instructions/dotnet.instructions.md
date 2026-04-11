---
applyTo: "**/*.cs, **/*.razor, **/*.csproj, **/*.sln, **/*.slnx, **/*.props, **/*.targets"
---

# .NET Conventions

## Project Setup
- Read `Directory.Build.props` for target framework and version. Read `Directory.Packages.props` for NuGet versions. Read `global.json` for SDK version. Read `.config/dotnet-tools.json` for tool versions. NEVER hardcode these values.
- Use Central Package Management — add new packages to `Directory.Packages.props` (version) and project `.csproj` (reference without version).
- Projects might reference `mu88.Shared` NuGet package which provides: OpenTelemetry, Roslyn analyzers (StyleCop, Meziantou, IDisposable), container publishing targets, health checks, SBOM generation.
- Read `.editorconfig` for coding style rules and suppressed analyzer diagnostics before writing code.
- Read `*.DotSettings` for JetBrains Rider-specific code style and inspection settings and also check for referenced settings files.
- Use `dotnet-coverage` (from .NET tool manifest) for coverage collection, NOT `coverlet`.
- Use `dotnet-sonarscanner` (from .NET tool manifest) for SonarQube/SonarCloud analysis.
- Your training data may not include the .NET and C# version this project uses. When the detected version is likely newer than your training cutoff, consult the official "What's New" documentation before implementing: `https://learn.microsoft.com/dotnet/core/whats-new/dotnet-{version}/overview` for runtime and BCL changes, and `https://learn.microsoft.com/dotnet/csharp/whats-new/csharp-{version}` for language features. Prefer new idiomatic APIs and language constructs over patterns you know from older versions.

## Entity Design
- Entities: `class` with a public constructor for required fields and `private set` on all
  properties — nothing mutable after construction unless a domain method explicitly changes it.
  Question every mutable property; prefer immutability by default.
- Configuration via Fluent API in `DbContext.OnModelCreating` — no Data Annotations on entities.
- **Strongly typed IDs on every entity in EF Core projects** (primitive obsession is a bug waiting
  to happen — `TeamId` and `PlayerId` must not be interchangeable at compile time):
  - `readonly record struct FooId(int Value)` with `ToString() => Value.ToString()` in `Domain/Ids/`
  - `[TypeConverter(typeof(FooIdTypeConverter))]` for model binding / JSON
  - EF Core `HasConversion` in `OnModelCreating`
  - Convert primitive → strongly typed ID at the controller boundary only: `new FooId(id)`
- Enums: no `[JsonConverter]` on enum types — configure globally in `Program.cs`.

## DTO Design
- DTOs: `record` with `{ get; init; }` properties — immutable by design. Use Data Annotations for validation on DTOs only.
- Mapping: extension methods (`ToDto()`, `ToEntity()`) in the DTO project, not in controllers.

## Collections
- Use `IEnumerable<T>` when only iterating. Use `IReadOnlyList<T>` only when `Count` or indexer access is needed.
- Remove unnecessary `.ToList()` / `.ToArray()` calls — EF Core and serialization work with `IEnumerable<T>`.

## Testing
- Framework: NUnit + FluentAssertions + NSubstitute.
- Every test method MUST have `// Arrange`, `// Act`, `// Assert` comments (AAA pattern).
- Use `[Category("Unit")]`, `[Category("Integration")]`, or `[Category("System")]` on every test class — CI jobs filter by category.
- System tests use Testcontainers and require Docker. The container image must be built with `dotnet publish` before running them — derive the exact command, flags, target project, and MSBuild targets from the GitHub Actions workflow (including any referenced shared workflow); never guess or construct the command from defaults.
- Aim for near-100% coverage on new code. SonarCloud enforces this on the leak period (= all lines changed or added since the last version tag; legacy code is excluded).
- Zero new Sonar issues on the leak period is a hard quality gate — do not leave open issues for later.
- Test all branches: if/else, switch cases, null paths, and error paths. A test that only hits the happy path is insufficient.
- Write tests for edge cases proactively — empty collections, null inputs, boundary values, concurrent access where applicable.
- When encountering a hard-to-mock API without an interface (e.g. `File`, `Directory`, `Environment`, `DateTime`): apply the Humble Object pattern — introduce a narrow `IFoo` interface and a `Foo : IFoo` wrapper that delegates to the real API. Annotate the wrapper with `[ExcludeFromCodeCoverage]`. Inject `IFoo` everywhere in production code, never the concrete type. Do NOT pull in third-party abstractions libraries (e.g. `System.IO.Abstractions`) unless they are already a project dependency.

## Mutation Testing
- Mutation testing with Stryker.NET validates that tests actually catch bugs, not just execute code.
- If `.stryker-config.json` exists in the repo, run: `dotnet tool run dotnet-stryker`
- A test suite with high line coverage but low mutation score means the tests don't assert meaningfully — fix the assertions, not just the coverage number.

## Configuration
- Use Options Pattern (`IOptions<T>`) for configuration values. Bind sections from `appsettings.json`.
- Inject `TimeProvider` (registered as `TimeProvider.System` singleton) instead of `DateTime.Now` or `DateTimeOffset.UtcNow`.

## CI/CD
- All repos may use a shared reusable workflow from `mu88` — check whether it applies and understand this workflow. Do not duplicate CI logic.
- Renovate config extends `github>mu88/common//renovate/default.json5`. Repo-specific overrides go in `renovate.json5`.
- Release versioning uses Versionize with conventional commits (`chore(release): X.Y.Z`).
- Docker: both regular and chiseled containers are published. `mu88.Shared` handles container family selection based on project properties.
- ALWAYS read the GitHub Actions workflow files in `.github/workflows/` before executing any CI-related command. If they reference shared/reusable workflows from another repository, follow those references and read the shared workflow too — it is the authoritative source for how builds, tests, container publishing, and Sonar scans actually work. Never infer flags or commands from documentation or defaults.
- SonarCloud runs on every branch push via CI. If the branch has already been pushed to GitHub and CI has completed, query the SonarCloud API for that branch's issues and coverage directly instead of running Sonar locally — it is faster, reflects the actual CI result, and requires no local token setup. Derive the project key and organization from the GitHub Actions workflow (they are passed as inputs to the shared workflow).

## Code Style
- Use `Environment.NewLine` for line breaks in string construction, not `\n`.
- Use `is null` / `is not null` instead of `== null` / `!= null` for null checks.
- Declare variables non-nullable by default; add null checks only at entry points (public API boundaries, deserialization). Trust the type system inside the codebase.
- Use `nameof(Member)` instead of string literals when referring to member names (e.g., in exceptions, logging, validation messages).
- Prefer pattern matching and switch expressions over if/else chains and explicit type casts.

## Controllers
- Use `TypedResults` (`TypedResults.Ok()`, `TypedResults.NotFound()`, `TypedResults.Problem()`) — not `IActionResult` or raw `Ok()`.
- Controllers are thin adapters: validate input, call service, map via DTO extension methods, return. No business logic in controllers.
- Route parameters stay as primitive types (`int`, `string`) — convert to strongly typed IDs at the controller boundary: `new FooId(id)`.

## Blazor
- Call `StateHasChanged()` only when Blazor cannot detect the state change automatically — e.g., after async work triggered outside the component lifecycle (timers, external callbacks). Avoid calling it redundantly.
- Override `ShouldRender()` to return `false` for components that receive frequent parameter updates but don't need to re-render every time.

## Async
- All async methods MUST accept `CancellationToken` parameter.
- Thread `CancellationToken` through all service, repository, and data access calls.

## Observability
- Use OpenTelemetry `ActivitySource` for tracing key operations.
- Use `Meter` + `Counter`/`Histogram` for custom metrics.
- `mu88.Shared` auto-configures ASP.NET Core, EF Core, process, and runtime instrumentation.
