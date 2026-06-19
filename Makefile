.PHONY: validate teardown port-forward-dev port-forward-prod port-forward port-forward-stop build-local run-local

PF_DIR := /tmp/pipeline-controls-pf

validate:
	./scripts/validate-setup.sh

teardown:
	./scripts/teardown.sh

port-forward-dev:
	kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev

port-forward-prod:
	kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod

# Background port-forward to both Dev (8080) and Prod (8081). Stop with
# `make port-forward-stop`. PIDs and logs live in $(PF_DIR).
port-forward:
	@mkdir -p $(PF_DIR)
	@$(MAKE) --no-print-directory port-forward-stop >/dev/null 2>&1 || true
	@nohup kubectl port-forward svc/pipeline-controls-demo 8080:80 -n web-dev  >$(PF_DIR)/dev.log  2>&1 & echo $$! > $(PF_DIR)/dev.pid
	@nohup kubectl port-forward svc/pipeline-controls-demo 8081:80 -n web-prod >$(PF_DIR)/prod.log 2>&1 & echo $$! > $(PF_DIR)/prod.pid
	@sleep 1
	@echo "Dev:  http://127.0.0.1:8080  (pid $$(cat $(PF_DIR)/dev.pid),  log $(PF_DIR)/dev.log)"
	@echo "Prod: http://127.0.0.1:8081  (pid $$(cat $(PF_DIR)/prod.pid), log $(PF_DIR)/prod.log)"
	@echo "Stop with: make port-forward-stop"

port-forward-stop:
	@for f in $(PF_DIR)/dev.pid $(PF_DIR)/prod.pid; do \
	  if [ -f $$f ]; then \
	    pid=$$(cat $$f); \
	    kill $$pid 2>/dev/null || true; \
	    echo "stopped pid $$pid"; \
	    rm -f $$f; \
	  fi; \
	done; true

build-local:
	docker build -t pipeline-controls-demo:local app/

run-local:
	docker run --rm -p 8080:8080 pipeline-controls-demo:local
