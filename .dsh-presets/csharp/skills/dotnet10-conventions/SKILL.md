---
name: dotnet10-conventions
description: >-
  Opinionated C# and .NET 10 coding conventions: Clean Architecture layering, one type per file,
  file-scoped namespaces, primary constructors, camelCase locals with no underscore prefix, plain
  Dapper with hand-written SQL, versioned migrations, soft deletes, and a single LookUp catalog
  table. Use when writing, reviewing, or scaffolding C# code for a .NET 10 project — solution
  structure, entities, repositories, services, handlers, DTOs, mappers, or validators.
license: MIT
---

# .NET 10 Coding Conventions

Source: GuerthCastro/claude-skills-dotnet (MIT). These are strict, opinionated rules built around
Clean Architecture and plain Dapper (no ORM). Adopt whole or fork the rules you disagree with.

## Non-negotiable rules

- One file per class, interface, enum, or record.
- File-scoped namespaces: `namespace Acme.Product.Domain;` — never block-style braces.
- Primary constructors always. No private backing fields unless the field is mutated after
  construction, read by reflection/serialization, or needs guard-clause derivation.
- No XML doc comments (`///`) and no inline comments; the only exception is `// Arrange`, `// Act`,
  `// Assert` in a test body.
- `var` by default; explicit type when the declared type carries weight.
- PascalCase for classes/interfaces/methods/properties; camelCase for private fields, parameters,
  locals. Never `_`-prefix a private field.
- Constants follow visibility: `private const` is camelCase, public/internal is PascalCase.
- No `Async`/`Sync` suffixes, no prefix that restates the type (keep `I` on interfaces, `Controller`/
  `Repository`/`Options`/`Model`/`ViewModel` suffixes).
- One statement per line (initializers and constructor declarations exempt).
- No em dashes in comments. Never change unrequested code (no reformatting as a side effect).

## Solution structure (Clean Architecture)

```
Acme.Product.Api               # ASP.NET Core: controllers, Program.cs, middleware
Acme.Product.Application       # DTOs, service interfaces, handlers, mappers, validators
Acme.Product.Domain            # Entities, repository interfaces, domain enums
Acme.Product.Infrastructure    # Dapper repositories, connection factory, external services
Acme.Product.Migrations        # Versioned SQL scripts, embedded as resources
Acme.Product.Tests/            # Application.Tests / Controller.Tests / Data.Tests / Tests.Common
```

Dependency direction: Api → Application → Domain. Infrastructure implements Domain interfaces and
is wired only at the composition root. Dapper is referenced by Infrastructure only — `using Dapper;`
in Application or Domain means a boundary was crossed.

## Entities (Domain layer)

Plain POCOs, no attributes, no framework base. One shared base you own:

```csharp
public abstract class EntityBase
{
    public long Id { get; set; }
    public Guid EntityKey { get; set; }
    public long CreatedBy { get; set; }
    public DateTime CreatedOn { get; set; }
    public long? UpdatedBy { get; set; }
    public DateTime? UpdatedOn { get; set; }
    public bool IsDeleted { get; set; }
}
```

Rules: `long` surrogate `Id` + `Guid EntityKey` for external exposure (URLs/payloads/logs use
`EntityKey`; `Id` stays inside the DB). Foreign keys are `long`, never `Guid`. Soft delete always
via `IsDeleted` (never `DELETE`). Nullable reference types on — non-nullable strings get
`= string.Empty`. Property name matches column name (alias in SQL, not a global mapper).

## Schema and migrations

Schema lives in SQL in source control, applied by a runner (DbUp/Flyway/Grate), never generated from
attributes or created by the app at startup. One numbered script per change, never edited after it
ships (`0007_add_order_notes.sql`). Forward-only, idempotent. Every table gets the base columns and
indexes on every foreign key and every `WHERE` column; make the soft-delete filter part of the index.

```sql
CREATE TABLE [Order] (
    Id          BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EntityKey   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    CustomerId  BIGINT NOT NULL,
    Reference   NVARCHAR(50) NOT NULL,
    Total       DECIMAL(18,2) NOT NULL,
    CreatedBy   BIGINT NOT NULL,
    CreatedOn   DATETIME2 NOT NULL,
    UpdatedBy   BIGINT NULL,
    UpdatedOn   DATETIME2 NULL,
    IsDeleted   BIT NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX UX_Order_EntityKey ON [Order](EntityKey);
CREATE INDEX IX_Order_CustomerId ON [Order](CustomerId) WHERE IsDeleted = 0;
```

