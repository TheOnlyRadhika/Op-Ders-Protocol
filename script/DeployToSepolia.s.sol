// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CreditScoring.sol";
import "../src/LendingPool.sol";
import "../src/Options.sol";

contract DeployToSepoliaScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // USDC on Sepolia
        address usdcSepolia = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;

        // Deploy CreditScoring
        CreditScoring creditScoring = new CreditScoring();
        console.log(" CreditScoring deployed at:", address(creditScoring));

        // Deploy LendingPool
        LendingPool lendingPool = new LendingPool(
            usdcSepolia,
            address(creditScoring)
        );
        console.log("LendingPool deployed at:", address(lendingPool));

        // Deploy Options
        address feeRecipient = msg.sender;
        Options optionsContract = new Options(
            usdcSepolia,
            address(creditScoring),
            address(lendingPool),
            feeRecipient
        );
        console.log("Options deployed at:", address(optionsContract));

        console.log(" \n All contracts deployed successfully!");
        console.log(" Save these addresses:");
        console.log("CreditScoring:", address(creditScoring));
        console.log("LendingPool:", address(lendingPool));
        console.log("Options:", address(optionsContract));

        vm.stopBroadcast();
    }
}
