.PHONY: build test exploit fixed anvil deploy slither coverage

build:    ; forge build
test:     ; forge test -vv
exploit:  ; forge test --match-path "test/exploits/*" -vvv
fixed:    ; forge test --match-path "test/fixed/*" -vv
anvil:    ; anvil
deploy:   ; forge script script/DeployReentrancy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
deploy2:  ; forge script script/DeployAccessControl.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
slither:  ; slither . --filter-paths "lib|test|script" --checklist > docs/slither-report.md || true
coverage: ; forge coverage --no-match-coverage "test|script"
