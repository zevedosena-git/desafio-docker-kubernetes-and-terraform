TF := terraform -chdir=infra/terraform

-include .env
export TF_VAR_postgres_password

.PHONY: init check up down status test-linux

init:
	$(TF) init -input=false

check: init
	$(TF) fmt -check
	$(TF) validate
	helm lint infra/helm/mural --set postgres.password=lint-only

up: init
	$(TF) apply -auto-approve

down:
	$(TF) destroy -auto-approve

test-linux:
	docker build -q -f infra/test/toolbox.Dockerfile -t mural-toolbox:local infra/test
	docker run --rm --network host -v /var/run/docker.sock:/var/run/docker.sock -v "$(CURDIR):/src:ro" --env-file .env mural-toolbox:local sh /src/infra/test/linux-cycle.sh

status:
	kubectl --kubeconfig "$$($(TF) output -raw kubeconfig_path)" -n mural get pods,jobs,pvc,ingress
