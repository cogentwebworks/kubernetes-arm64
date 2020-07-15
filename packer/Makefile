default: help

.PHONY: centos
centos: ## Build AMI for centos 8 ARM64
	@cd centos && packer build template.pkr.hcl

.PHONY: help
help: ## Display this information. Default target.
	@echo "Valid targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
