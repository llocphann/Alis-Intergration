# Optional Agenda task mutation — focused source evidence

AGENDA-F01 implementation belongs to Alis-Intergration main. The host task
board remains in Alis dev. Version 0.2.2 adds the bounded acknowledged worker
for existing daily heading / managed task sections; package absent or older
API leaves a visible pending link, with no fallback to another task source.

Task markers are versioned and validated. Native checkbox mutations retain
markers; event changes preserve completion and user suffix/child notes.
Deleting/unlinking Agenda preserves the task. Explicit task deletion removes
only the linked checkbox and is idempotent. Missing linked tasks never return.
Workers reread under a directory lock, retain core CAS/fsync protection, and
reject ambiguous identities, unwritable/missing sections and unsafe paths.

See receipt.json and source-hashes.json. Actual host-to-package QML-to-Python
bridge evidence for both sources is retained in Alis under
`docs/evidence/abyss-product/20261012-agenda-obsidian/final-source/`: 16 processes,
48 checks, repeated restart and independent note/disk readbacks. This tests
source in private fixture mounts, not an installed owner package.

Known diagnostic failures and the fix-forward remain in the host evidence:
unregistered local QML type, private package probe setup, and QVariant task
array transport that temporarily cleared the UI. JSON string transport now
retains the actual task model across every acknowledged mutation. No personal
vault, preferences, integration activation or hardware profiles were modified.
Host exact-SHA canonical, installed identity, owner and source-switch/midnight
acceptance remain separate open gates.
