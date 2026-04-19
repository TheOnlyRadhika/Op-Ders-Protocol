// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Setup.t.sol";

contract LendingPoolTest is BaseTest {
    // ===== DEPOSIT TESTS =====

    function test_canDepositToPool() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(amount);

        (uint256 balance, , , ) = lendingpool.getPoolStats();
        assertEq(balance, amount, "Pool balance should equal deposit");
    }

    function test_depositUpdatesLenderInfo() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(amount);

        (uint256 depositAmount, , , uint256 maxWithdrawable) = lendingpool
            .getLenderStats(alice);
        assertEq(
            depositAmount,
            amount,
            "Lender deposit amount should be recorded"
        );
        assertGt(maxWithdrawable, 0, "Should be able to withdraw");
    }

    function test_multipleDepositsAddUp() public {
        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 500 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(amount1);

        vm.prank(bob);
        lendingpool.depositToPool(amount2);

        (uint256 balance, , , ) = lendingpool.getPoolStats();
        assertEq(balance, amount1 + amount2, "Pool should have both deposits");
    }

    function test_depositIncreasesLenderBalance() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 aliceBalanceBefore = stablecoin.balanceOf(alice);

        vm.prank(alice);
        lendingpool.depositToPool(amount);

        uint256 aliceBalanceAfter = stablecoin.balanceOf(alice);
        assertEq(
            aliceBalanceBefore - aliceBalanceAfter,
            amount,
            "Alice balance should decrease by deposit amount"
        );
    }

    function test_cannotDepositZero() public {
        vm.prank(alice);
        vm.expectRevert();
        lendingpool.depositToPool(0);
    }

    // ===== WITHDRAWAL TESTS =====

    function test_canWithdrawFromPool() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(depositAmount);

        uint256 aliceBalanceBefore = stablecoin.balanceOf(alice);

        vm.prank(alice);
        lendingpool.withdrawFromPool(depositAmount);

        uint256 aliceBalanceAfter = stablecoin.balanceOf(alice);
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore + depositAmount,
            "Alice should receive her deposit"
        );
    }

    function test_cannotWithdrawMoreThanDeposited() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(depositAmount);

        uint256 withdrawAmount = 2000 * 10 ** 18;

        vm.prank(alice);
        vm.expectRevert();
        lendingpool.withdrawFromPool(withdrawAmount);
    }

    function test_cannotWithdrawWithoutDeposit() public {
        vm.prank(alice);
        vm.expectRevert();
        lendingpool.withdrawFromPool(100 * 10 ** 18);
    }

    function test_withdrawalUpdatesPoolBalance() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(depositAmount);

        (uint256 balanceBefore, , , ) = lendingpool.getPoolStats();
        assertEq(balanceBefore, depositAmount, "Pool should have full deposit");

        vm.prank(alice);
        lendingpool.withdrawFromPool(depositAmount);

        (uint256 balanceAfter, , , ) = lendingpool.getPoolStats();
        assertEq(
            balanceAfter,
            0,
            "Pool balance should be 0 after full withdrawal"
        );
    }

    // ===== BORROW TESTS =====

    function test_canBorrowWithCollateral() public {
        // First, deposit to pool so there's liquidity
        vm.prank(bob);
        lendingpool.depositToPool(5000 * 10 ** 18);

        // Alice tries to borrow but her score is 0, so this should fail
        uint256 collateralAmount = 500 * 10 ** 18;
        uint256 loanDurationDays = 30;

        vm.prank(alice);
        vm.expectRevert();
        lendingpool.borrowWithCollateral(collateralAmount, loanDurationDays);
    }

    function test_borrowCreatesLoanRecord() public {
        // Setup: Create debt to initialize alice's credit score to 300
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        // Deposit liquidity
        vm.prank(bob);
        lendingpool.depositToPool(5000 * 10 ** 18);

        uint256 collateralAmount = 500 * 10 ** 18;
        uint256 loanDurationDays = 30;

        vm.prank(alice);
        lendingpool.borrowWithCollateral(collateralAmount, loanDurationDays);

        LendingPool.Loan memory loan = lendingpool.getLoan(1);
        assertEq(loan.borrower, alice, "Loan borrower should be Alice");
        assertEq(
            loan.collateralAmount,
            collateralAmount,
            "Collateral should match"
        );
    }

    function test_borrowLocksCollateral() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        vm.prank(bob);
        lendingpool.depositToPool(5000 * 10 ** 18);

        uint256 collateralAmount = 500 * 10 ** 18;

        vm.prank(alice);
        lendingpool.borrowWithCollateral(collateralAmount, 30);

        uint256 lockedCollateral = lendingpool.totalCollateralLocked(alice);

        assertEq(
            lockedCollateral,
            500 * 10 ** 18,
            "Collateral should be recorded in protocol"
        );
    }

    function test_borrowReducesPoolBalance() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        uint256 depositAmount = 5000 * 10 ** 18;
        vm.prank(bob);
        lendingpool.depositToPool(depositAmount);

        (uint256 poolBalanceBefore, , , ) = lendingpool.getPoolStats();

        uint256 collateralAmount = 500 * 10 ** 18;

        vm.prank(alice);
        lendingpool.borrowWithCollateral(collateralAmount, 30);

        (uint256 poolBalanceAfter, , , ) = lendingpool.getPoolStats();

        assertLt(
            poolBalanceAfter,
            poolBalanceBefore,
            "Pool balance should decrease after loan"
        );
    }

    function test_cannotBorrowIfPoolEmpty() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        // No deposits, pool is empty
        uint256 collateralAmount = 500 * 10 ** 18;

        vm.prank(alice);
        vm.expectRevert();
        lendingpool.borrowWithCollateral(collateralAmount, 30);
    }

    // ===== REPAYMENT TESTS =====

    function test_canRepayLoan() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        vm.prank(bob);
        lendingpool.depositToPool(5000 * 10 ** 18);

        uint256 collateralAmount = 500 * 10 ** 18;

        vm.prank(alice);
        lendingpool.borrowWithCollateral(collateralAmount, 30);

        // Repay

        LendingPool.Loan memory loan = lendingpool.getLoan(1);
        uint256 repayAmount = loan.principalAmount;

        vm.startPrank(alice);
        stablecoin.approve(address(lendingpool), repayAmount);
        lendingpool.repayLoan(1, repayAmount);
        vm.stopPrank();

        LendingPool.Loan memory updatedLoan = lendingpool.getLoan(1);

        assertEq(
            updatedLoan.amountRepaid,
            repayAmount,
            "Repay amount should be recorded"
        );
    }

    function test_repaymentReturnsCollateral() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        vm.startPrank(bob);
        stablecoin.approve(address(lendingpool), 5000 * 10 ** 18);
        lendingpool.depositToPool(5000 * 10 ** 18);
        vm.stopPrank();

        uint256 aliceBalanceBefore = stablecoin.balanceOf(alice);

        uint256 collateralAmount = 500 * 10 ** 18;

        vm.startPrank(alice);
        stablecoin.approve(address(lendingpool), collateralAmount);
        lendingpool.borrowWithCollateral(collateralAmount, 30);
        vm.stopPrank();

        // Calculate total owed (principal + interest estimate)
        uint256 repayAmount = lendingpool.getRemainingAmount(1);

        vm.startPrank(alice);
        stablecoin.approve(address(lendingpool), repayAmount);
        lendingpool.repayLoan(1, repayAmount);
        vm.stopPrank();

        uint256 aliceBalanceAfter = stablecoin.balanceOf(alice);

        // Alice should get collateral back
        assertGt(
            aliceBalanceBefore,
            aliceBalanceAfter,
            "Collateral should be returned to Alice"
        );
    }

    function test_fullRepaymentMarksLoanAsRepaid() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        vm.startPrank(bob);
        stablecoin.approve(address(lendingpool), 5000 * 10 ** 18);
        lendingpool.depositToPool(5000 * 10 ** 18);
        vm.stopPrank();

        // vm.prank(bob);
        // lendingpool.depositToPool(5000 * 10 ** 18);

        uint256 collateralAmount = 500 * 10 ** 18;

        vm.startPrank(alice);
        stablecoin.approve(address(lendingpool), collateralAmount);
        lendingpool.borrowWithCollateral(collateralAmount, 30);
        vm.stopPrank();

        LendingPool.Loan memory loanBefore = lendingpool.getLoan(1);
        assertFalse(loanBefore.isRepaid, "Loan should not be repaid initially");

        uint256 repayAmount = lendingpool.getRemainingAmount(1);

        vm.startPrank(alice);
        stablecoin.approve(address(lendingpool), repayAmount);
        lendingpool.repayLoan(1, repayAmount);
        vm.stopPrank();

        LendingPool.Loan memory loanAfter = lendingpool.getLoan(1);
        assertTrue(loanAfter.isRepaid, "Loan should be marked as repaid");
    }

    function test_partialRepaymentDoesNotMarkAsRepaid() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        vm.startPrank(bob);
        stablecoin.approve(address(lendingpool), 5000 * 10 ** 18);
        lendingpool.depositToPool(5000 * 10 ** 18);
        vm.stopPrank();

        uint256 collateralAmount = 500 * 10 ** 18;

        vm.startPrank(alice);
        stablecoin.approve(address(lendingpool), collateralAmount);
        lendingpool.borrowWithCollateral(collateralAmount, 30);
        vm.stopPrank();

        // vm.warp(block.timestamp + 15 days);

        uint256 partialRepay = 20 * 10 ** 18;

        vm.startPrank(alice);
        stablecoin.approve(address(lendingpool), partialRepay);
        lendingpool.repayLoan(1, partialRepay);
        vm.stopPrank();

        LendingPool.Loan memory loan = lendingpool.getLoan(1);
        assertFalse(
            loan.isRepaid,
            "Loan should not be marked as repaid with partial payment"
        );
    }

    // ===== INTEREST RATE TESTS =====

    function test_differentScoresHaveDifferentInterestRates() public {
        uint256 rate0 = lendingpool.getInterestRateForScore(250); // 0-300
        uint256 rate1 = lendingpool.getInterestRateForScore(400); // 300-600
        uint256 rate2 = lendingpool.getInterestRateForScore(700); // 600-800
        uint256 rate3 = lendingpool.getInterestRateForScore(900); // 800-1000

        assertGt(rate0, rate1, "Lower scores should have higher rates");
        assertGt(rate1, rate2, "Lower scores should have higher rates");
        assertGt(rate2, rate3, "Lower scores should have higher rates");
    }

    function test_interestRatesAreLessThan20Percent() public {
        uint256 rate = lendingpool.getInterestRateForScore(250);
        assertLe(rate, 2000, "Interest rate should not exceed 20%");
    }

    // ===== POOL STATS TESTS =====

    function test_poolStatsShowCorrectBalance() public {
        uint256 deposit1 = 1000 * 10 ** 18;
        uint256 deposit2 = 500 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(deposit1);

        vm.prank(bob);
        lendingpool.depositToPool(deposit2);

        (uint256 balance, , uint256 numLenders, ) = lendingpool.getPoolStats();
        assertEq(
            balance,
            deposit1 + deposit2,
            "Pool balance should be sum of deposits"
        );
        assertEq(numLenders, 2, "Should have 2 lenders");
    }

    function test_poolStatsShowInterestEarned() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        vm.prank(alice);
        lendingpool.depositToPool(depositAmount);

        (uint256 balance, uint256 interestEarned, , ) = lendingpool
            .getPoolStats();

        assertGe(
            balance,
            depositAmount,
            "Pool balance should be at least deposit"
        );
        assertGe(interestEarned, 0, "Interest earned should be tracked");
    }

    // ===== BORROW FOR OPTIONS TESTS =====

    function test_borrowForOptionsCreatesDebt() public {
        vm.prank(bob);
        lendingpool.depositToPool(5000 * 10 ** 18);

        uint256 borrowAmount = 100 * 10 ** 18;

        vm.prank(address(options));
        uint256 debtId = lendingpool.borrowForOptions(alice, borrowAmount);

        assertGt(debtId, 0, "Debt ID should be created");
    }

    function test_borrowForOptionsReducesPoolBalance() public {
        uint256 initialDeposit = 5000 * 10 ** 18;

        vm.prank(bob);
        lendingpool.depositToPool(initialDeposit);

        (uint256 balanceBefore, , , ) = lendingpool.getPoolStats();

        uint256 borrowAmount = 100 * 10 ** 18;

        vm.prank(address(options));
        lendingpool.borrowForOptions(alice, borrowAmount);

        (uint256 balanceAfter, , , ) = lendingpool.getPoolStats();

        assertEq(
            balanceBefore - balanceAfter,
            borrowAmount,
            "Pool balance should decrease by borrowed amount"
        );
    }

    function test_cannotBorrowMoreThanPoolBalance() public {
        vm.prank(bob);
        lendingpool.depositToPool(100 * 10 ** 18);

        uint256 borrowAmount = 1000 * 10 ** 18;

        vm.prank(address(options));
        vm.expectRevert();
        lendingpool.borrowForOptions(alice, borrowAmount);
    }

    function test_repayOptionsDebtIncreasesPoolBalance() public {
        vm.prank(bob);
        lendingpool.depositToPool(5000 * 10 ** 18);

        uint256 borrowAmount = 100 * 10 ** 18;

        vm.prank(address(options));
        lendingpool.borrowForOptions(alice, borrowAmount);

        (uint256 balanceAfter, , , ) = lendingpool.getPoolStats();
        uint256 balanceAfterBorrow = balanceAfter;

        uint256 repayAmount = 100 * 10 ** 18;

        vm.prank(alice);
        lendingpool.repayOptionsDebt(1, repayAmount);

        (uint256 balanceAfterRepay, , , ) = lendingpool.getPoolStats();

        assertGt(
            balanceAfterRepay,
            balanceAfterBorrow,
            "Pool balance should increase after repayment"
        );
    }

    // ===== BORROWER STATS TESTS =====

    function test_getBorrowerStats() public {
        vm.prank(address(lendingpool));
        creditscoring.createDebt(alice, 100 * 10 ** 18, 15 * 10 ** 18);

        vm.prank(bob);
        lendingpool.depositToPool(5000 * 10 ** 18);

        vm.prank(alice);
        lendingpool.borrowWithCollateral(500 * 10 ** 18, 30);

        (
            uint256 totalLoans,
            uint256 collateralLocked,
            uint256 activeLoans,
            uint256 repaidLoans
        ) = lendingpool.getBorrowerStats(alice);

        assertEq(totalLoans, 1, "Should have 1 loan");
        assertEq(
            collateralLocked,
            500 * 10 ** 18,
            "Should have 500 collateral locked"
        );
        assertEq(activeLoans, 1, "Should have 1 active loan");
        assertEq(repaidLoans, 0, "Should have 0 repaid loans");
    }
}
