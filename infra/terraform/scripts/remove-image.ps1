$ErrorActionPreference = 'Stop'

$imageId = & docker image ls --quiet $env:MURAL_IMAGE
if ($LASTEXITCODE -ne 0) { throw 'Consulta da tag gerenciada falhou' }
if ($imageId) {
  & docker image rm $env:MURAL_IMAGE
  if ($LASTEXITCODE -ne 0) { throw 'Remocao da tag gerenciada falhou' }
}
