# Obfuscations

This directory contains distributable, generated copies of the stable V128
scripts. The working files in the project root are not modified.

Run this command from the repository root after a source change:

```powershell
powershell -ExecutionPolicy Bypass -File .\Obfuscations\Build-Obfuscations.ps1
```

The build script encodes each source byte with a per-position mask, generates
a small Luau decoder/loader, and verifies that decoding returns every original
byte before it writes the output. `Glitch_Panel.obfuscated.lua` is configured
to download `Glitch_Core.obfuscated.lua`.

The generated files start with the requested project marker. They are not
produced by, or represented as, Luraph output; Luraph is a separate service.
An in-game executor test is still required after any gameplay change because
the Roblox runtime is not available in this workspace.
