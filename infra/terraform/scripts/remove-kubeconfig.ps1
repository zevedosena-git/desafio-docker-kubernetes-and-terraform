$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $env:MURAL_KUBECONFIG) {
  Remove-Item -LiteralPath $env:MURAL_KUBECONFIG
}
