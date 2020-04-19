INSTALL_DIR=/usr/local/bin
LOCAL_DIR=$(CURDIR)/bin

all: install

help:
	@echo 'Install on /usr/local/bin  "sudo make install"'
	@echo 'Install on /usr/bin        "sudo make install INSTALL_DIR=/usr/bin"'

runcobo:
	@shards install --production
	@mkdir -p $(LOCAL_DIR)
	@rm -f $(LOCAL_DIR)/runcobo

	@echo "Building runcobo on $(LOCAL_DIR)"
	@crystal build -o $(LOCAL_DIR)/runcobo src/cli.cr -p --no-debug
	@rm -f $(INSTALL_DIR)/runcobo
	@cp $(LOCAL_DIR)/runcobo $(INSTALL_DIR)/runcobo
	@echo "Install runcobo on $(INSTALL_DIR)"

install: runcobo | $(INSTALL_DIR)
