// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Setup.t.sol";

contract OptionsTest is BaseTest {
    // ===== HELPER FUNCTIONS =====

    function _getProfile(
        address _user
    ) internal view returns (CreditScoring.CreditProfile memory) {
        return creditscoring.getCreditProfile(_user);
    }

    function _initAliceCredit() internal {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);
    }

    // ===== WRITE CALL TESTS =====

    function test_canWriteCall() public {
        _initAliceCredit();

        uint256 strikePrice = 3500 * 10 ** 18;
        uint256 premium = 500 * 10 ** 18;
        uint256 quantity = 10 * 10 ** 18;
        uint256 daysToExpiry = 30;

        vm.prank(alice);
        options.writeCall(strikePrice, premium, quantity, daysToExpiry);

        uint256[] memory writtenOptions = options.getUserWrittenOptions(alice);
        assertEq(
            writtenOptions.length,
            1,
            "Alice should have 1 written option"
        );
    }

    function test_writeCallCreatesOptionRecord() public {
        _initAliceCredit();

        uint256 strikePrice = 3500 * 10 ** 18;
        uint256 premium = 500 * 10 ** 18;
        uint256 quantity = 10 * 10 ** 18;
        uint256 daysToExpiry = 30;

        vm.prank(alice);
        options.writeCall(premium, strikePrice, daysToExpiry, quantity);

        Options.Option memory option = options.getOption(1);
        assertEq(option.writer, alice, "Writer should be Alice");
        assertEq(option.strikePrice, strikePrice, "Strike price should match");
        assertEq(option.premium, premium, "Premium should match");
        assertEq(option.quantity, quantity, "Quantity should match");
    }

    function test_writeCallOptionIsActive() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        Options.Option memory option = options.getOption(1);
        assertEq(
            uint8(option.status),
            uint8(Options.OptionStatus.ACTIVE),
            "Option should be ACTIVE"
        );
    }

    function test_writeCallHasNoBuyerInitially() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        Options.Option memory option = options.getOption(1);
        assertEq(option.buyer, address(0), "Should have no buyer initially");
        assertFalse(option.isPaid, "Premium should not be paid initially");
    }

    function test_cannotWriteCallWithoutCredit() public {
        // Alice has score 0 — cannot write
        vm.prank(alice);
        vm.expectRevert();
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);
    }

    // ===== WRITE PUT TESTS =====

    function test_canWritePut() public {
        _initAliceCredit();

        uint256 strikePrice = 3000 * 10 ** 18;
        uint256 premium = 200 * 10 ** 18;
        uint256 quantity = 10 * 10 ** 18;
        uint256 daysToExpiry = 30;

        vm.prank(alice);
        options.writePut(strikePrice, premium, quantity, daysToExpiry);

        uint256[] memory writtenOptions = options.getUserWrittenOptions(alice);
        assertEq(
            writtenOptions.length,
            1,
            "Alice should have 1 written option"
        );
    }

    function test_writePutCreatesOptionRecord() public {
        _initAliceCredit();

        uint256 strikePrice = 3000 * 10 ** 18;
        uint256 premium = 200 * 10 ** 18;
        uint256 quantity = 10 * 10 ** 18;

        vm.prank(alice);
        options.writePut(strikePrice, premium, quantity, 30);

        Options.Option memory option = options.getOption(1);
        assertEq(
            uint256(option.optionType),
            uint256(Options.OptionType.PUT),
            "Should be PUT option"
        );
        assertEq(option.strikePrice, strikePrice, "Strike price should match");
    }

    // ===== BUY OPTION TESTS =====

    function test_canBuyOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(bob);
        options.buyOption(1);

        Options.Option memory option = options.getOption(1);
        assertEq(option.buyer, bob, "Buyer should be Bob");
        assertTrue(option.isPaid, "Premium should be marked as paid");
    }

    function test_buyOptionTransfersPremium() public {
        _initAliceCredit();

        uint256 premium = 500 * 10 ** 18;

        uint256 aliceBalanceBefore = stablecoin.balanceOf(alice);
        uint256 bobBalanceBefore = stablecoin.balanceOf(bob);

        vm.prank(alice);
        options.writeCall(premium, 3500 * 10 ** 18, 30, 10 * 10 ** 18);

        vm.startPrank(bob);
        stablecoin.approve(address(options), premium);
        options.buyOption(1);
        vm.stopPrank();

        uint256 aliceBalanceAfter = stablecoin.balanceOf(alice);
        uint256 bobBalanceAfter = stablecoin.balanceOf(bob);

        assertGt(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Alice should receive premium"
        );
        assertLt(bobBalanceAfter, bobBalanceBefore, "Bob should pay premium");
    }

    function test_buyOptionRecordsBuyer() public {
        _initAliceCredit();

        vm.startPrank(alice);
        stablecoin.approve(address(options), type(uint256).max);
        underlying.approve(address(options), type(uint256).max);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);
        vm.stopPrank();

        vm.prank(bob);
        options.buyOption(1);

        uint256[] memory boughtOptions = options.getUserBoughtOptions(bob);
        assertEq(boughtOptions.length, 1, "Bob should have 1 bought option");
        assertEq(boughtOptions[0], 1, "Should be option ID 1");
    }

    function test_cannotBuyAlreadyBoughtOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(bob);
        options.buyOption(1);

        // Charlie tries to buy already bought option — should revert
        vm.prank(charlie);
        vm.expectRevert();
        options.buyOption(1);
    }

    // ===== EXERCISE CALL TESTS =====

    function test_buyerCanExerciseCall() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(bob);
        options.buyOption(1);

        vm.prank(bob);
        options.exerciseCall(1);

        Options.Option memory option = options.getOption(1);
        assertEq(
            uint8(option.status),
            uint8(Options.OptionStatus.EXERCISED),
            "Option should be exercised"
        );
    }

    function test_exerciseCallChangesStatus() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(bob);
        options.buyOption(1);

        Options.Option memory optionBefore = options.getOption(1);
        assertEq(
            uint8(optionBefore.status),
            uint8(Options.OptionStatus.ACTIVE),
            "Status should be ACTIVE before exercise"
        );

        vm.prank(bob);
        options.exerciseCall(1);

        Options.Option memory optionAfter = options.getOption(1);
        assertEq(
            uint8(optionAfter.status),
            uint8(Options.OptionStatus.EXERCISED),
            "Status should be EXERCISED after exercise"
        );
    }

    function test_cannotExerciseWithoutBuying() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        // Bob never bought — should revert
        vm.prank(bob);
        vm.expectRevert();
        options.exerciseCall(1);
    }

    // ===== EXERCISE PUT TESTS =====

    function test_buyerCanExercisePut() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writePut(3000 * 10 ** 18, 200 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(bob);
        options.buyOption(1);

        vm.prank(bob);
        options.exercisePut(1);

        Options.Option memory option = options.getOption(1);
        assertEq(
            uint8(option.status),
            uint8(Options.OptionStatus.EXERCISED),
            "Option should be exercised"
        );
    }

    // ===== SETTLEMENT TESTS =====

    function test_canSettleExpiredOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 30, 10 * 10 ** 18);

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        options.settleExpiredOption(1);

        Options.Option memory option = options.getOption(1);
        assertEq(
            uint8(option.status),
            uint8(Options.OptionStatus.EXPIRED),
            "Option should be expired"
        );
    }

    function test_settlementReturnsCollateral() public {
        _initAliceCredit();

        uint256 quantity = 10 * 10 ** 18;

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 30, quantity);

        // FIX: was 'underlying' — correct variable name from Setup is 'underlying'
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        options.settleExpiredOption(1);

        uint256 aliceBalanceAfter = underlying.balanceOf(alice);

        assertGt(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Collateral should be returned to Alice"
        );
    }

    function test_settlementUpdatesCredit() public {
        _initAliceCredit();

        // FIX: was tuple unpacking — getCreditProfile returns a struct
        CreditScoring.CreditProfile memory profileBefore = _getProfile(alice);
        uint256 scoreBefore = profileBefore.creditScore;

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 30, 10 * 10 ** 18);

        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        options.settleExpiredOption(1);

        // FIX: was tuple unpacking — getCreditProfile returns a struct
        CreditScoring.CreditProfile memory profileAfter = _getProfile(alice);
        uint256 scoreAfter = profileAfter.creditScore;

        assertGt(
            scoreAfter,
            scoreBefore,
            "Credit score should increase on successful settlement"
        );
    }

    // ===== CANCEL OPTION TESTS =====

    function test_writerCanCancelOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(alice);
        options.cancelOption(1);

        Options.Option memory option = options.getOption(1);
        assertEq(
            uint8(option.status),
            uint8(Options.OptionStatus.CANCELLED),
            "Option should be cancelled"
        );
    }

    function test_cancelOptionReturnCollateral() public {
        _initAliceCredit();

        uint256 quantity = 10 * 10 ** 18;

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, quantity, 30);

        // FIX: was 'underlying' — correct variable name is 'underlying'
        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        vm.prank(alice);
        options.cancelOption(1);

        uint256 aliceBalanceAfter = underlying.balanceOf(alice);

        assertGt(
            aliceBalanceAfter,
            aliceBalanceBefore,
            "Collateral should be returned"
        );
    }

    function test_cannotBuyCancelledOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(alice);
        options.cancelOption(1);

        vm.prank(bob);
        vm.expectRevert();
        options.buyOption(1);
    }

    // ===== EDGE CASE TESTS =====

    function test_cannotWriteZeroQuantity() public {
        _initAliceCredit();

        vm.prank(alice);
        vm.expectRevert();
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 0, 30);
    }

    function test_cannotWriteZeroPremium() public {
        _initAliceCredit();

        vm.prank(alice);
        vm.expectRevert();
        options.writeCall(3500 * 10 ** 18, 0, 10 * 10 ** 18, 30);
    }

    function test_cannotWriteZeroStrike() public {
        _initAliceCredit();

        vm.prank(alice);
        vm.expectRevert();
        options.writeCall(0, 500 * 10 ** 18, 10 * 10 ** 18, 30);
    }

    function test_multipleOptionsTracked() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(alice);
        options.writeCall(3600 * 10 ** 18, 600 * 10 ** 18, 10 * 10 ** 18, 30);

        uint256[] memory writtenOptions = options.getUserWrittenOptions(alice);
        assertEq(
            writtenOptions.length,
            2,
            "Alice should have 2 written options"
        );
    }

    // ===== ADDITIONAL EDGE CASES =====

    function test_cannotExerciseExpiredOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 30, 10 * 10 ** 18);

        vm.prank(bob);
        options.buyOption(1);

        // Move past expiry
        vm.warp(block.timestamp + 31 days);

        vm.prank(bob);
        vm.expectRevert();
        options.exerciseCall(1);
    }

    function test_cannotCancelBoughtOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        vm.prank(bob);
        options.buyOption(1);

        // Alice cannot cancel after Bob bought
        vm.prank(alice);
        vm.expectRevert();
        options.cancelOption(1);
    }

    function test_nonWriterCannotCancel() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        // Bob is not the writer — should revert
        vm.prank(bob);
        vm.expectRevert();
        options.cancelOption(1);
    }

    function test_cannotSettleBeforeExpiry() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        // Try to settle before expiry — should revert
        vm.prank(alice);
        vm.expectRevert();
        options.settleExpiredOption(1);
    }

    function test_writerCannotExerciseOwnOption() public {
        _initAliceCredit();

        vm.prank(alice);
        options.writeCall(3500 * 10 ** 18, 500 * 10 ** 18, 10 * 10 ** 18, 30);

        // Alice is writer not buyer — should revert
        vm.prank(alice);
        vm.expectRevert();
        options.exerciseCall(1);
    }
}
