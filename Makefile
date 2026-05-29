.PHONY: validate teardown port-forward-dev port-forward-prod build-local run-local

validate:
	./scripts/validate-setup.sh

teardown:
	./scripts/teardown.sh

port-forward-dev:
	kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev

port-forward-prod:
	kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod

build-local:
	docker build -t pipeline-controls-demo:local app/

run-local:
	docker run --rm -p 8080:8080 pipeline-controls-demo:local
