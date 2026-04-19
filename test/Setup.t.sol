// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "lib/forge-std/src/Test.sol";
import "../src/CreditScoring.sol";
import "../src/LendingPool.sol";
import "../src/Options.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 100000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BaseTest is Test {
    CreditScoring public creditscoring;
    LendingPool public lendingpool;
    Options public options;

    MockToken public underlying;
    MockToken public stablecoin;

    address public alice = address(0x111);
    address public bob = address(0x222);
    address public charlie = address(0x333);
    address public owner = address(this);

    uint256 constant INITIAL_BALANCE = 100000 * 10 ** 18;

    //DEPLOYING CONTRACTS
    function setUp() public {
        stablecoin = new MockToken("USDC", "USDC");
        underlying = new MockToken("WETH", "WETH");
        // Give the options contract some liquidity to pay premiums!

        //other contracts
        creditscoring = new CreditScoring();
        lendingpool = new LendingPool(
            address(stablecoin),
            address(creditscoring)
        );
        options = new Options(
            address(creditscoring),
            address(lendingpool),
            address(underlying),
            address(stablecoin)
        );
        stablecoin.mint(address(options), 1000000 * 10 ** 18);
        underlying.mint(address(options), 1000000 * 10 ** 18);

        // --- ALLOWANCE WALI CODE LINES ---

        // Prank Alice and approve the Options contract to spend her tokens
        vm.startPrank(alice);
        stablecoin.approve(address(options), type(uint256).max);
        underlying.approve(address(options), type(uint256).max);
        vm.stopPrank();

        // Prank Bob and approve the Options contract to spend his tokens
        vm.startPrank(bob);
        stablecoin.approve(address(options), type(uint256).max);
        underlying.approve(address(options), type(uint256).max);
        vm.stopPrank();

        // SET VARIOUS ADDRESSES
        creditscoring.setLendingPool(address(lendingpool));
        creditscoring.setOptionsContract(address(options));

        // GIVE TEST USER TOKENS
        stablecoin.mint(alice, INITIAL_BALANCE);
        stablecoin.mint(bob, INITIAL_BALANCE);
        stablecoin.mint(charlie, INITIAL_BALANCE);

        underlying.mint(alice, INITIAL_BALANCE);
        underlying.mint(bob, INITIAL_BALANCE);
        underlying.mint(charlie, INITIAL_BALANCE);

        vm.prank(alice);
        stablecoin.approve(address(lendingpool), type(uint256).max);
        vm.prank(alice);
        stablecoin.approve(address(options), type(uint256).max);
        vm.prank(alice);
        stablecoin.approve(address(underlying), type(uint256).max);

        vm.prank(bob);
        stablecoin.approve(address(lendingpool), type(uint256).max);
        vm.prank(bob);
        stablecoin.approve(address(options), type(uint256).max);
        vm.prank(bob);
        stablecoin.approve(address(underlying), type(uint256).max);

        vm.prank(charlie);
        stablecoin.approve(address(lendingpool), type(uint256).max);
        vm.prank(charlie);
        stablecoin.approve(address(options), type(uint256).max);
        vm.prank(charlie);
        stablecoin.approve(address(underlying), type(uint256).max);
    }

    //arrange
    //act
    //assert
}
