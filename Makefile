-include .env.local
.EXPORT_ALL_VARIABLES:
MAKEFLAGS += --no-print-directory

PROTOCOL ?= compound
NETWORK ?= eth-mainnet

FOUNDRY_SRC ?= src/${PROTOCOL}/

FOUNDRY_PROFILE ?= ${PROTOCOL}
FOUNDRY_PRIVATE_KEY ?= ${DEPLOYER_PRIVATE_KEY}
FOUNDRY_ETH_RPC_URL ?= https://${NETWORK}.g.alchemy.com/v2/${ALCHEMY_KEY}

ifeq (${FOUNDRY_PROFILE}, production)
  FOUNDRY_TEST = test/prod/${PROTOCOL}/
else
  FOUNDRY_TEST ?= test/${PROTOCOL}/
endif

install:
	yarn
	foundryup
	git submodule update --init --recursive

	chmod +x ./scripts/**/*.sh
	chmod +x ./export_env.sh

deploy:
	@echo Deploying Morpho-${PROTOCOL}-${NETWORK}
	./scripts/${PROTOCOL}/deploy.sh

initialize:
	@echo Initializing Morpho-${PROTOCOL}-${NETWORK}
	./scripts/${PROTOCOL}/initialize.sh

create-market:
	@echo Creating market on Morpho-${PROTOCOL}-${NETWORK}
	./scripts/${PROTOCOL}/create-market.sh

anvil:
	@echo Starting fork of ${NETWORK}
	@anvil --fork-url ${FOUNDRY_ETH_RPC_URL} --fork-block-number "${FOUNDRY_FORK_BLOCK_NUMBER}"

script-%:
	@echo Running script $* of Morpho-${PROTOCOL} on ${NETWORK} with script mode: ${SMODE}
	@forge script scripts/${PROTOCOL}/$*.s.sol:$* --broadcast -vvvv

contracts:
	FOUNDRY_TEST=/dev/null forge build --sizes --force

ci:
	forge test -vvv

ci-upgrade:
	@FOUNDRY_MATCH_CONTRACT=TestUpgrade FOUNDRY_FUZZ_RUNS=64 FOUNDRY_PROFILE=production make ci

test:
	@echo Running Morpho-${PROTOCOL}-${NETWORK} tests under \"${FOUNDRY_TEST}\"\
		with profile \"${FOUNDRY_PROFILE}\", seed \"${FOUNDRY_FUZZ_SEED}\",\
		match contract patterns \"\(${FOUNDRY_MATCH_CONTRACT}\)!${FOUNDRY_NO_MATCH_CONTRACT}\",\
		match test patterns \"\(${FOUNDRY_MATCH_TEST}\)!${FOUNDRY_NO_MATCH_TEST}\"

	forge test -vvv | tee trace.ansi

test-prod:
	@FOUNDRY_NO_MATCH_CONTRACT=TestUpgrade FOUNDRY_PROFILE=production make test

test-upgrade:
	@FOUNDRY_MATCH_CONTRACT=TestUpgrade FOUNDRY_PROFILE=production make test

test-common:
	@FOUNDRY_TEST=test/common/ make test

test-upgrade-%:
	@FOUNDRY_MATCH_TEST=$* make test-upgrade

test-prod-%:
	@FOUNDRY_MATCH_TEST=$* make test-prod

test-%:
	@FOUNDRY_MATCH_TEST=$* make test

contract-% c-%:
	@FOUNDRY_MATCH_CONTRACT=$* make test

gas-report:
	@echo Create gas report from Morpho-${PROTOCOL}-${NETWORK} tests under \"${FOUNDRY_TEST}\"\
		with profile \"${FOUNDRY_PROFILE}\", seed \"${FOUNDRY_FUZZ_SEED}\",

	forge test --gas-report | tee trace.ansi

config:
	@forge config


.PHONY: test config test-common foundry contracts
