#!/usr/bin/env bash
# Driver: run the full test suite, deploy all ten solutions to a local anvil
# on port 9545 (starting one if none is running), then walk the UUPS counter
# through a live V2 upgrade — slot flip, new function, state preserved.
set -euo pipefail
cd "$(dirname "$0")"

PORT=9545
KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80  # anvil account 0
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc  # keccak256("eip1967.proxy.implementation")-1

echo "════ 1/3: forge test ════"
forge test

echo
echo "════ 2/3: deploy all solutions to anvil :$PORT ════"
if lsof -ti tcp:$PORT > /dev/null 2>&1; then
    echo "anvil already listening on $PORT — reusing it"
else
    anvil --port $PORT > anvil.log 2>&1 &
    echo "started anvil (pid $!, log: anvil.log)"
    sleep 1
fi

forge script script/DeployAll.s.sol --tc DeployAll --rpc-url local --broadcast

echo
echo "════ 3/3: UUPS upgrade drill — counter V1 -> V2 ════"
# proxy address from the broadcast record (robust against nonce drift on a reused anvil)
PROXY=$(python3 -c "
import json
txs = json.load(open('broadcast/DeployAll.s.sol/31337/run-latest.json'))['transactions']
print(next(t['contractAddress'] for t in txs if t.get('contractName') == 'ERC1967Proxy'))")

cast send "$PROXY" "increment()" --rpc-url local --private-key $KEY > /dev/null
cast send "$PROXY" "increment()" --rpc-url local --private-key $KEY > /dev/null
echo "value before upgrade:  $(cast call "$PROXY" 'value()(uint256)' --rpc-url local)"
echo "impl slot before:      $(cast storage "$PROXY" $IMPL_SLOT --rpc-url local)"

# V2 must exist on-chain first (cast can't deploy; lift CounterV2 from the test file)
V2=$(forge create test/08_UpgradeableCounter.t.sol:CounterV2 \
        --rpc-url local --broadcast --private-key $KEY 2>/dev/null \
     | awk '/Deployed to/ {print $3}')
echo "CounterV2 deployed:    $V2"

# the upgrade tx goes to the PROXY: V1 code runs via delegatecall and writes
# the new implementation into the proxy's EIP-1967 slot. 0x = no migration call.
cast send "$PROXY" "upgradeToAndCall(address,bytes)" "$V2" 0x \
    --rpc-url local --private-key $KEY > /dev/null

echo "impl slot after:       $(cast storage "$PROXY" $IMPL_SLOT --rpc-url local)"
echo "version() [new in V2]: $(cast call "$PROXY" 'version()(uint256)' --rpc-url local)"
echo "value preserved:       $(cast call "$PROXY" 'value()(uint256)' --rpc-url local)"
cast send "$PROXY" "decrement()" --rpc-url local --private-key $KEY > /dev/null
echo "after decrement():     $(cast call "$PROXY" 'value()(uint256)' --rpc-url local)"

echo
echo "anvil is live on http://127.0.0.1:$PORT — addresses above."
echo "example:  cast call <ORACLE_ADDR> 'latestPrice18()(uint256)' --rpc-url local"
echo "stop it:  lsof -ti tcp:$PORT | xargs kill"
