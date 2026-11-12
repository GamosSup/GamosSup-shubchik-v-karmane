param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [Parameter(Mandatory)][string]$DriveFolder,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repo = 'GamosSup/GamosSup-shubchik-v-karmane'
$tag = "android-$Version"
$file = "shubchik-$Version.apk"
$gh = Get-Command gh -ErrorAction SilentlyContinue
$ghPath = if ($gh) { $gh.Source } else { Join-Path $env:ProgramFiles 'GitHub CLI/gh.exe' }

$json = & $ghPath release view $tag -R $repo --json isDraft,assets
if ($LASTEXITCODE -ne 0) { throw "Could not read release $tag" }
$release = $json | ConvertFrom-Json
if (!$release.isDraft) { throw "Release $tag is not a private draft" }
$assets = @($release.assets | Where-Object { $_.name -ceq $file })
if ($assets.Count -ne 1 -or $assets[0].digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
    throw "Could not find a verified APK digest for $file"
}
$expected = $assets[0].digest.Substring(7)
if (!(Test-Path -LiteralPath $DriveFolder -PathType Container)) {
    throw 'The approved Google Drive folder is unavailable'
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$local = Join-Path $OutputDirectory $file
if (!(Test-Path -LiteralPath $local -PathType Leaf)) {
    & $ghPath release download $tag -R $repo --pattern $file --dir $OutputDirectory
    if ($LASTEXITCODE -ne 0) { throw "Could not download $file" }
}
if ((Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash -ne $expected) {
    throw "The local APK digest differs from the draft asset"
}
$destination = Join-Path $DriveFolder $file
if (!(Test-Path -LiteralPath $destination -PathType Leaf)) {
    Copy-Item -LiteralPath $local -Destination $destination
}
if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
    throw "The Drive APK digest differs from the draft asset"
}
[pscustomobject]@{ Version = $Version; Local = $local; Drive = $destination; SHA256 = $expected }
