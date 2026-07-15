<#
Builds the shared Lambda layer directory that terraform/modules/lambda zips via
archive_file. Installs third-party deps (google-auth, PyJWT) plus the local
`common` module into terraform/build/layer/python.

Run this once before `terraform apply`, and again whenever
lambdas/layer_requirements.txt or lambdas/common/common.py changes.
#>

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$layerPythonDir = Join-Path $root "terraform\build\layer\python"

if (Test-Path $layerPythonDir) {
    Remove-Item -Recurse -Force $layerPythonDir
}
New-Item -ItemType Directory -Force -Path $layerPythonDir | Out-Null

# Force manylinux/cp312 wheels regardless of the local interpreter/OS, since
# this layer runs on Lambda's Linux python3.12 runtime, not on Windows.
pip install -r (Join-Path $root "lambdas\layer_requirements.txt") -t $layerPythonDir `
    --platform manylinux2014_x86_64 `
    --implementation cp `
    --python-version 3.12 `
    --only-binary=:all:
Copy-Item (Join-Path $root "lambdas\common\common.py") $layerPythonDir

Write-Host "Layer contents ready at $layerPythonDir"
