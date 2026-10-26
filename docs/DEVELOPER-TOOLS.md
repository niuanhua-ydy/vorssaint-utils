# Command bar developer tools

Search `json`, `base64`, `url`, `unicode`, or `sha256` in the command bar.
Each opens an independent editor; Return inserts a newline, Command-Return runs
the selected operation. Copy is explicit. “Use as input” enables chaining.

Settings → Command bar → Developer tool plugins enables/disables each module.
All five start enabled. Disabling removes the command entry (including its row
shortcut on preference sync); an already-open editor is left intact to preserve
its draft. Closing the editor discards its draft. Disabling the Actions source
also hides these entries, like other command actions.

- JSON: validate, format, minify. Preserves key order, numeric tokens and string
  escapes; does not sort keys or silently round long IDs.
- Base64: standard Base64 of UTF-8 text; ignores whitespace on decode, rejects
  other invalid characters and non-UTF-8 decoded bytes. Not a binary-file editor.
- URL: RFC 3986 component percent encoding, not whole-URL encoding or HTML form
  decoding; `+` stays `+`, spaces become `%20`.
- Unicode: produces a quoted JSON string with UTF-16 `\uXXXX` escapes (surrogate
  pairs for emoji). Decode expects a complete quoted JSON string.
- SHA-256: lowercase hex digest of the exact UTF-8 input, including whitespace.

All processing is local, with no automatic clipboard reads, networking, logging
or persistence of input/output. Input is limited to 256 KiB per operation.
Errors clear the previous output to prevent copying stale results.

## Adding an in-process plugin

Register a `CommandBarDeveloperTool` in `CommandBarDeveloperTools.all`, with a
unique stable ID, English/Chinese names, symbol, search keywords and operations.
Each operation supplies its stable ID, labels and throwing `(String) -> String`
transform. The command catalog, editor and settings switches use this registry;
no separate switch statements are required. IDs are persisted, so never rename
released IDs. Unknown disabled IDs survive preference edits.

This is an in-process built-in module interface, not a third-party executable
loader. New modules require a rebuild. No new package dependencies are needed.

Verification: `./build.sh --test-suite=developer-tools`,
`./build.sh --test-suite=command-bar`, `./build.sh --dev`.
