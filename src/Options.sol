// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CreditScoring.sol";

// interface ICreditScoring {
//     function getCollateralizationRatio(
//         address _user
//     ) external view returns (uint256);

//     function canUserWriteOptions(address _user) external view returns (bool);

//     function createDebt(
//         address _debtor,
//         uint256 _principalAmount,
//         uint256 _penaltyAmount
//     ) external;

//     function recordSuccessfulOption(address _writer) external;

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
// }

interface ILendingPool {
    function borrowForOptions(
        address _borrower,
        uint256 _amount
    ) external returns (uint256);
}

/**
 * OPTIONS CONTRACT
 *
 * Handles options trading (calls and puts)
 * Integrates with CreditScoring and LendingPool
 * Manages under-collateralized options via credit-backing
 */

contract Options is ReentrancyGuard, Ownable {
    // ===== ENUMS =====

    enum OptionType {
        CALL,
        PUT
    }
    enum OptionStatus {
        ACTIVE,
        EXERCISED,
        EXPIRED,
        CANCELLED
    }

    // ===== DATA STRUCTURES =====

    struct Option {
        uint256 optionId;
        address writer; // Who created the option
        address buyer; // Who bought the option (0 if not sold yet)
        OptionType optionType; // CALL or PUT
        address underlyingToken; // The token (ETH, USDC, etc.)
        uint256 strikePrice; // Exercise price
        uint256 premium; // Price to buy this option
        uint256 quantity; // Amount of underlying asset
        uint256 collateralLocked; // Collateral from writer
        uint256 creditBackedAmount; // Credit-backed portion from system
        uint256 createdAt; // Timestamp created
        uint256 expiryTime; // When option expires
        OptionStatus status; // Current status
        bool isPaid; // Premium paid by buyer?
        uint256 debtIdInCreditScoring; // If credit-backed, the debt ID
    }

    // ===== STATE VARIABLES =====

    CreditScoring public creditScoring;
    ILendingPool public lendingPool;
    IERC20 public underlyingToken; // The asset being traded (e.g., WETH)
    IERC20 public stablecoin; // For collateral (USDC)

    mapping(uint256 => Option) public options;
    mapping(address => uint256[]) public userWrittenOptions;
    mapping(address => uint256[]) public userBoughtOptions;
    mapping(address => uint256) public collateralLocked;

    uint256 public nextOptionId = 1;
    uint256 public platformFeePercentage = 25; // 25 basis points = 0.25%
    uint256 public platformFeeCollected;

    // ===== EVENTS =====

    event OptionCreated(
        uint256 indexed optionId,
        address indexed writer,
        OptionType optionType,
        uint256 strikePrice,
        uint256 premium,
        uint256 quantity,
        uint256 expiryTime,
        uint256 collateralLocked,
        uint256 creditBackedAmount
    );

    event OptionBought(
        uint256 indexed optionId,
        address indexed buyer,
        uint256 premium
    );
    event OptionExercised(uint256 indexed optionId, address indexed buyer);
    event OptionExpired(uint256 indexed optionId, address indexed writer);
    event OptionCancelled(uint256 indexed optionId, address indexed writer);
    event CreditBackedBorrowed(uint256 indexed optionId, uint256 amount);
    event CollateralReturned(address indexed writer, uint256 amount);

    // ===== ERRORS =====

    error InvalidAddress();
    error InvalidAmount();
    error CannotWriteOptions();
    error InsufficientCollateral();
    error OptionNotFound();
    error OptionNotActive();
    error NotOptionWriter();
    error NotOptionBuyer();
    error PremiumNotPaid();
    error OptionAlreadyExercised();
    error OnlyLendingPool();

    // ===== CONSTRUCTOR =====

    constructor(
        address _creditScoring,
        address _lendingPool,
        address _underlyingToken,
        address _stablecoin
    ) Ownable(msg.sender) {
        if (
            _creditScoring == address(0) ||
            _lendingPool == address(0) ||
            _underlyingToken == address(0) ||
            _stablecoin == address(0)
        ) {
            revert InvalidAddress();
        }

        creditScoring = CreditScoring(_creditScoring);
        lendingPool = ILendingPool(_lendingPool);
        underlyingToken = IERC20(_underlyingToken);
        stablecoin = IERC20(_stablecoin);
    }

    // ===== ADMIN FUNCTIONS =====

    function setPlatformFee(uint256 _basisPoints) external onlyOwner {
        require(_basisPoints <= 100, "Fee too high"); // Max 1%
        platformFeePercentage = _basisPoints;
    }

    function withdrawFees() external onlyOwner {
        require(platformFeeCollected > 0, "No fees to withdraw");
        uint256 amount = platformFeeCollected;
        platformFeeCollected = 0;

        bool success = stablecoin.transfer(msg.sender, amount);
        require(success, "Fee withdrawal failed");
    }

    function writeCall(
        uint256 _premium,
        uint256 _strikePrice,
        uint256 _daysToExpire,
        uint256 _quantity
    ) external nonReentrant {
        if (
            _premium == 0 ||
            _daysToExpire == 0 ||
            _strikePrice == 0 ||
            _quantity == 0
        ) {
            revert InvalidAmount();
        }
        // CHECK WHETHER USER CAN WRITE OPTIONS
        if (!creditScoring.canUserWriteOptions(msg.sender))
            revert CannotWriteOptions();
        uint256 collateralisationRatio = creditScoring
            .getCollateralizationRatio(msg.sender);

        uint256 fullCollateralNeeded = _quantity;
        uint256 userMustDeposit = (fullCollateralNeeded *
            collateralisationRatio) / 10000;
        uint256 creditBackedAmount = fullCollateralNeeded - userMustDeposit;

        // collateral transfer
        bool collateralTransfer = underlyingToken.transferFrom(
            msg.sender,
            address(this),
            userMustDeposit
        );
        require(collateralTransfer, "Collateral Transfer Failed");

        // calculating platform fees
        uint256 platformFee = (_premium * platformFeePercentage) / 10000;
        uint256 premiumAfterFee = _premium - platformFee;
        platformFeeCollected += platformFee;

        // writing the option
        uint256 optionId = nextOptionId++;

        options[optionId] = Option({
            optionId: optionId,
            writer: msg.sender,
            buyer: address(0), // No buyer yet
            optionType: OptionType.CALL,
            underlyingToken: address(underlyingToken),
            strikePrice: _strikePrice,
            premium: _premium,
            quantity: _quantity,
            collateralLocked: userMustDeposit,
            creditBackedAmount: creditBackedAmount,
            createdAt: block.timestamp,
            expiryTime: block.timestamp + (_daysToExpire * 1 days),
            status: OptionStatus.ACTIVE,
            isPaid: false,
            debtIdInCreditScoring: 0
        });
        // ===== UPDATE TRACKING =====
        userWrittenOptions[msg.sender].push(optionId);
        collateralLocked[msg.sender] += userMustDeposit;

        // ===== TRANSFER PREMIUM TO WRITER =====

        // Send premium to writer immediately (before anyone buys)
        // This is why the contract needs stablecoin
        bool premiumTransfer = stablecoin.transfer(msg.sender, premiumAfterFee);
        require(premiumTransfer, "Premium transfer failed");

        emit OptionCreated(
            optionId,
            msg.sender,
            OptionType.CALL,
            _strikePrice,
            _premium,
            _quantity,
            block.timestamp + (_daysToExpire * 1 days),
            userMustDeposit,
            creditBackedAmount
        );
    }

    function writePut(
        uint256 _strikePrice,
        uint256 _premium,
        uint256 _quantity,
        uint256 _daysToExpiry
    ) external nonReentrant {
        // ===== VALIDATION =====

        if (
            _strikePrice == 0 ||
            _premium == 0 ||
            _quantity == 0 ||
            _daysToExpiry == 0
        ) {
            revert InvalidAmount();
        }

        // Check: Can user write options?
        if (!creditScoring.canUserWriteOptions(msg.sender)) {
            revert CannotWriteOptions();
        }

        // ===== GET CREDIT INFORMATION =====

        uint256 collateralizationRatio = creditScoring
            .getCollateralizationRatio(msg.sender);

        // ===== CALCULATE COLLATERAL REQUIREMENTS =====

        // For puts, collateral is in stablecoin (strike price × quantity)
        uint256 fullCollateralNeeded = (_strikePrice * _quantity) / 1e18;
        uint256 userMustDeposit = (fullCollateralNeeded *
            collateralizationRatio) / 10000;
        uint256 creditBackedAmount = fullCollateralNeeded - userMustDeposit;

        // ===== TRANSFER COLLATERAL FROM USER =====

        bool collateralTransfer = stablecoin.transferFrom(
            msg.sender,
            address(this),
            userMustDeposit
        );
        require(collateralTransfer, "Collateral transfer failed");

        // ===== CALCULATE AND DEDUCT PLATFORM FEE =====

        uint256 platformFee = (_premium * platformFeePercentage) / 10000;
        uint256 premiumAfterFee = _premium - platformFee;
        platformFeeCollected += platformFee;

        // ===== CREATE OPTION RECORD =====

        uint256 optionId = nextOptionId++;

        options[optionId] = Option({
            optionId: optionId,
            writer: msg.sender,
            buyer: address(0),
            optionType: OptionType.PUT,
            underlyingToken: address(underlyingToken),
            strikePrice: _strikePrice,
            premium: _premium,
            quantity: _quantity,
            collateralLocked: userMustDeposit,
            creditBackedAmount: creditBackedAmount,
            createdAt: block.timestamp,
            expiryTime: block.timestamp + (_daysToExpiry * 1 days),
            status: OptionStatus.ACTIVE,
            isPaid: false,
            debtIdInCreditScoring: 0
        });

        // ===== UPDATE TRACKING =====

        userWrittenOptions[msg.sender].push(optionId);
        collateralLocked[msg.sender] += userMustDeposit;

        // ===== TRANSFER PREMIUM TO WRITER =====

        bool premiumTransfer = stablecoin.transfer(msg.sender, premiumAfterFee);
        require(premiumTransfer, "Premium transfer failed");

        // ===== EMIT EVENT =====

        emit OptionCreated(
            optionId,
            msg.sender,
            OptionType.PUT,
            _strikePrice,
            _premium,
            _quantity,
            block.timestamp + (_daysToExpiry * 1 days),
            userMustDeposit,
            creditBackedAmount
        );
    }

    function buyOption(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];

        // ===== VALIDATION =====

        if (option.optionId == 0) {
            revert OptionNotFound();
        }

        if (option.status != OptionStatus.ACTIVE) {
            revert OptionNotActive();
        }

        if (option.buyer != address(0)) {
            require(option.buyer == address(0), "Option already bought");
        }

        if (_optionId == 0) {
            revert InvalidAmount();
        }

        // ===== TRANSFER PREMIUM FROM BUYER =====

        bool premiumTransfer = stablecoin.transferFrom(
            msg.sender,
            address(this),
            option.premium
        );
        require(premiumTransfer, "Premium payment failed");

        // ===== UPDATE OPTION =====

        option.buyer = msg.sender;
        option.isPaid = true;

        // ===== UPDATE TRACKING =====

        userBoughtOptions[msg.sender].push(_optionId);

        // ===== EMIT EVENT =====

        emit OptionBought(_optionId, msg.sender, option.premium);
    }

    function exerciseCall(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];

        // ===== VALIDATION =====

        if (option.optionId == 0) {
            revert OptionNotFound();
        }

        if (option.optionType != OptionType.CALL) {
            require(option.optionType == OptionType.CALL, "Not a call option");
        }

        if (option.status != OptionStatus.ACTIVE) {
            revert OptionNotActive();
        }

        if (msg.sender != option.buyer) {
            revert NotOptionBuyer();
        }

        if (!option.isPaid) {
            revert PremiumNotPaid();
        }

        if (block.timestamp > option.expiryTime) {
            revert OptionNotActive();
        }

        // ===== THE CRITICAL LOGIC: CHECK COLLATERAL =====

        uint256 collateralAvailable = option.collateralLocked;
        uint256 collateralNeeded = option.quantity;

        // Do we have enough collateral?
        if (collateralAvailable < collateralNeeded) {
            // NOT ENOUGH! Need to borrow
            uint256 shortfall = collateralNeeded - collateralAvailable;

            // ===== BORROW FROM LENDING POOL =====

            // This creates a debt in CreditScoring
            lendingPool.borrowForOptions(option.writer, shortfall);

            // ===== CREATE DEBT RECORD =====

            // LendingPool already called creditScoring.createDebt()
            // So the debt is recorded automatically

            emit CreditBackedBorrowed(_optionId, shortfall);
        }

        // ===== RELEASE COLLATERAL TO BUYER =====

        // Transfer collateral to buyer
        bool collateralTransfer = underlyingToken.transfer(
            msg.sender,
            collateralNeeded
        );
        require(collateralTransfer, "Collateral transfer to buyer failed");

        // ===== UPDATE TRACKING =====

        collateralLocked[option.writer] -= option.collateralLocked;
        option.status = OptionStatus.EXERCISED;

        // ===== EMIT EVENT =====

        emit OptionExercised(_optionId, msg.sender);
    }

    /**
     * exercisePut: Buyer exercises a put option
     *
     * Put = Right to SELL at strike price
     *
     * Flow:
     * 1. Buyer sends underlying asset to contract
     * 2. Buyer receives strike price × quantity in stablecoin
     * 3. Writer's collateral sent to buyer
     */
    function exercisePut(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];

        // ===== VALIDATION =====

        if (option.optionId == 0) {
            revert OptionNotFound();
        }

        if (option.optionType != OptionType.PUT) {
            require(option.optionType == OptionType.PUT, "Not a put option");
        }

        if (option.status != OptionStatus.ACTIVE) {
            revert OptionNotActive();
        }

        if (msg.sender != option.buyer) {
            revert NotOptionBuyer();
        }

        if (!option.isPaid) {
            revert PremiumNotPaid();
        }

        if (block.timestamp > option.expiryTime) {
            revert OptionNotActive();
        }

        // ===== TRANSFER UNDERLYING ASSET FROM BUYER =====

        bool underlyingTransfer = underlyingToken.transferFrom(
            msg.sender,
            address(this),
            option.quantity
        );
        require(underlyingTransfer, "Asset transfer failed");

        // ===== CHECK COLLATERAL =====

        uint256 strikePriceTotal = (option.strikePrice * option.quantity) /
            1e18;
        uint256 collateralAvailable = option.collateralLocked;

        // Do we have enough collateral?
        if (collateralAvailable < strikePriceTotal) {
            // NOT ENOUGH! Need to borrow
            uint256 shortfall = strikePriceTotal - collateralAvailable;

            // Borrow from lending pool
            lendingPool.borrowForOptions(option.writer, shortfall);

            emit CreditBackedBorrowed(_optionId, shortfall);
        }

        // ===== TRANSFER STABLECOIN TO BUYER =====

        bool stablecoinTransfer = stablecoin.transfer(
            msg.sender,
            strikePriceTotal
        );
        require(stablecoinTransfer, "Stablecoin transfer failed");

        // ===== UPDATE TRACKING =====

        collateralLocked[option.writer] -= option.collateralLocked;
        option.status = OptionStatus.EXERCISED;

        // ===== EMIT EVENT =====

        emit OptionExercised(_optionId, msg.sender);
    }

    // ===== OPTION SETTLEMENT FUNCTIONS =====

    /**
     * settleExpiredOption: Called when option expires unexercised
     *
     * If option expires and nobody exercises:
     * - Return collateral to writer
     * - Update credit score: +25 bonus
     * - Option marked as EXPIRED
     *
     * @param _optionId The expired option
     */
    function settleExpiredOption(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];

        // ===== VALIDATION =====

        if (option.optionId == 0) {
            revert OptionNotFound();
        }

        if (option.status != OptionStatus.ACTIVE) {
            revert OptionNotActive();
        }

        if (block.timestamp <= option.expiryTime) {
            require(
                block.timestamp > option.expiryTime,
                "Option not expired yet"
            );
        }

        // ===== RETURN COLLATERAL TO WRITER =====

        address writer = option.writer;
        uint256 collateralToReturn = option.collateralLocked;

        if (option.optionType == OptionType.CALL) {
            // Return underlying token
            bool transfer = underlyingToken.transfer(
                writer,
                collateralToReturn
            );
            require(transfer, "Collateral return failed");
        } else {
            // Return stablecoin
            bool transfer = stablecoin.transfer(writer, collateralToReturn);
            require(transfer, "Collateral return failed");
        }

        // ===== UPDATE TRACKING =====

        collateralLocked[writer] -= collateralToReturn;
        option.status = OptionStatus.EXPIRED;

        // ===== UPDATE CREDIT SCORE =====

        // Call CreditScoring to record successful option
        creditScoring.recordSuccessfulOption(writer);

        // ===== EMIT EVENT =====

        emit OptionExpired(_optionId, writer);
    }

    /**
     * cancelOption: Writer cancels their option before it's bought
     *
     * Only works if:
     * - Option is ACTIVE
     * - Nobody has bought it yet (buyer == address(0))
     *
     * @param _optionId Option to cancel
     */
    function cancelOption(uint256 _optionId) external nonReentrant {
        Option storage option = options[_optionId];

        // ===== VALIDATION =====

        if (option.optionId == 0) {
            revert OptionNotFound();
        }

        if (msg.sender != option.writer) {
            revert NotOptionWriter();
        }

        if (option.status != OptionStatus.ACTIVE) {
            revert OptionNotActive();
        }

        if (option.buyer != address(0)) {
            require(option.buyer == address(0), "Already bought");
        }

        // ===== RETURN COLLATERAL =====

        address writer = option.writer;
        uint256 collateralToReturn = option.collateralLocked;

        if (option.optionType == OptionType.CALL) {
            bool transfer = underlyingToken.transfer(
                writer,
                collateralToReturn
            );
            require(transfer, "Collateral return failed");
        } else {
            bool transfer = stablecoin.transfer(writer, collateralToReturn);
            require(transfer, "Collateral return failed");
        }

        // ===== RETURN PREMIUM =====

        // Premium was already sent to writer when created
        // But if option is cancelled, buyer might get money back
        // (This logic depends on your protocol design)

        // ===== UPDATE TRACKING =====

        collateralLocked[writer] -= collateralToReturn;
        option.status = OptionStatus.CANCELLED;

        // ===== EMIT EVENT =====

        emit OptionCancelled(_optionId, writer);
    }

    // ===== VIEW FUNCTIONS =====

    /**
     * getOption: Get option details
     */
    function getOption(
        uint256 _optionId
    ) external view returns (Option memory) {
        return options[_optionId];
    }

    /**
     * getUserWrittenOptions: Get all options written by user
     */
    function getUserWrittenOptions(
        address _user
    ) external view returns (uint256[] memory) {
        return userWrittenOptions[_user];
    }

    /**
     * getUserBoughtOptions: Get all options bought by user
     */
    function getUserBoughtOptions(
        address _user
    ) external view returns (uint256[] memory) {
        return userBoughtOptions[_user];
    }

    /**
     * getUserWrittenOptionsCount: Count of options written
     */
    function getUserWrittenOptionsCount(
        address _user
    ) external view returns (uint256) {
        return userWrittenOptions[_user].length;
    }

    /**
     * getUserBoughtOptionsCount: Count of options bought
     */
    function getUserBoughtOptionsCount(
        address _user
    ) external view returns (uint256) {
        return userBoughtOptions[_user].length;
    }

    /**
     * getOptionStatus: Get current status of option
     */
    function getOptionStatus(
        uint256 _optionId
    ) external view returns (OptionStatus) {
        return options[_optionId].status;
    }

    /**
     * getCollateralLocked: How much collateral is locked for a user
     */
    function getCollateralLocked(
        address _user
    ) external view returns (uint256) {
        return collateralLocked[_user];
    }
}
