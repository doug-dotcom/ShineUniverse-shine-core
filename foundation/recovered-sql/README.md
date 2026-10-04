# Deployed Foundation SQL recovery archive

Recovered on 4 October 2026 from the dedicated Foundation project's migration history (`sjpxqeyewahraxvidvcc`). These 125 existing migration records cover numbered Foundation Layers 110–198 and fixes within those layers. They are preserved as historical source, not new migrations, and are not automatically executed by CI.

`manifest.json` records each migration's original version, name and database-computed MD5 of its stored SQL. All 125 archived files were verified byte-for-byte against those checksums. Preserve whitespace when checking the archive.

The existing Foundation JavaScript acceptance suites passed: 208 tests, zero failures. This checks existing checked-in code; it does not establish a clean database replay of the recovered SQL, current runtime certification, or historical layer-completion evidence.

The source and completion ledger previously stopped at 109 although the live database contains Layer 198. No historical ledger entries were manufactured during recovery. Layer 199 remains in progress pending reconciliation of live definitions, release evidence and ledger omissions. No production migration was rerun.
