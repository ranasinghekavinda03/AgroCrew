# Phase 4, Step 26: CropCycle API

The authenticated API supports creating, listing, reading, replacing, and deleting CropCycles at `/api/v1/crops`. Each crop belongs to a Farm, and every operation resolves ownership through that Farm. A farmer cannot read or modify another farmer's crop. The list supports `limit` (1–100), zero-based `offset`, and an optional owned `farm_id` filter. Results use creation time and crop ID ordering.

Create accepts an owned `farm_id`; the server supplies ownership from the access token. PUT replaces the writable crop fields, clears omitted optional values, and cannot change the parent Farm or generated identity. Crop types are trimmed, optional blank varieties become null, dates must be ISO calendar dates, expected harvest cannot precede planting, plant count must be a positive integer, and notes are limited to 10,000 characters. Status accepts only `planned`, `active`, `harvested`, or `cancelled`; this is enum validation only, not a lifecycle policy.

Database writes commit on success and roll back on database errors. Crop creation locks the owned Farm row on PostgreSQL to serialize against a Farm deletion. Updates and deletes lock the selected owner-scoped crop row. The foreign key remains the final protection if concurrent activity defeats application level checks. Concurrent updates are last-writer-wins after row locks are acquired; there is no version field or optimistic conflict response.

Future lifecycle design remains open: transitions from planned to active and active to harvested; cancellation; editing or deleting harvested and cancelled history; linking crops to diagnosis history and AI recommendations; showing growing duration and estimated harvest dates; and filtering by status. This step adds none of those workflows or records.

Real database verification is opt-in with `RUN_POSTGRES_INTEGRATION=1` and uses the configured PostgreSQL instance. The ordinary API tests use isolated SQLite and do not substitute for that integration run.