## Data access (Dapper)

Connections come from a factory (`IDbConnectionFactory` in Domain, `SqlConnectionFactory` in
Infrastructure), never a connection string read inside a repository. Repository interfaces live in
Domain and speak entities; implementations live in Infrastructure and own the SQL.

```csharp
public class OrderRepository(IDbConnectionFactory connectionFactory) : IOrderRepository
{
    private const string selectColumns = """
        Id, EntityKey, CustomerId, Reference, Total, Notes,
        CreatedBy, CreatedOn, UpdatedBy, UpdatedOn, IsDeleted
        """;

    public async Task<Order?> GetByKey(Guid entityKey, CancellationToken ct)
    {
        string sql = $"""
            SELECT {selectColumns}
            FROM [Order]
            WHERE EntityKey = @EntityKey AND IsDeleted = 0
            """;
        using IDbConnection connection = await connectionFactory.Create(ct);
        CommandDefinition command = new(sql, new { EntityKey = entityKey }, cancellationToken: ct);
        return await connection.QuerySingleOrDefaultAsync<Order>(command);
    }
}
```

Dapper rules:

- **Parameters always.** Never interpolate a value into SQL; only compile-time constants like
  `selectColumns` may be interpolated.
- Raw string literals (`"""`) for multi-line queries; no `@"..."`, no concatenation.
- `CommandDefinition` so the `CancellationToken` reaches the driver.
- `QuerySingleOrDefaultAsync` for 0-or-1, `QueryFirstOrDefaultAsync` only for ordered/truncated,
  `QuerySingleAsync` when zero rows is a bug.
- Materialize before returning: return `IReadOnlyList<T>`, never leak a live reader.
- No stored procedures for CRUD. Repositories return domain entities, never DTOs.

Multi-result sets: one round trip via `QueryMultipleAsync` + `GridReader`. Joins: `splitOn` with the
split column immediately after the previous entity's last column. Pagination: keyset when large and
ordered, `OFFSET FETCH` for arbitrary page numbers. Transactions: one connection + one transaction
handed down; a multi-repository unit of work owns the transaction at the Application layer.
PostgreSQL: `NpgsqlConnection`, `bigserial`/`uuid`, lowercase names +
`MatchNamesWithUnderscores = true`, `INSERT ... RETURNING Id`.

## LookUp pattern for catalogs

Every catalog/reference list lives in one `LookUp` table discriminated by `LookUpType`, not one
table per catalog:

```sql
CREATE TABLE LookUp (
    Id          BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EntityKey   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    ParentId    BIGINT NULL,
    Name        NVARCHAR(250) NOT NULL,
    Code        NVARCHAR(250) NULL,
    Data        NVARCHAR(MAX) NULL,
    LookUpType  INT NOT NULL,
    CreatedBy   BIGINT NOT NULL,
    CreatedOn   DATETIME2 NOT NULL,
    IsDeleted   BIT NOT NULL DEFAULT 0
);
CREATE INDEX IX_LookUp_Type ON LookUp(LookUpType) WHERE IsDeleted = 0;
```

`LookUpType` is an enum in Infrastructure. Each catalog type still gets its own DTO in Application
and its own mapper, so consumers never see the generic `LookUp` shape.

## Mapping rules

- Pin AutoMapper to 13.0.1 (last MIT version). Static `MapperConfiguration`, every `ForMember`
  explicit, one mapper file per entity/DTO pair. Hand-written extension methods are an acceptable
  substitute; no reflection-based mapping in hot paths.

## Application and Api layers

- Application: `Dtos/`, `Interfaces/`, `Handlers/` — one file each. FluentValidation, one validator
  per DTO/command.
- Api: versioned routes `/api/v1/`, JWT bearer in every environment, thin controllers (binding →
  authorization → handler → status code), route params carry `EntityKey` never `Id`.
- Solution file: prefer `.slnx`; folders `Source/`, `Tests/`, `Documentation/`, `Pipelines/` with
  no numeric prefixes.

## What not to do

- No Entity Framework, no Dapper outside Infrastructure, no block namespaces.
- No SQL interpolation with runtime values; parameters always.
- No physical deletes (soft delete). No schema generated from code at startup.
- No `_`-prefixed private fields, no `Async`/`Sync` suffixes, no em dashes in comments.
- No separate catalog tables (use LookUp). No unrequested edits bundled into a change.
