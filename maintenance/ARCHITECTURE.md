# DataRaft package boundaries

The repository contains the umbrella package at its root and six independent
source packages under `packages/`. Building the umbrella excludes that folder;
it imports and re-exports the component APIs, without copying their engines.

The intended GitHub organization is `dataraft-r`, with a repository per package.
Organization creation and repository placement are separate from the source
split. Until those repositories exist, the shared checkout and CI install the
component packages in dependency order.

The core owns definitions, recipes, execution protocols, in-memory execution and
quality gates. Lake, adapter, dbt, catalog and metrics packages own their respective
implementations. Their Imports graph is acyclic. Optional core methods can call
an installed extension, but an in-memory workflow does not load one.

Shared implementation helpers are currently exported with internal documentation
so cross-package calls use declared interfaces rather than `:::`. They are not
re-exported by the umbrella. Further reducing that helper surface is separate
from the user-facing API and requires replacing remaining concrete integration
branches with narrower protocols.

The shared integration suite lives in the umbrella; its test-only helper binds
implementation functions from their owning namespace. That fixture is never
installed as production code. The core additionally has standalone tests and a
CI job with no extension or optional engine installed.
