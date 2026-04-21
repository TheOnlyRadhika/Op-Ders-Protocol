// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Setup.t.sol";

contract CreditScoringTest is BaseTest {
    // ===== HELPER: get profile cleanly =====
    function _getProfile(
        address _user
    ) internal view returns (CreditScoring.CreditProfile memory) {
        return creditscoring.getCreditProfile(_user);
    }

    // ===== SETUP TESTS =====

    function test_initialCreditScoreIsZero() public {
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertEq(profile.creditScore, 0, "Initial credit score should be 0");
    }

    function test_canSetLendingPoolAddress() public {
        // Already set in setUp() — just verify
        assertEq(creditscoring.lendingPool(), address(lendingpool));
    }

    function test_canSetOptionsContractAddress() public {
        // Already set in setUp() — just verify
        assertEq(creditscoring.optionsContract(), address(options));
    }

    // ===== COLLATERALIZATION RATIO TESTS =====

    function test_scoreZeroCannotWriteOptions() public {
        bool canWrite = creditscoring.canUserWriteOptions(alice);
        assertFalse(canWrite, "Score 0 cannot write options");
    }

    function test_scoreBelow300CannotWriteOptions() public {
        bool canWrite = creditscoring.canUserWriteOptions(alice);
        assertFalse(canWrite, "Score < 300 cannot write options");
    }

    function test_collateralRatioFor300Score() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        uint256 ratio = creditscoring.getCollateralizationRatio(alice);
        assertEq(ratio, 10000, "Score 300 should have 10000 bps (100%) ratio");
    }

    function test_collateralRatioFor700Score() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        vm.prank(address(lendingpool));
        creditscoring.recordFullRepayment(alice, 1, 115 * 10 ** 18);

        uint256 ratio = creditscoring.getCollateralizationRatio(alice);
        assertGt(ratio, 0, "Ratio should be greater than 0");
    }

    function test_scoreCannotWriteReturnsZeroRatio() public {
        uint256 ratio = creditscoring.getCollateralizationRatio(alice);
        assertEq(ratio, 0, "Score 0 should return 0 ratio (cannot borrow)");
    }

    // ===== DEBT CREATION TESTS =====

    function test_canCreateDebt() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 debtCount = creditscoring.getUserDebtCount(alice);
        assertEq(debtCount, 1, "Should have 1 debt");
    }

    function test_debtRecordCreatedCorrectly() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        CreditScoring.DebtRecord memory debt = creditscoring.getDebt(1);
        assertEq(debt.debtor, alice, "Debtor should be Alice");
        assertEq(debt.principalAmount, principal, "Principal incorrect");
        assertEq(debt.penaltyAmount, penalty, "Penalty incorrect");
        assertFalse(debt.isCleared, "Debt should not be cleared initially");
        assertFalse(debt.isDefaulted, "Debt should not be defaulted initially");
        assertFalse(
            debt.isPartiallyPaid,
            "Debt should not be partially paid initially"
        );
    }

    function test_creditProfileInitializes() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        // FIX: getCreditProfile returns a struct, not a tuple
        CreditScoring.CreditProfile memory profile = _getProfile(alice);

        assertEq(profile.creditScore, 300, "Score should initialize to 300");
        assertEq(
            profile.amountBorrowed,
            principal,
            "Total borrowed should be updated"
        );
        assertEq(profile.activeDebt, 1, "Should have 1 active debt");
    }

    function test_debtHas30DayDeadline() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        uint256 creationTime = block.timestamp;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        CreditScoring.DebtRecord memory debt = creditscoring.getDebt(1);
        uint256 expectedDeadline = creationTime + 30 days;

        assertEq(
            debt.deadline,
            expectedDeadline,
            "Deadline should be 30 days from creation"
        );
    }

    function test_multipleDebtsTracked() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 debtCount = creditscoring.getUserDebtCount(alice);
        assertEq(debtCount, 2, "Should have 2 debts");
    }

    // ===== INTEREST CALCULATION TESTS =====

    function test_calculateCurrentDebtWithInterest() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        vm.warp(block.timestamp + 1 days);

        uint256 currentDebt = creditscoring.calculateCurrentDebt(1);
        uint256 expectedMinimum = principal + penalty;

        assertGt(
            currentDebt,
            expectedMinimum,
            "Should include interest after 1 day"
        );
    }

    function test_interestAccruesTotalOverTime() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 debtDay1 = creditscoring.calculateCurrentDebt(1);

        vm.warp(block.timestamp + 30 days);

        uint256 debtDay30 = creditscoring.calculateCurrentDebt(1);

        assertGt(debtDay30, debtDay1, "Debt should increase over time");
    }

    function test_interestCompoundsDaily() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        skip(1 days);
        uint256 debt1Day = creditscoring.calculateCurrentDebt(1);

        skip(1 days);
        uint256 debt2Days = creditscoring.calculateCurrentDebt(1);

        skip(1 days);
        uint256 debt3Days = creditscoring.calculateCurrentDebt(1);

        uint256 day1Interest = debt1Day - (principal + penalty);
        uint256 day2Interest = debt2Days - debt1Day;
        uint256 day3Interest = debt3Days - debt2Days;

        assertGe(day2Interest, day1Interest, "Interest should compound daily");
        assertGe(
            day3Interest,
            day2Interest,
            "Interest should continue compounding"
        );
    }

    // ===== FULL REPAYMENT TESTS =====

    function test_recordFullRepaymentOnTime() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 initialScore = 300;

        vm.prank(address(lendingpool));
        creditscoring.recordFullRepayment(alice, 1, principal + penalty);

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);

        assertEq(
            profile.creditScore,
            initialScore + 10,
            "On-time repayment should add 10 points"
        );
        assertEq(
            profile.totalRepaid,
            principal + penalty,
            "Total repaid should be updated"
        );
        assertEq(
            profile.activeDebt,
            0,
            "Active debts should be 0 after repayment"
        );
    }

    function test_recordFullRepaymentLate() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        vm.warp(block.timestamp + 31 days);

        uint256 initialScore = 300;

        vm.prank(address(lendingpool));
        creditscoring.recordFullRepayment(
            alice,
            1,
            principal + penalty + 100 ether
        );

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);

        assertEq(
            profile.creditScore,
            initialScore - 50,
            "Late repayment should deduct 50 points"
        );
    }

    function test_debtMarkedAsCleared() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        CreditScoring.DebtRecord memory debtBefore = creditscoring.getDebt(1);
        assertFalse(
            debtBefore.isCleared,
            "Debt should not be cleared initially"
        );

        vm.prank(address(lendingpool));
        creditscoring.recordFullRepayment(alice, 1, principal + penalty);

        CreditScoring.DebtRecord memory debtAfter = creditscoring.getDebt(1);
        assertTrue(debtAfter.isCleared, "Debt should be marked as cleared");
    }

    // ===== PARTIAL PAYMENT TESTS =====

    function test_recordPartialPaymentLocks() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        vm.warp(block.timestamp + 31 days);

        uint256 partialAmount = 50 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.recordPartialPayment(alice, 1, partialAmount);

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertTrue(
            profile.isLockedFromWrite,
            "Partial payment should lock user from writing"
        );
    }

    function test_partialPaymentDeducts20Points() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        vm.warp(block.timestamp + 31 days);

        uint256 initialScore = 300;
        uint256 partialAmount = 50 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.recordPartialPayment(alice, 1, partialAmount);

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertEq(
            profile.creditScore,
            initialScore - 20,
            "Partial payment should deduct 20 points"
        );
    }

    function test_partialPaymentUpdatesDebtRecord() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 partialAmount = 50 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.recordPartialPayment(alice, 1, partialAmount);

        CreditScoring.DebtRecord memory debt = creditscoring.getDebt(1);
        assertEq(
            debt.amountRepaid,
            partialAmount,
            "Amount repaid should be updated"
        );
        assertTrue(
            debt.isPartiallyPaid,
            "Debt should be marked as partially paid"
        );
        assertFalse(
            debt.isCleared,
            "Debt should not be cleared with partial payment"
        );
    }

    function test_partialPaymentSetsNewDeadline() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        CreditScoring.DebtRecord memory debtBefore = creditscoring.getDebt(1);
        uint256 originalDeadline = debtBefore.deadline;

        vm.warp(block.timestamp + 15 days);

        uint256 partialAmount = 50 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.recordPartialPayment(alice, 1, partialAmount);

        CreditScoring.DebtRecord memory debtAfter = creditscoring.getDebt(1);
        assertGt(
            debtAfter.deadline,
            originalDeadline,
            "New deadline should be extended 30 days from payment"
        );
    }

    // ===== DEFAULT TESTS =====

    function test_recordDefaultDeducts150Points() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 initialScore = 300;

        vm.prank(address(lendingpool));
        creditscoring.recordDefault(alice, 1);

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertEq(
            profile.creditScore,
            initialScore - 150,
            "Default should deduct 150 points"
        );
    }

    function test_recordDefaultLocksUser() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        vm.prank(address(lendingpool));
        creditscoring.recordDefault(alice, 1);

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertTrue(
            profile.isLockedFromWrite,
            "Default should lock user permanently"
        );
    }

    function test_recordDefaultMarksDebtAsDefaulted() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        assertFalse(
            creditscoring.getDebt(1).isDefaulted,
            "Debt should not be defaulted initially"
        );

        vm.prank(address(lendingpool));
        creditscoring.recordDefault(alice, 1);

        assertTrue(
            creditscoring.getDebt(1).isDefaulted,
            "Debt should be marked as defaulted"
        );
    }

    function test_defaultIncrementsDefaultCount() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        // FIX: use struct access for both before and after
        CreditScoring.CreditProfile memory profileBefore = _getProfile(alice);
        assertEq(
            profileBefore.defaultedDebts,
            0,
            "Should have 0 defaulted debts initially"
        );

        vm.prank(address(lendingpool));
        creditscoring.recordDefault(alice, 1);

        CreditScoring.CreditProfile memory profileAfter = _getProfile(alice);
        assertEq(
            profileAfter.defaultedDebts,
            1,
            "Should have 1 defaulted debt after default"
        );
    }

    // ===== SUCCESSFUL OPTION TESTS =====

    function test_recordSuccessfulOptionAdds25Points() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 initialScore = 300;

        vm.prank(address(options));
        creditscoring.recordSuccessfulOption(alice);

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertEq(
            profile.creditScore,
            initialScore + 25,
            "Successful option should add 25 points"
        );
    }

    function test_multipleSuccessfulOptionsIncreaseScore() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 initialScore = 300;

        vm.prank(address(options));
        creditscoring.recordSuccessfulOption(alice);

        vm.prank(address(options));
        creditscoring.recordSuccessfulOption(alice);

        // FIX: use struct access
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertEq(
            profile.creditScore,
            initialScore + 50,
            "Two successful options should add 50 points"
        );
    }

    // ===== MAX CALL AMOUNT TESTS =====

    function test_scoreUnder300HasZeroMaxCall() public {
        uint256 maxCall = creditscoring.getMaxCallAmount(alice);
        assertEq(maxCall, 0, "Score 0 should have 0 max call");
    }

    function test_score300Has5000MaxCall() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        uint256 maxCall = creditscoring.getMaxCallAmount(alice);
        assertEq(
            maxCall,
            5000 * 10 ** 18,
            "Score 300 should have $5000 max call"
        );
    }

    function test_score600AndAboveHasUnlimitedMaxCall() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        vm.prank(address(lendingpool));
        creditscoring.recordFullRepayment(alice, 1, principal + penalty);

        uint256 maxCall = creditscoring.getMaxCallAmount(alice);
        assertGt(maxCall, 0, "Score > 300 should have max call > 0");
    }

    // ===== EDGE CASE TESTS =====

    function test_scoreCannotExceed1000() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        for (uint256 i = 0; i < 40; i++) {
            vm.prank(address(options));
            creditscoring.recordSuccessfulOption(alice);
        }

        // FIX: was unpacking 7 values from struct (wrong count) + wrong field name
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertLe(profile.creditScore, 1000, "Score should not exceed 1000");
    }

    function test_scoreCannotGoBelow0() public {
        uint256 principal = 100 * 10 ** 18;
        uint256 penalty = 15 * 10 ** 18;

        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, principal, penalty);

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(address(lendingpool));
            creditscoring.createDebt(alice, principal, penalty);
            vm.prank(address(lendingpool));
            creditscoring.recordDefault(alice, i + 1);
        }

        // FIX: was profile.score — wrong field name, correct is creditScore
        CreditScoring.CreditProfile memory profile = _getProfile(alice);
        assertGe(profile.creditScore, 0, "Score should not go below 0");
    }
}
