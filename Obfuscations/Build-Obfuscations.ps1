[CmdletBinding()]
param()

# Generates the distributable wrappers without changing the working sources.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = $PSScriptRoot
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-EncodedBytes {
	param([byte[]] $Bytes)
	$hex = [System.Text.StringBuilder]::new($Bytes.Length * 2)
	for ($index = 0; $index -lt $Bytes.Length; $index++) {
		$mask = ((($index + 1) * 29) + 73) % 256
		$encoded = ($Bytes[$index] + $mask) % 256
		[void] $hex.Append($encoded.ToString('X2'))
	}
	return $hex.ToString()
}

function Assert-RoundTrip {
	param([byte[]] $Original, [string] $Hex)
	if ($Hex.Length -ne ($Original.Length * 2)) {
		throw 'Encoded payload length does not match the source length.'
	}
	for ($index = 0; $index -lt $Original.Length; $index++) {
		$value = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
		$mask = ((($index + 1) * 29) + 73) % 256
		$decoded = ($value - $mask + 256) % 256
		if ($decoded -ne $Original[$index]) {
			throw "Round-trip verification failed at byte $index."
		}
	}
}

function Write-ObfuscatedLua {
	param(
		[string] $OutputName,
		[byte[]] $SourceBytes
	)

	$payload = Get-EncodedBytes -Bytes $SourceBytes
	Assert-RoundTrip -Original $SourceBytes -Hex $payload

	# The wrapper decodes the bytes in memory and executes the original chunk.
	# It uses only loadstring, which the existing panel already requires.
	$wrapper = @"
-- This is file project using LoRa up obfuscation.
-- Generated locally by Obfuscations/Build-Obfuscations.ps1; not produced by Luraph.
local _p = "$payload"
local _o = {}
for _i = 1, #_p, 2 do
	local _v = tonumber(_p:sub(_i, _i + 1), 16)
	local _j = (_i + 1) / 2
	_o[#_o + 1] = string.char((_v - ((_j * 29 + 73) % 256)) % 256)
end
local _f, _e = loadstring(table.concat(_o))
if not _f then error(_e, 0) end
return _f()
"@

	$outputPath = Join-Path $outputRoot $OutputName
	[System.IO.File]::WriteAllText($outputPath, $wrapper, $utf8NoBom)
	return [pscustomobject]@{
		File = $outputPath
		SourceBytes = $SourceBytes.Length
		OutputBytes = (Get-Item -LiteralPath $outputPath).Length
	}
}

$coreBytes = [System.IO.File]::ReadAllBytes((Join-Path $projectRoot 'Glitch_Core.lua'))
$panelPath = Join-Path $projectRoot 'Glitch_Panel.lua'
$panelSource = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($panelPath))
$oldCoreUrl = 'local CORE_URL = "https://raw.githubusercontent.com/kimpler1/scim/main/Glitch_Core.lua?cb=v128"'
$newCoreUrl = 'local CORE_URL = "https://raw.githubusercontent.com/kimpler1/scim/main/Obfuscations/Glitch_Core.obfuscated.lua?cb=v128-obfuscated"'
if (-not $panelSource.Contains($oldCoreUrl)) {
	throw 'The expected V128 core URL was not found in Glitch_Panel.lua.'
}
$panelSource = $panelSource.Replace($oldCoreUrl, $newCoreUrl)
$panelBytes = [System.Text.Encoding]::UTF8.GetBytes($panelSource)

$results = @(
	Write-ObfuscatedLua -OutputName 'Glitch_Core.obfuscated.lua' -SourceBytes $coreBytes
	Write-ObfuscatedLua -OutputName 'Glitch_Panel.obfuscated.lua' -SourceBytes $panelBytes
)
$results | Format-Table -AutoSize
Write-Host 'Round-trip verification passed for both generated files.'
