// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract CreditScoring is Ownable {
    // CONSTRUCTOR
    constructor() Ownable(msg.sender) {}

    // ProfileTrackers
    struct CreditProfile {
        uint256 creditScore;
        uint256 amountBorrowed;
        uint256 totalRepaid;
        uint256 activeDebt;
        uint256 defaultedDebts;
        uint256 lastUpdated;
        bool isLockedFromWrite;
        uint256 lockedUntilTimestamp;
    }

    struct DebtRecord {
        address debtor;
        uint256 debtId;
        uint256 principalAmount;
        uint256 penaltyAmount;
        uint256 totalInterestAccrued;
        uint256 createdAt;
        uint256 deadline;
        uint256 amountRepaid;
        bool isCleared;
        bool isDefaulted;
        bool isPartiallyPaid;
    }

    // STATE VARIABLES
    mapping(address => CreditProfile) public creditProfiles;
    mapping(address => DebtRecord[]) public userDebts;
    mapping(uint256 => DebtRecord) public debtRecords;
    address public lendingPool;
    address public optionsContract;

    uint256 public nextDebtId = 1;

    // CONSTANTS
    uint256 constant BASE_SCORE = 300;
    uint256 constant MIN_SCORE_FOR_LIMITED_CALLS = 300;
    uint256 constant MIN_SCORE_FOR_UNLIMITED = 600;
    uint256 constant MIN_SCORE_FOR_BEST_RATIO = 800;

    // PENALTIES AND BONUSES
    uint256 constant PARTIAL_PAY_PENALTY = 20;
    uint256 constant LATE_PAY_PENALTY = 50;
    uint256 constant DEFAULT_PENALTY = 150;
    uint256 constant ON_TIME_BONUS = 10;
    uint256 constant QUICK_REPAY_BONUS = 10;
    uint256 constant SUCCESSFUL_OPTION_BONUS = 25;

    // EVENTS
    event CreditScoreUpdated(
        address indexed user,
        uint256 newScore,
        string reason
    );
    event DebtCreated(
        address indexed debtor,
        uint256 indexed debtId,
        uint256 principal
    );
    event DebtPartiallyPaid(
        address indexed debtor,
        uint256 indexed debtId,
        uint256 amountPaid
    );
    event DebtFullyRepaid(
        address indexed debtor,
        uint256 indexed debtId,
        uint256 totalRepaid
    );
    event DebtDefaulted(address indexed debtor, uint256 debtId);
    event UserLockedFromWriting(address indexed user, string reason);
    event UserUnlockedFromWriting(address indexed user);
    event LendingPoolSet(address indexed lendingPool);
    event OptionsContractSet(address indexed optionsContract);

    // ERRORS
    error DebtNotFound();
    error InvalidAddress();
    error InvalidDebtor();
    error InvalidPrincipal();
    error DebtMismatch();
    error DebtAlreadyCleared();
    error DebtIsDefaulted();
    error DebtAlreadyDefaulted();
    error OnlyPoolOrOptions();

    // SETTERS (Owner Only)
    function setLendingPool(address _lendingPool) external onlyOwner {
        if (_lendingPool == address(0)) revert InvalidAddress();
        lendingPool = _lendingPool;
        emit LendingPoolSet(_lendingPool);
    }

    function setOptionsContract(address _optionsContract) external onlyOwner {
        if (_optionsContract == address(0)) revert InvalidAddress();
        optionsContract = _optionsContract;
        emit OptionsContractSet(_optionsContract);
    }

    // DEBT MANAGEMENT
    function createDebt(
        address _debtor,
        uint256 _principalAmount,
        uint256 _penaltyAmount
    ) external {
        if (msg.sender != optionsContract && msg.sender != lendingPool) {
            revert OnlyPoolOrOptions();
        }
        if (_debtor == address(0)) revert InvalidDebtor();
        if (_principalAmount == 0) revert InvalidPrincipal();

        DebtRecord memory newDebt = DebtRecord({
            debtor: _debtor,
            debtId: nextDebtId,
            principalAmount: _principalAmount,
            penaltyAmount: _penaltyAmount,
            totalInterestAccrued: 0,
            createdAt: block.timestamp,
            deadline: block.timestamp + 30 days,
            amountRepaid: 0,
            isCleared: false,
            isDefaulted: false,
            isPartiallyPaid: false
        });

        debtRecords[nextDebtId] = newDebt;
        userDebts[_debtor].push(newDebt);

        CreditProfile storage profile = creditProfiles[_debtor];
        profile.activeDebt += 1;
        profile.amountBorrowed += _principalAmount;
        profile.lastUpdated = block.timestamp;

        if (profile.creditScore == 0) {
            profile.creditScore = BASE_SCORE;
        }

        emit DebtCreated(_debtor, nextDebtId, _principalAmount);
        nextDebtId++;
    }

    function recordPartialPayment(
        address _debtor,
        uint256 _debtId,
        uint256 _amountPaid
    ) external {
        if (msg.sender != lendingPool) revert OnlyPoolOrOptions();

        DebtRecord storage debt = debtRecords[_debtId];
        if (debt.debtor != _debtor) revert DebtMismatch();
        if (debt.isCleared) revert DebtAlreadyCleared();
        if (debt.isDefaulted) revert DebtIsDefaulted();

        debt.amountRepaid += _amountPaid;
        debt.isPartiallyPaid = true;
        debt.deadline = block.timestamp + 30 days;

        CreditProfile storage profile = creditProfiles[_debtor];
        profile.isLockedFromWrite = true;
        profile.lockedUntilTimestamp = debt.deadline;

        _updateCreditScore(
            _debtor,
            PARTIAL_PAY_PENALTY,
            false,
            "Partial payment - missed Day 30"
        );

        emit UserLockedFromWriting(_debtor, "Partial payment - missed Day 30");
        emit DebtPartiallyPaid(_debtor, _debtId, _amountPaid);
    }

    function recordFullRepayment(
        address _debtor,
        uint256 _debtId,
        uint256 _totalRepaid
    ) external {
        if (msg.sender != lendingPool) revert OnlyPoolOrOptions();

        DebtRecord storage debt = debtRecords[_debtId];
        if (debt.debtor != _debtor) revert DebtMismatch();
        if (debt.isCleared) revert DebtAlreadyCleared();

        debt.amountRepaid = _totalRepaid;
        debt.isCleared = true;

        CreditProfile storage profile = creditProfiles[_debtor];
        profile.activeDebt = profile.activeDebt > 0
            ? profile.activeDebt - 1
            : 0;
        profile.totalRepaid += _totalRepaid;
        profile.lastUpdated = block.timestamp;

        // Determine bonus based on timing
        if (block.timestamp <= debt.deadline && !debt.isPartiallyPaid) {
            _updateCreditScore(
                _debtor,
                ON_TIME_BONUS,
                true,
                "On-time full repayment"
            );
        } else if (block.timestamp > debt.deadline) {
            _updateCreditScore(
                _debtor,
                LATE_PAY_PENALTY,
                false,
                "Late repayment"
            );
        }

        // Unlock if no more debts
        if (profile.activeDebt == 0) {
            profile.isLockedFromWrite = false;
            profile.lockedUntilTimestamp = 0;
            emit UserUnlockedFromWriting(_debtor);
        }

        emit DebtFullyRepaid(_debtor, _debtId, _totalRepaid);
    }

    function recordDefault(address _debtor, uint256 _debtId) external {
        if (msg.sender != lendingPool) revert OnlyPoolOrOptions();

        DebtRecord storage debt = debtRecords[_debtId];
        if (debt.debtor != _debtor) revert DebtMismatch();
        if (debt.isDefaulted) revert DebtAlreadyDefaulted();

        debt.isDefaulted = true;

        CreditProfile storage profile = creditProfiles[_debtor];
        profile.defaultedDebts += 1;
        profile.activeDebt = profile.activeDebt > 0
            ? profile.activeDebt - 1
            : 0;
        profile.isLockedFromWrite = true;
        profile.lockedUntilTimestamp = type(uint256).max;

        _updateCreditScore(_debtor, DEFAULT_PENALTY, false, "Default on debt");

        emit DebtDefaulted(_debtor, _debtId);
        emit UserLockedFromWriting(_debtor, "Default on debt repayment");
    }

    function recordSuccessfulOption(address _writer) external {
        if (msg.sender != optionsContract) revert OnlyPoolOrOptions();

        _updateCreditScore(
            _writer,
            SUCCESSFUL_OPTION_BONUS,
            true,
            "Successful option expiry"
        );
    }

    // INTERNAL FUNCTIONS
    function _updateCreditScore(
        address _user,
        uint256 _amount,
        bool _isBonus,
        string memory _reason
    ) internal {
        CreditProfile storage profile = creditProfiles[_user];

        if (profile.creditScore == 0) {
            profile.creditScore = BASE_SCORE;
        }

        if (_isBonus) {
            profile.creditScore = profile.creditScore + _amount > 1000
                ? 1000
                : profile.creditScore + _amount;
        } else {
            profile.creditScore = profile.creditScore > _amount
                ? profile.creditScore - _amount
                : 0;
        }

        profile.lastUpdated = block.timestamp;
        emit CreditScoreUpdated(_user, profile.creditScore, _reason);
    }

    // VIEW FUNCTIONS
    function getCreditProfile(
        address _user
    ) external view returns (CreditProfile memory) {
        return creditProfiles[_user];
    }

    function getCollateralizationRatio(
        address _user
    ) external view returns (uint256) {
        uint256 score = creditProfiles[_user].creditScore;

        if (score < 300) {
            return 0; // Can't write
        } else if (score < 600) {
            return 10000; // 100%
        } else if (score < 800) {
            return 5000; // 50%
        } else {
            return 2500; // 25%
        }
    }

    function canUserWriteOptions(address _user) external view returns (bool) {
        CreditProfile memory profile = creditProfiles[_user];

        if (profile.isLockedFromWrite) {
            return false;
        }

        if (profile.creditScore < 300) {
            return false;
        }

        return true;
    }

    function getMaxCallAmount(address _user) external view returns (uint256) {
        uint256 score = creditProfiles[_user].creditScore;

        if (score >= 600) {
            return type(uint256).max; // Unlimited
        } else if (score >= 300) {
            return 5000 * 10 ** 18; // $5000 max
        } else {
            return 0; // Can't write
        }
    }

    function getDebt(
        uint256 _debtId
    ) external view returns (DebtRecord memory) {
        return debtRecords[_debtId];
    }

    function getUserDebts(
        address _user
    ) external view returns (DebtRecord[] memory) {
        return userDebts[_user];
    }

    function calculateCurrentDebt(
        uint256 _debtId
    ) external view returns (uint256) {
        DebtRecord memory debt = debtRecords[_debtId];

        if (debt.isCleared || debt.isDefaulted) {
            return 0;
        }

        uint256 timePassed = block.timestamp - debt.createdAt;

        // 10% APR = 0.0274% per day
        // 274 represents 0.0274% (274 / 1000000)
        uint256 dailyInterestRate = 274;
        uint256 interestAccrued = (debt.principalAmount *
            dailyInterestRate *
            timePassed) / (1000000 * 1 days);

        uint256 totalOwed = debt.principalAmount +
            debt.penaltyAmount +
            interestAccrued;

        return
            totalOwed > debt.amountRepaid ? totalOwed - debt.amountRepaid : 0;
    }

    function getUserDebtCount(address _user) external view returns (uint256) {
        return userDebts[_user].length;
    }
}
