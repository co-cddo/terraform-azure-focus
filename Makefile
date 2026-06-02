#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
.PHONY: all security lint format documentation documentation-examples validate-all validate validate-examples init examples tests tests-python python-setup python-lint python-format python-lock

TERRAFORM_DOCS_DOCKER=docker run --rm --volume "$$(pwd):/workspace" --workdir /workspace -u $$(id -u) quay.io/terraform-docs/terraform-docs:0.20.0

default: all

all: 
	$(MAKE) init
	$(MAKE) validate
	$(MAKE) tests
	$(MAKE) tests-python
	$(MAKE) lint
	$(MAKE) security
	$(MAKE) format
	$(MAKE) documentation

examples:
	$(MAKE) validate-examples
	$(MAKE) tests
	$(MAKE) lint-examples
	$(MAKE) lint
	$(MAKE) security
	$(MAKE) format
	$(MAKE) documentation

documentation: 
	@echo "--> Generating documentation"
	@$(TERRAFORM_DOCS_DOCKER) markdown .
	$(MAKE) documentation-modules
	$(MAKE) documentation-examples

documentation-modules:
	@echo "--> Generating documentation for modules"
	@find . -type d -regex '.*/modules/[a-za-z\-_$$]*' -not -path '*.terraform*' 2>/dev/null | while read -r dir; do \
		echo "--> Generating documentation for module: $$dir"; \
		$(TERRAFORM_DOCS_DOCKER) markdown $$dir; \
	done;

documentation-examples:
	@echo "--> Generating documentation for examples"
	@find . -type d -path '*/examples/*' -not -path '*.terraform*' 2>/dev/null| while read -r dir; do \
		echo "--> Generating documentation for example: $$dir"; \
		$(TERRAFORM_DOCS_DOCKER) markdown $$dir; \
	done;

upgrade-terraform-providers:
	@printf "%s Upgrading Terraform providers for %-24s" "-->" "."
	@terraform init -upgrade >/dev/null && echo "[OK]" || echo "[FAILED]"
	@$(MAKE) upgrade-terraform-example-providers

upgrade-terraform-example-providers:
	@if [ -d examples ]; then \
		find examples -type d -mindepth 1 -maxdepth 1 2>/dev/null | while read -r dir; do \
			printf "%s Upgrading Terraform providers for %-24s" "-->" "$$dir"; \
			terraform -chdir=$$dir init -upgrade >/dev/null && echo "[OK]" || echo "[FAILED]"; \
		done; \
	fi

init: 
	@echo "--> Running terraform init"
	@terraform init -backend=false
	@find . -type f -name "*.tf" -not -path '*.terraform*' -exec dirname {} \; | sort -u | while read -r dir; do \
		echo "--> Running terraform init in $$dir"; \
		terraform -chdir=$$dir init -backend=false; \
	done;

security: init
	@echo "--> Running Security checks"
	@trivy config .
	$(MAKE) security-modules
	$(MAKE) security-examples

security-modules:
	@echo "--> Running Security checks on modules"
	@find . -type d -regex '.*/modules/[a-zA-Z\-_$$]*' -not -path '*.terraform*' 2>/dev/null | while read -r dir; do \
		echo "--> Validating $$dir"; \
	  terraform init -backend=false; \
		trivy config  --format table --exit-code  1 --severity  CRITICAL,HIGH --ignorefile .trivyignore $$dir; \
	done; 

security-examples:
	@echo "--> Running Security checks on examples"
	@find . -type d -path '*/examples/*' -not -path '*.terraform*' 2>/dev/null | while read -r dir; do \
		echo "--> Validating $$dir"; \
	  terraform init -backend=false; \
		trivy config  --format table --exit-code  1 --severity  CRITICAL,HIGH --ignorefile .trivyignore $$dir; \
	done;

tests: 
	@echo "--> Running Terraform Tests" 
	@terraform test

validate:
	@echo "--> Running terraform validate"
	@terraform init -backend=false
	@terraform validate
	$(MAKE) validate-modules
	$(MAKE) validate-examples
	$(MAKE) validate-commits

validate-modules:
	@echo "--> Running terraform validate on modules"
	@find . -type d -regex '.*/modules/[a-zA-Z\-_$$]*' -not -path '*.terraform*' 2>/dev/null | while read -r dir; do \
		echo "--> Validating Module $$dir"; \
		terraform -chdir=$$dir init -backend=false; \
		terraform -chdir=$$dir validate; \
	done;

