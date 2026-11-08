$ErrorActionPreference = 'Stop'

& docker build -f $env:MURAL_DOCKERFILE -t $env:MURAL_IMAGE $env:MURAL_REPO_ROOT
if ($LASTEXITCODE -ne 0) { throw 'Build da imagem falhou' }

& kind load docker-image $env:MURAL_IMAGE --name $env:MURAL_CLUSTER
if ($LASTEXITCODE -ne 0) { throw 'Carregamento da imagem no kind falhou' }
