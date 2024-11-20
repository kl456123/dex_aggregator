#!/bin/bash

NETWORK=hardhat
DEPLOYMENT_ID=${NETWORK}
yarn hardhat ignition deploy ignition/modules/DexAggregator.ts \
    --parameters ./ignition/parameters.json \
    --network ${NETWORK} \
    --deployment-id ${DEPLOYMENT_ID}



# forge script scripts/DeployDexAggregator.s.sol --rpc-url ${NETWORK}