validate-examples:
	@echo "--> Running terraform validate on examples"
	@find . -type d -path '*/examples/*' -not -path '*.terraform*' 2>/dev/null | while read -r dir; do \
		echo "--> Validating $$dir"; \
		terraform -chdir=$$dir init -backend=false; \
		terraform -chdir=$$dir validate; \
	done; 

validate-commits:
	@echo "--> Running commitlint against the main branch"
	@command -v commitlint >/dev/null 2>&1 || { echo "commitlint is not installed. Please install it by running 'npm install -g commitlint'"; exit 1; }
	@git log --pretty=format:"%s" origin/main..HEAD | commitlint --from=origin/main

lint:
	@echo "--> Running tflint"
	@tflint --init 
	@tflint -f compact
	$(MAKE) lint-modules
	$(MAKE) lint-examples

lint-modules:
	@echo "--> Running tflint on modules"
	@find . -type d -regex '.*/modules/[a-zA-Z\-_$$]*' -not -path '*.terraform*' 2>/dev/null | while read -r dir; do \
		echo "--> Linting $$dir"; \
		tflint --chdir=$$dir --init; \
		tflint --chdir=$$dir -f compact; \
	done;

lint-examples:
	@echo "--> Running tflint on examples"
	@find . -type d -path '*/examples/*' -not -path '*.terraform*' 2>/dev/null | while read -r dir; do \
		echo "--> Linting $$dir"; \
		tflint --chdir=$$dir --init; \
		tflint --chdir=$$dir -f compact; \
	done; 

format: 
	@echo "--> Running terraform fmt"
	@terraform fmt -recursive -write=true

clean:
	@echo "--> Cleaning up"
	@find . -type d -name ".terraform" 2>/dev/null | while read -r dir; do \
		echo "--> Removing $$dir"; \
		rm -rf $$dir; \
	done

# Python dependency locking for the cost_export function app.
# Regenerates requirements.txt (fully pinned + hashed, incl. transitive deps) from
# requirements.in. Resolves for Linux / Python 3.13 so the tree and wheel hashes match
# Azure's Oryx remote build (--platform-version 3.13), which installs with
# --require-hashes. Requires uv (https://docs.astral.sh/uv/); it fetches a 3.12
# interpreter automatically, so no local Python 3.12 or Docker is needed.
python-lock:
	@echo "--> Locking Python requirements with full transitive hashes (linux/py3.13)"
	@command -v uv >/dev/null 2>&1 || { echo "uv is not installed. Install it: https://docs.astral.sh/uv/getting-started/installation/"; exit 1; }
	@cd src/cost_export && uv pip compile --generate-hashes \
	  --python-version 3.13 --python-platform linux \
	  --output-file requirements.txt requirements.in

# Python testing targets for carbon export functions
python-setup:
	@echo "--> Setting up Python test environment"
	@cd src/cost_export && python3 -m pip install --upgrade pip
	@cd src/cost_export && python3 -m pip install -r requirements.txt
	@cd src/cost_export && python3 -m pip install -r requirements-test.txt

tests-python: python-setup
	@echo "--> Running Python tests for carbon export functions"
	@cd src/cost_export && echo "Running Carbon API Date Range Tests..." && python3 test_carbon_date_range.py
	@cd src/cost_export && echo "Running Carbon API Idempotency Tests..." && python3 test_carbon_idempotency.py
	@cd src/cost_export && echo "Running Carbon API Batching Integration Tests..." && python3 test_carbon_batching.py
	@cd src/cost_export && echo "Running Carbon API Batching Unit Tests..." && python3 test_carbon_batching_unit.py
	@cd src/cost_export && echo "Validating Python syntax..." && python3 -m py_compile function_app.py common.py
	@echo "✅ All Python tests completed successfully"

python-lint:
	@echo "--> Running Python linting checks"
	@cd src/cost_export && flake8 --max-line-length=120 --ignore=E203,W503 *.py || echo "⚠️  Linting issues found"
	@cd src/cost_export && bandit -r . -f txt || echo "⚠️  Security issues found"

python-format:
	@echo "--> Formatting Python code"
	@cd src/cost_export && black --line-length=120 *.py
	@cd src/cost_export && isort --profile black *.py
	@echo "✅ Python code formatted successfully"

python-test-quick:
	@echo "--> Running quick Python syntax validation"
	@cd src/cost_export && python3 -m py_compile function_app.py common.py
	@cd src/cost_export && python3 test_carbon_batching_unit.py
	@echo "✅ Quick Python validation completed"