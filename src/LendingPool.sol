// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CreditScoring.sol";

// interface ICreditScoring {
//     function recordPartialPayment(
//         address _debtor,
//         uint256 _debtId,
//         uint256 _amountPaid
//     ) external;

//     function recordFullRepayment(
//         address _debtor,
//         uint256 _debtId,
//         uint256 _totalRepaid
//     ) external;

//     function createDebt(
//         address _debtor,
//         uint256 _principalAmount,
//         uint256 _penaltyAmount
//     ) external;

//     function recordDefault(address _debtor, uint256 _debtId) external;

//     function getCreditProfile(
//         address _user
//     )
//         external
//         view
//         returns (
//             uint256 creditScore,
//             uint256 totalBorrowed,
//             uint256 totalRepaid,
//             uint256 activeDebts,
//             uint256 defaultedDebts,
//             uint256 lastUpdated,
//             bool isLockedFromWriting,
//             uint256 lockedUntilTimestamp
//         );

//     function calculateCurrentDebt(
//         uint256 _debtId
//     ) external view returns (uint256);

//     function getCollateralizationRatio(
//         address _user
//     ) external view returns (uint256);
// }
contract LendingPool is ReentrancyGuard, Ownable {
    struct Loan {
        address borrower;
        uint256 loanId;
        uint256 principalAmount;
        uint256 collateralAmount;
        uint256 interestRate;
        uint256 borrowTime;
        uint256 repaymentDeadline;
        uint256 amountRepaid;
        bool isRepaid;
        bool isDefaulted;
        uint256 debtIdInCreditScoring;
    }

    struct LenderDeposit {
        address lender;
        uint256 depositTime;
        uint256 depositAmount;
        uint256 interestEarned;
        uint256 lastWithdrawTime;
    }

    // STATE VARIABLES
    IERC20 public stablecoin;
    CreditScoring public creditScoring;

    mapping(uint256 => Loan) public loans;
    mapping(address => uint256[]) public userLoans;
    mapping(address => LenderDeposit) public lenderDeposits;
    mapping(address => uint256) public totalCollateralLocked;

    address[] public lenders;

    uint256 public nextLoanId = 1;
    uint256 public nextDebtId = 1;
    uint256 public poolBalance;
    uint256 public totalInterestEarned;

    uint256 public defaultThresholdDays = 7;
    uint256 public platformFeePercentage = 10; // 10 basis points = 0.1%
    uint256 public platformFeeCollected;

    mapping(uint256 => uint256) public interestRates;

    // EVENTS
    event DepositedToPool(address indexed lender, uint256 amount);
    event WithdrawnFromPool(
        address indexed lender,
        uint256 amount,
        uint256 interestEarned
    );
    event LoanCreated(
        address indexed borrower,
        uint256 indexed loanId,
        uint256 principal,
        uint256 collateral,
        uint256 interestRate,
        uint256 deadline
    );
    event LoanPartiallyRepaid(
        address indexed borrower,
        uint256 indexed loanId,
        uint256 amount,
        uint256 interestPaid
    );
    event LoanFullyRepaid(
        address indexed borrower,
        uint256 indexed loanId,
        uint256 totalRepaid,
        uint256 interestPaid
    );
    event LoanDefaulted(address indexed borrower, uint256 indexed loanId);
    event CollateralClaimed(
        address indexed borrower,
        uint256 indexed loanId,
        uint256 amount
    );
    event PoolBorrowedForOptions(
        address indexed borrower,
        uint256 amount,
        uint256 debtId
    );
    event InterestRateSet(uint256 scoreRange, uint256 basisPoints);
    event DefaultThresholdUpdated(uint256 newThreshold);

    // ERRORS
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientPoolBalance();
    error InsufficientBalance();
    error OnlyOptionsContract();
    error LoanNotFound();
    error LoanAlreadyRepaid();
    error CannotWithdraw();
    error NoDeposit();
    error LoanIsDefaulted();

    // CONSTRUCTOR
    constructor(
        address _stablecoin,
        address _creditScoring
    ) Ownable(msg.sender) {
        if (_stablecoin == address(0) || _creditScoring == address(0))
            revert InvalidAddress();

        stablecoin = IERC20(_stablecoin);
        creditScoring = CreditScoring(_creditScoring);

        // Initialize interest rate tiers
        // Score 0-300: 12% APR = 1200 bps
        interestRates[0] = 1200;
        // Score 300-600: 8% APR = 800 bps
        interestRates[1] = 800;
        // Score 600-800: 5% APR = 500 bps
        interestRates[2] = 500;
        // Score 800-1000: 2% APR = 200 bps
        interestRates[3] = 200;
    }

    // SETTERS (Owner Only)
    function setInterestRate(
        uint256 _scoreRange,
        uint256 _basisPoints
    ) external onlyOwner {
        interestRates[_scoreRange] = _basisPoints;
        emit InterestRateSet(_scoreRange, _basisPoints);
    }

    function setDefaultThreshold(uint256 _days) external onlyOwner {
        defaultThresholdDays = _days;
        emit DefaultThresholdUpdated(_days);
    }

    // LENDER OPERATIONS
    function depositToPool(uint256 _amount) external nonReentrant {
        if (_amount == 0) revert InvalidAmount();

        bool success = stablecoin.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        require(success, "Transfer failed");

        poolBalance += _amount;

        if (lenderDeposits[msg.sender].depositAmount == 0) {
            lenders.push(msg.sender);
        }

        lenderDeposits[msg.sender].lender = msg.sender;
        lenderDeposits[msg.sender].depositAmount += _amount;
        lenderDeposits[msg.sender].depositTime = block.timestamp;

        emit DepositedToPool(msg.sender, _amount);
    }

    function withdrawFromPool(uint256 _amount) external nonReentrant {
        LenderDeposit storage deposit = lenderDeposits[msg.sender];

        if (deposit.depositAmount == 0) revert NoDeposit();
        if (_amount == 0) revert InvalidAmount();
        if (_amount > poolBalance) revert InsufficientBalance();

        // Calculate interest earned
        uint256 interestEarned = _calculateLenderInterest(msg.sender);
        uint256 maxWithdrawable = deposit.depositAmount + interestEarned;

        if (_amount > maxWithdrawable) revert CannotWithdraw();

        // Update pool and deposits
        poolBalance -= _amount;
        deposit.depositAmount -= _amount;
        deposit.lastWithdrawTime = block.timestamp;

        // Transfer stablecoins to lender
        bool success = stablecoin.transfer(msg.sender, _amount);
        require(success, "Withdrawal failed");

        emit WithdrawnFromPool(msg.sender, _amount, interestEarned);
    }

    // BORROWER OPERATIONS
    function borrowWithCollateral(
        uint256 _collateralAmount,
        uint256 _loanDurationDays
    ) external nonReentrant {
        if (_collateralAmount == 0) revert InvalidAmount();
        if (_loanDurationDays == 0) revert InvalidAmount();
        if (poolBalance == 0) revert InsufficientPoolBalance();

        // Get user's credit profile
        CreditScoring.CreditProfile memory profile = creditScoring
            .getCreditProfile(msg.sender);

        uint256 creditScore = profile.creditScore;
        bool isLocked = profile.isLockedFromWrite;

        // Calculate max loan amount based on credit score
        uint256 maxLoanAmount = _calculateMaxLoanAmount(
            msg.sender,
            _collateralAmount,
            creditScore
        );

        if (maxLoanAmount == 0) revert InvalidAmount();
        if (maxLoanAmount > poolBalance) revert InsufficientPoolBalance();

        // Transfer collateral from borrower to contract
        bool collateralTransfer = stablecoin.transferFrom(
            msg.sender,
            address(this),
            _collateralAmount
        );
        require(collateralTransfer, "Collateral transfer failed");

        // Deduct platform fee from loan amount
        uint256 platformFee = (maxLoanAmount * platformFeePercentage) / 10000;
        uint256 netLoanAmount = maxLoanAmount - platformFee;

        // Get interest rate based on credit score
        uint256 interestRate = _getInterestRate(creditScore);

        // Create loan record
        uint256 loanId = nextLoanId++;
        loans[loanId] = Loan({
            borrower: msg.sender,
            loanId: loanId,
            principalAmount: maxLoanAmount,
            collateralAmount: _collateralAmount,
            interestRate: interestRate,
            borrowTime: block.timestamp,
            repaymentDeadline: block.timestamp + (_loanDurationDays * 1 days),
            amountRepaid: 0,
            isRepaid: false,
            isDefaulted: false,
            debtIdInCreditScoring: 0
        });

        userLoans[msg.sender].push(loanId);
        totalCollateralLocked[msg.sender] += _collateralAmount;
        poolBalance -= maxLoanAmount;
        platformFeeCollected += platformFee;

        // Transfer loan amount to borrower (net of fee)
        bool loanTransfer = stablecoin.transfer(msg.sender, netLoanAmount);
        require(loanTransfer, "Loan transfer failed");

        emit LoanCreated(
            msg.sender,
            loanId,
            maxLoanAmount,
            _collateralAmount,
            interestRate,
            block.timestamp + (_loanDurationDays * 1 days)
        );
    }

    function repayLoan(uint256 _loanId, uint256 _amount) external nonReentrant {
        Loan storage loan = loans[_loanId];

        // Basic Checks
        if (loan.borrower == address(0)) revert LoanNotFound();
        require(msg.sender == loan.borrower, "Not borrower");
        if (loan.isRepaid) revert LoanAlreadyRepaid();
        if (loan.isDefaulted) revert LoanIsDefaulted();
        if (_amount == 0) revert InvalidAmount();

        // 1. Calculate Total Owed (Principal + Simple Interest)
        uint256 currentInterest = _calculateLoanInterest(loan);
        uint256 totalOwed = loan.principalAmount + currentInterest;

        // 2. Prevent paying more than what is owed
        uint256 remaining = totalOwed - loan.amountRepaid;
        uint256 actualPayment = (_amount > remaining) ? remaining : _amount;

        // 3. Effects: Update state BEFORE external calls
        loan.amountRepaid += actualPayment;
        poolBalance += actualPayment;

        // 4. Interaction: Transfer funds from borrower
        bool success = stablecoin.transferFrom(
            msg.sender,
            address(this),
            actualPayment
        );
        require(success, "Transfer failed");

        // 5. Finalize if fully repaid
        if (loan.amountRepaid >= totalOwed) {
            loan.isRepaid = true;

            // Return collateral
            uint256 collateral = loan.collateralAmount;

            // This line reverts if Step 2 wasn't done correctly!
            totalCollateralLocked[loan.borrower] -= collateral;

            require(
                stablecoin.transfer(loan.borrower, collateral),
                "Collateral return failed"
            );

            emit LoanFullyRepaid(
                msg.sender,
                _loanId,
                loan.amountRepaid,
                currentInterest
            );
        } else {
            emit LoanPartiallyRepaid(msg.sender, _loanId, actualPayment, 0);
        }
    }

    // function repayLoan(uint256 _loanId, uint256 _amount) external nonReentrant {
    //     Loan storage loan = loans[_loanId];

    //     if (loan.borrower == address(0)) revert LoanNotFound();
    //     if (msg.sender != loan.borrower) {
    //         require(msg.sender == loan.borrower, "Not borrower");
    //     }
    //     if (loan.isRepaid) revert LoanAlreadyRepaid();
    //     if (loan.isDefaulted) revert LoanIsDefaulted();
    //     if (_amount == 0) revert InvalidAmount();

    //     // Calculate total owed including interest
    //     uint256 totalOwed = loan.principalAmount + _calculateLoanInterest(loan);
    //     uint256 remaining = totalOwed - loan.amountRepaid;

    //     if (_amount > remaining) {
    //         _amount = remaining;
    //     }
    //     loan.amountRepaid += _amount;

    //     // Transfer repayment
    //     bool repaymentTransfer = stablecoin.transferFrom(
    //         msg.sender,
    //         address(this),
    //         _amount
    //     );
    //     require(repaymentTransfer, "Repayment transfer failed");

    //     // Calculate interest portion of this payment
    //     uint256 interestPaid = _calculateInterestInPayment(loan, _amount);

    //     // Update loan

    //     poolBalance += _amount;
    //     totalInterestEarned += interestPaid;

    //     // Check if loan is fully repaid
    //     if (loan.amountRepaid >= totalOwed) {
    //         loan.isRepaid = true;

    //         // Return collateral to borrower
    //         bool collateralReturn = stablecoin.transfer(
    //             loan.borrower,
    //             loan.collateralAmount
    //         );
    //         require(collateralReturn, "Collateral return failed");

    //         totalCollateralLocked[loan.borrower] -= loan.collateralAmount;

    //         emit LoanFullyRepaid(
    //             msg.sender,
    //             _loanId,
    //             loan.amountRepaid,
    //             interestPaid
    //         );
    //     } else {
    //         emit LoanPartiallyRepaid(
    //             msg.sender,
    //             _loanId,
    //             _amount,
    //             interestPaid
    //         );
    //     }
    // }

    function claimDefaultedLoan(
        uint256 _loanId
    ) external onlyOwner nonReentrant {
        Loan storage loan = loans[_loanId];

        if (loan.borrower == address(0)) revert LoanNotFound();
        if (loan.isRepaid) revert LoanAlreadyRepaid();
        if (loan.isDefaulted) revert LoanIsDefaulted();

        // Check if loan is overdue
        uint256 daysPastDeadline = (block.timestamp - loan.repaymentDeadline) /
            1 days;
        require(daysPastDeadline >= defaultThresholdDays, "Not yet in default");

        // Mark as defaulted
        loan.isDefaulted = true;
        poolBalance += loan.collateralAmount;
        totalCollateralLocked[loan.borrower] -= loan.collateralAmount;

        // Record in credit scoring
        creditScoring.recordDefault(loan.borrower, _loanId);

        emit LoanDefaulted(loan.borrower, _loanId);
        emit CollateralClaimed(loan.borrower, _loanId, loan.collateralAmount);
    }

    // OPTIONS INTEGRATION
    function borrowForOptions(
        address _borrower,
        uint256 _amount
    ) external nonReentrant returns (uint256) {
        if (_amount == 0) revert InvalidAmount();
        if (_amount > poolBalance) revert InsufficientPoolBalance();

        // Calculate penalty (15% of borrowed amount)
        uint256 penaltyAmount = (_amount * 1500) / 10000;

        // Create debt in CreditScoring contract
        creditScoring.createDebt(_borrower, _amount, penaltyAmount);

        // Borrow from pool
        poolBalance -= _amount;

        uint256 debtId = nextDebtId++;

        emit PoolBorrowedForOptions(_borrower, _amount, debtId);

        return debtId;
    }

    function repayOptionsDebt(
        uint256 _debtId,
        uint256 _amount
    ) external nonReentrant {
        if (_amount == 0) revert InvalidAmount();

        // Transfer repayment from user
        bool success = stablecoin.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        require(success, "Repayment transfer failed");

        // Update pool balance
        poolBalance += _amount;

        // Emit event so backend can listen
        emit LoanPartiallyRepaid(msg.sender, _debtId, _amount, 0);
    }

    // INTERNAL VIEW FUNCTIONS
    function _calculateMaxLoanAmount(
        address _borrower,
        uint256 _collateralAmount,
        uint256 _creditscore
    ) internal view returns (uint256) {
        uint256 collateralizationRatio = creditScoring
            .getCollateralizationRatio(_borrower);

        if (collateralizationRatio == 0) return 0;

        // collateralizationRatio is in basis points (0-10000)
        // 10000 = 100% (must deposit full amount)
        // 5000 = 50% (can borrow 2x)
        // 2500 = 25% (can borrow 4x)

        uint256 maxLoan = (_collateralAmount * 10000) / collateralizationRatio;

        return maxLoan;
    }

    function _getInterestRate(
        uint256 _creditScore
    ) internal view returns (uint256) {
        if (_creditScore < 300) {
            return interestRates[0]; // 12%
        } else if (_creditScore < 600) {
            return interestRates[1]; // 8%
        } else if (_creditScore < 800) {
            return interestRates[2]; // 5%
        } else {
            return interestRates[3]; // 2%
        }
    }

    function _calculateLoanInterest(
        Loan memory _loan
    ) internal view returns (uint256) {
        if (_loan.isRepaid || _loan.isDefaulted) {
            return 0;
        }

        uint256 timePassed = block.timestamp - _loan.borrowTime;

        // Interest = principal × (rate bps / 10000) × (days / 365)
        uint256 interestAccrued = (_loan.principalAmount *
            _loan.interestRate *
            timePassed) / (10000 * 365 days);

        // uint256 totalOwed = _loan.principalAmount + interestAccrued;

        // return totalOwed;
        return interestAccrued;
    }

    function _calculateInterestInPayment(
        Loan memory _loan,
        uint256 _paymentAmount
    ) internal view returns (uint256) {
        uint256 totalOwed = _calculateLoanInterest(_loan);
        uint256 remainingPrincipal = _loan.principalAmount -
            (
                _loan.amountRepaid > _loan.principalAmount
                    ? _loan.principalAmount
                    : _loan.amountRepaid
            );

        uint256 interestRemaining = totalOwed - _loan.principalAmount;

        if (_paymentAmount > remainingPrincipal) {
            return _paymentAmount - remainingPrincipal;
        } else {
            return 0;
        }
    }

    function _calculateLenderInterest(
        address _lender
    ) internal view returns (uint256) {
        LenderDeposit memory deposit = lenderDeposits[_lender];

        if (deposit.depositAmount == 0) return 0;

        uint256 timeInPool = block.timestamp - deposit.depositTime;
        uint256 daysInPool = timeInPool / 1 days;

        // Simple calculation: 5% average APR on borrowed funds
        uint256 estimatedInterest = (deposit.depositAmount * 5 * daysInPool) /
            (100 * 365);

        return estimatedInterest;
    }

    // PUBLIC VIEW FUNCTIONS
    function getLoan(uint256 _loanId) external view returns (Loan memory) {
        return loans[_loanId];
    }

    function getUserLoans(
        address _user
    ) external view returns (uint256[] memory) {
        return userLoans[_user];
    }

    function getUserLoanCount(address _user) external view returns (uint256) {
        return userLoans[_user].length;
    }

    function getPoolStats()
        external
        view
        returns (
            uint256 currentBalance,
            uint256 totalEarned,
            uint256 numLenders,
            uint256 platformFees
        )
    {
        return (
            poolBalance,
            totalInterestEarned,
            lenders.length,
            platformFeeCollected
        );
    }

    function getLenderStats(
        address _lender
    )
        external
        view
        returns (
            uint256 depositAmount,
            uint256 depositTime,
            uint256 interestEarned,
            uint256 maxWithdrawable
        )
    {
        LenderDeposit memory deposit = lenderDeposits[_lender];
        uint256 earned = _calculateLenderInterest(_lender);

        return (
            deposit.depositAmount,
            deposit.depositTime,
            earned,
            deposit.depositAmount + earned
        );
    }

    function getBorrowerStats(
        address _borrower
    )
        external
        view
        returns (
            uint256 totalLoans,
            uint256 collateralLocked,
            uint256 activeLoans,
            uint256 repaidLoans
        )
    {
        uint256[] memory borrowerLoans = userLoans[_borrower];
        uint256 active = 0;
        uint256 repaid = 0;

        for (uint256 i = 0; i < borrowerLoans.length; i++) {
            Loan memory loan = loans[borrowerLoans[i]];
            if (loan.isRepaid) {
                repaid++;
            } else if (!loan.isDefaulted) {
                active++;
            }
        }

        return (
            borrowerLoans.length,
            totalCollateralLocked[_borrower],
            active,
            repaid
        );
    }

    function getMaxBorrowAmount(
        address _borrower,
        uint256 _collateralAmount
    ) external view returns (uint256) {
        CreditScoring.CreditProfile memory profile = creditScoring
            .getCreditProfile(_borrower);

        return
            _calculateMaxLoanAmount(
                _borrower,
                _collateralAmount,
                profile.creditScore
            );
    }

    function getInterestRateForScore(
        uint256 _creditScore
    ) external view returns (uint256) {
        return _getInterestRate(_creditScore);
    }

    /**
     * @notice Returns the total amount (Principal + Interest) minus what was already paid
     */
    function getRemainingAmount(uint256 _loanId) public view returns (uint256) {
        Loan storage loan = loans[_loanId];
        if (loan.borrower == address(0)) revert LoanNotFound();
        if (loan.isRepaid) return 0;
        // 1. Calculate total debt (Live Principal + Live Interest)
        uint256 totalOwed = loan.principalAmount + _calculateLoanInterest(loan);

        // 2. Subtract what has already been paid
        if (loan.amountRepaid >= totalOwed) return 0;

        return totalOwed - loan.amountRepaid;
    }
}
