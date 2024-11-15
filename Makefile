# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

##########################################
### Libraries
##########################################
install:
	rm -rf lib
	forge install foundry-rs/forge-std@v1.9.4 --no-git
	forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git

##########################################
### Utils
##########################################
fmt:
	forge fmt
	
##########################################
### Build
##########################################
clean:
	forge fmt && forge clean

build: fmt
	forge build --evm-version paris

clean_build: clean build

docs: clean_build
	forge doc --build

##########################################
### Tests
##########################################
test: fmt
	forge test

test-gas: fmt
	forge test --gas-report

test-cov: fmt
	forge coverage

test-fuzz: fmt
	forge test --fuzz-runs 10000

##########################################
### Audit
##########################################
slither:
	poetry run slither .

##########################################
### Deploy HODLHelperV1.sol
##########################################

deploy_HODLHelperV1_sepolia: build
	forge script script/Deploy.s.sol:DeployHODLHelperV1 --evm-version paris --rpc-url sepolia --ledger --sender ${SENDER} --broadcast
	forge verify-contract $$(cat out.txt) src/HODLHelperV1.sol:HODLHelperV1 --chain sepolia --watch --constructor-args ${CONSTRUCTOR_ARGS}
	@bash print_and_clean.sh