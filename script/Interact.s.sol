// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CreditScoring.sol";

contract InteractScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Your deployed CreditScoring address
        address creditScoringAddr = vm.envAddress("CREDIT_SCORING_ADDR");

        vm.startBroadcast(deployerPrivateKey);

        CreditScoring creditScoring = CreditScoring(creditScoringAddr);

        // Test interaction
        creditScoring.createDebt(msg.sender, 1000 * 10 ** 18, 150 * 10 ** 18);

        console.log(" Successfully created debt!");

        vm.stopBroadcast();
    }
}
