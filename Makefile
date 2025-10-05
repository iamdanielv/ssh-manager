# Makefile for the SSH Manager project.
# The help comments are based on https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html

.DEFAULT_GOAL := help
.PHONY: all build clean test ssh-manager advanced-ssh-manager playground dist-ssh-manager dist-advanced-ssh-manager help

# Color Definitions
C_BLUE := \033[34m
C_WHITE := \033[37m
T_RESET := \033[0m

# Define variables
SHELL := /bin/bash
SRC_DIR := src
DIST_DIR := dist
TEST_DIR := test

BUILD_SCRIPT := ./build.sh

SSH_MANAGER_SRC := $(SRC_DIR)/ssh-manager.sh
ADVANCED_SSH_MANAGER_SRC := $(SRC_DIR)/advanced-ssh-manager.sh
PLAYGROUND_SRC := $(SRC_DIR)/interactive-menu-playground.sh

SSH_MANAGER_DIST := $(DIST_DIR)/ssh-manager.sh
ADVANCED_SSH_MANAGER_DIST := $(DIST_DIR)/advanced-ssh-manager.sh
LIB_FILES := $(wildcard $(SRC_DIR)/lib/*.sh)
TEST_SCRIPTS := $(wildcard $(TEST_DIR)/test_*.sh)

##@ General

help: ##@ Show this help message
	@printf "$(C_BLUE)%-28s$(T_RESET) %s\n" "Target" "Description"
	@printf "%-28s %s\n" "------" "-----------"
	@grep -E '^[a-zA-Z_-]+:.*?##@ .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?##@ "}; {printf "\033[34m%-28s\033[0m %s\n", $$1, $$2}'

all: build ##@ Build all distributable scripts (default if no goal is specified after help)
	@echo "Build complete. Find artifacts in $(DIST_DIR)/"

build: $(SSH_MANAGER_DIST) $(ADVANCED_SSH_MANAGER_DIST) ##@ Build all distributable scripts

$(SSH_MANAGER_DIST): $(SSH_MANAGER_SRC) $(LIB_FILES) $(BUILD_SCRIPT)
	@$(BUILD_SCRIPT) $(SSH_MANAGER_SRC)

$(ADVANCED_SSH_MANAGER_DIST): $(ADVANCED_SSH_MANAGER_SRC) $(LIB_FILES) $(BUILD_SCRIPT)
	@$(BUILD_SCRIPT) $(ADVANCED_SSH_MANAGER_SRC)

clean: ##@ Remove the dist directory and other build artifacts
	@echo "Cleaning up..."
	@rm -rf $(DIST_DIR)

test: $(SSH_MANAGER_SRC) $(ADVANCED_SSH_MANAGER_SRC) $(LIB_FILES) ##@ Run all tests
	@echo "Running tests..."
	@for test_script in $(TEST_SCRIPTS); do \
		echo; \
		printf "$(C_WHITE)--- Running $$test_script ---$(T_RESET)\n"; \
		bash $$test_script; \
	done

##@ Development

ssh-manager: ##@ Run the development version of ssh-manager
	@$(SSH_MANAGER_SRC)

advanced-ssh-manager: ##@ Run the development version of advanced-ssh-manager
	@$(ADVANCED_SSH_MANAGER_SRC)

playground: ##@ Run the interactive menu playground script
	@$(PLAYGROUND_SRC)

##@ Distribution

dist-ssh-manager: $(SSH_MANAGER_DIST) ##@ Build and run the distributable version of ssh-manager
	@$(SSH_MANAGER_DIST)

dist-advanced-ssh-manager: $(ADVANCED_SSH_MANAGER_DIST) ##@ Build and run the distributable version of advanced-ssh-manager
	@$(ADVANCED_SSH_MANAGER_DIST)