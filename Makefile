SHELL := /bin/bash
.DELETE_ON_ERROR:

.PHONY: all
all: help

.PHONY: help
help: ## Show available targets
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: lint
lint: ## buf lint
	buf lint

.PHONY: breaking
breaking: ## buf breaking against origin/main
	buf breaking --against '.git#branch=main'

.PHONY: proto proto-go proto-java proto-swift proto-typescript proto-php proto-php-rr
proto: proto-go proto-java proto-swift proto-typescript proto-php proto-php-rr  ## Generate all language bindings locally (ephemeral)

proto-go:  ## Generate Go bindings into gen/go/ (published to proto-gen-go)
	buf generate --template buf.gen.go.yaml

proto-java:  ## Generate Java bindings into gen/java/ (published to proto-gen-java)
	buf generate --template buf.gen.java.yaml

proto-swift:  ## Generate Swift bindings into gen/swift/ (published to proto-gen-swift)
	buf generate --template buf.gen.swift.yaml

proto-typescript:  ## Generate TypeScript bindings into gen/typescript/ (published to proto-gen-typescript)
	buf generate --template buf.gen.typescript.yaml

proto-php:  ## Generate PHP (classic gRPC) bindings into gen/php/ (published to proto-gen-php)
	buf generate --template buf.gen.php.yaml

proto-php-rr:  ## Generate PHP (RoadRunner gRPC) bindings into gen/php-rr/ (published to proto-gen-php-rr)
	buf generate --template buf.gen.php-rr.yaml

.PHONY: clean
clean:  ## Remove all generated output
	rm -rf gen/
