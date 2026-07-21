# ADR 0010: Snippet Persistence Model

## Status

Accepted

## Context

Phase 2 requires users to organize reusable plain-text snippets into folders,
preserve user-defined ordering, and later edit, import, display, and paste those
snippets. Issue #32 provides only the persistent foundation; editor behavior,
reordering operations, Clipy XML import, viewer integration, and paste dispatch
remain separate delivery slices.

Yank already stores clipboard history in SwiftData. The local `Yank.store` may
contain Phase 1 `ClipItem` rows that must survive the additive Phase 2 schema
change.

## Decision

Add two SwiftData models:

- `SnippetFolder` stores `title`, `sortOrder`, and its `snippets` relationship.
- `Snippet` stores `title`, plain-text `content`, `sortOrder`, and a `folder`
  relationship. Creation requires a folder, while the persisted inverse is
  optional so SwiftData can clear it while cascading a folder deletion.

Folder order is global. Snippet order is scoped to a folder. Both use ascending,
zero-based, dense `Int` values as their normalized representation. The models
store the values but do not validate or renumber them; the snippet editor will
own those operations.

Deleting a folder cascades to its snippets. Yank does not intentionally create
unfiled snippets: the initializer requires a folder, even though SwiftData's
persisted inverse must accept `nil` during cascade processing. Use SwiftData's
`PersistentIdentifier` rather than adding domain UUIDs. Do not add repositories,
CRUD services, or import-specific metadata in this slice.

Register `ClipItem`, `SnippetFolder`, and `Snippet` in the application schema.
Because this change only adds entities and relationships, use SwiftData's
automatic lightweight migration rather than introducing `VersionedSchema` or a
custom migration plan. An on-disk test must prove that a store created with the
Phase 1 schema reopens with the expanded schema while retaining its existing
`ClipItem` data.

## Consequences

Positive:

- Later editor, viewer, and import work shares one explicit persistence model.
- Ordering is queryable and independent of SwiftData relationship-array order.
- Required creation-time ownership and cascade deletion prevent orphaned
  snippets in supported application flows.
- The existing clipboard store is preserved through an additive migration.

Negative:

- Reordering may update several sibling `sortOrder` values.
- SwiftData does not enforce dense, unique order values within a folder; later
  domain logic must maintain that invariant.
- The persisted `folder` relationship is technically optional to support
  SwiftData cascade processing; later mutation APIs must preserve the ownership
  invariant.

If the on-disk migration test fails on a supported toolchain, do not delete or
recreate the user's store. Stop the change and introduce an explicit migration
design instead.
