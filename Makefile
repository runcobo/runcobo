INSTALL_DIR ?= /usr/local/bin
LOCAL_DIR ?= $(CURDIR)/bin

.DEFAULT_GOAL := build
.PHONY: all help deps build build-crsql runcobo test examples-check generate generate-check integration format format-check check install install-dbmate

all: build

help:
	@echo 'make build         Build bin/cobo locally (default)'
	@echo 'make test          Install dependencies and run specs'
	@echo 'make examples-check Compile the example applications without linking'
	@echo 'make generate      Generate the crsql example queries (requires sqlc)'
	@echo 'make generate-check Check generated queries match the committed file'
	@echo 'make integration   Test against a dedicated runcobo_crsql_test database'
	@echo 'make format        Format src and spec'
	@echo 'make format-check  Check formatting without changing files'
	@echo 'make check         Run specs, formatting checks and build smoke checks'
	@echo 'make install       Install cobo and dbmate in INSTALL_DIR (default: /usr/local/bin)'

deps:
	shards install

build: deps
	mkdir -p "$(LOCAL_DIR)"
	crystal build src/cli.cr --no-debug -o "$(LOCAL_DIR)/cobo"

build-crsql: deps
	mkdir -p "$(LOCAL_DIR)"
	crystal build lib/crsql/src/cli.cr -o "$(LOCAL_DIR)/crsql"

generate: build-crsql
	"$(LOCAL_DIR)/crsql" generate -f examples/crsql/sqlc.yaml

generate-check: generate
	git diff --exit-code -- examples/crsql/src/db/queries.cr

integration: generate
	CRYSTAL_PATH="$(CURDIR)/src:$(shell crystal env CRYSTAL_PATH)" crystal spec examples/crsql/spec

runcobo: build

test: deps build build-crsql
	crystal spec

examples-check: deps
	cd spec/dummy && CRYSTAL_PATH="$(CURDIR)/lib:$(shell crystal env CRYSTAL_PATH)" crystal build --no-codegen src/dummy.cr
	CRYSTAL_PATH="$(CURDIR)/src:$(shell crystal env CRYSTAL_PATH)" crystal build --no-codegen examples/crsql/src/main.cr

format:
	crystal tool format src spec examples/crsql/src examples/crsql/spec

format-check:
	crystal tool format --check src spec examples/crsql/src examples/crsql/spec

check: test examples-check format-check build
	"$(LOCAL_DIR)/cobo" --version
	"$(LOCAL_DIR)/cobo" --help

install-dbmate:
	sh scripts/install-dbmate.sh "$(LOCAL_DIR)/runcobo-dbmate"

install: build install-dbmate
	install -d "$(INSTALL_DIR)"
	install -m 755 "$(LOCAL_DIR)/cobo" "$(INSTALL_DIR)/cobo"
	install -m 755 "$(LOCAL_DIR)/runcobo-dbmate" "$(INSTALL_DIR)/runcobo-dbmate"
