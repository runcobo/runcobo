INSTALL_DIR ?= /usr/local/bin
LOCAL_DIR ?= $(CURDIR)/bin

.DEFAULT_GOAL := build
.PHONY: all help deps build runcobo test examples-check format format-check check install

all: build

help:
	@echo 'make build         Build bin/runcobo locally (default)'
	@echo 'make test          Install dependencies and run specs'
	@echo 'make examples-check Compile the example application without linking'
	@echo 'make format        Format src and spec'
	@echo 'make format-check  Check formatting without changing files'
	@echo 'make check         Run specs, formatting checks and build smoke checks'
	@echo 'make install       Build and install in INSTALL_DIR (default: /usr/local/bin)'

deps:
	shards install

build: deps
	mkdir -p "$(LOCAL_DIR)"
	crystal build src/cli.cr --no-debug -o "$(LOCAL_DIR)/runcobo"

runcobo: build

test: deps
	crystal spec

examples-check: deps
	cd spec/dummy && CRYSTAL_PATH="$(CURDIR)/lib:$(shell crystal env CRYSTAL_PATH)" crystal build --no-codegen src/dummy.cr

format:
	crystal tool format src spec

format-check:
	crystal tool format --check src spec

check: test examples-check format-check build
	"$(LOCAL_DIR)/runcobo" --version
	"$(LOCAL_DIR)/runcobo" --help

install: build
	install -d "$(INSTALL_DIR)"
	install -m 755 "$(LOCAL_DIR)/runcobo" "$(INSTALL_DIR)/runcobo"
