// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {Pool} from "./Pool.sol";

//import "../node_modules/hardhat/console.sol";

///@title Borb Game contract
///@notice A contract that allows you to bet stablecoins on an increase or decrease in the price of a selected currency and make a profit.
contract BorbCFD is AutomationCompatibleInterface {
    uint256[] public notClaimed;
    uint256 public constant REWARD_PERCENT_MIN = 20;
    uint256 public constant REWARD_PERCENT_MAX = 100;

    enum BetType {
        Up,
        Down
    }

    enum Currency {
        BTC,
        ETH,
        SOL,
        BNB,
        ADA,
        DOT,
        MATIC,
        DOGE,
        ATOM,
        AVAX
    }

    struct Bet {
        int256 lockPrice;
        uint256 lockTimestamp;
        uint256 amount;
        address user;
        uint80 roundId; //the round in which the price was fixed
        uint32 timeframe;
        uint8 assetId;
        uint8 leverage;
        BetType betType;
        Currency currency;
        bool claimed;
    }

    ///@notice oracle price contracts
    mapping(Currency => AggregatorV3Interface) public priceFeeds;

    ///@notice The pool manages the funds.
    Pool public pool;

    ///@notice The owner of this contract
    /// @dev Only the owner can call  functions addAsset, setOracle, setCalculatorFee, grabCalculatorFee
    /// @return owner the address of this smart contract's deployer
    address public owner;
    ///@notice Backend address that closes bets and changes the current win percentage
    address public calculator;
    ///@notice Fee, that need for backend
    uint256 public calculatorFee;

    ///@notice Max bet amount
    uint256 public maxBetAmount;
    ///@notice Min bet amount
    uint256 public minBetAmount;
    ///@notice array of all bets
    Bet[] public bets;
    ///@notice k-user v-his referer
    mapping(address => address) public referals;
    ///@notice k-user v-isKnown
    mapping(address => bool) public users;

    ///@notice reward percents is different for different currencies, timeframes and assets
    mapping(Currency => mapping(uint32 => uint256)) public rewardPercent;

    ///@notice assetId from pool, this currency is for bets
    uint8 public assetId;

    ///@notice allowed currencies
    Currency[10] public currencies = [
        Currency.BTC,
        Currency.ETH,
        Currency.SOL,
        Currency.BNB,
        Currency.ADA,
        Currency.DOT,
        Currency.MATIC,
        Currency.DOGE,
        Currency.ATOM,
        Currency.AVAX
    ];

    ///@notice if game is stopped, then nobody can make bets
    bool public isGameStopped;

    ///@notice rises when user makes first bet
    ///@param user address of user
    ///@param ref his referal
    event NewUserAdded(address indexed user, address ref);

    ///@notice rises when user adding bet
    ///@param user address of the user who makes bet
    ///@param betId id of bet
    ///@param betType 0 if bet Up or 1 if bet Down
    ///@param currency number of currency for bet
    ///@param timeframe timeframe in seconds
    ///@param amount amount of bet
    ///@param leverage leverage value
    ///@param lockPrice price of currency when user makes bet
    ///@param lockedAt time when bet was made
    event NewBetAdded(
        address indexed user,
        uint256 indexed betId,
        BetType betType,
        Currency currency,
        uint32 timeframe,
        uint256 amount,
        uint8 leverage,
        int256 lockPrice,
        uint256 lockedAt
    );

    ///@notice rises when bet is claimed
    ///@param user address of user who made bet
    ///@param timeframe bet timeframe in seconds
    ///@param betId id of bet
    ///@param closePrice close price at bet closed time
    ///@param tradeResult result of trade (win or loss, determines by open and close price)
    event BetClaimed(
        address indexed user,
        uint256 indexed timeframe,
        uint256 indexed betId,
        int256 closePrice,
        uint256 tradeResult,
        bool isWin
    );

    error NotAnOwnerError();
    error NotACalculatorError();
    error TimeframeNotExsistError();
    error NotEnoughtPoolBalanceError();
    error NotEnoughtUserBalanceError();
    error BetRangeError(uint256 min, uint256 max);
    error MinBetValueError();
    error BetAllreadyClaimedError();
    error ClaimBeforeTimeError(uint256 betTime, uint256 currentTime);
    error IncorrectKnownRoundIdError();
    error ClosePriceNotFoundError();
    error RewardPercentRangeError(uint256 min, uint256 max);
    error IncorrectRoundIdError();
    error IncorrectPriceFeedNumber();
    error IncorrectFeeValue();
    error IncorrectLeverageValue();
    error BettingIsNotAllowedError();

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotAnOwnerError();
        }
        _;
    }

    modifier onlyCalculator() {
        if (msg.sender != calculator) {
            revert NotACalculatorError();
        }
        _;
    }

    modifier timeframeExsists(uint32 _timeframe) {
        if (
            _timeframe != 5 minutes &&
            _timeframe != 15 minutes &&
            _timeframe != 1 hours &&
            _timeframe != 4 hours &&
            _timeframe != 24 hours
        ) {
            revert TimeframeNotExsistError();
        }
        _;
    }

    /// @notice Deploys the smart contract and sets price oracles
    /// @dev Assigns `msg.sender` to the owner state variable. Assigns calculator address and address of the pool
    constructor(
        address[10] memory _priceFeeds,
        address _calculator,
        address _pool,
        string memory _assetName
    ) {
        owner = msg.sender;

        for (uint256 currencyId = 0; currencyId < 10; currencyId++) {
            priceFeeds[currencies[currencyId]] = AggregatorV3Interface(
                _priceFeeds[currencyId]
            );
        }

        calculator = _calculator;
        pool = Pool(_pool);
        maxBetAmount = 100 * 10 ** 18;
        minBetAmount = 10_000;
        for (uint256 currencyId = 0; currencyId < 10; currencyId++) {
            _initRewardPercent(currencies[currencyId]);
        }
        assetId = pool.getAssetId(_assetName);
    }

    function _initRewardPercent(Currency _currency) private {
        uint32[] memory timeframes = getAllowedTimeframes();
        uint256 length = timeframes.length;
        for (uint8 i = 0; i < length; ) {
            rewardPercent[_currency][timeframes[i]] = REWARD_PERCENT_MAX;
            unchecked {
                ++i;
            }
        }
    }

    ///@notice fee for win bet
    uint256 public winFeePercent = 200;
    ///@notice fee for loose bet
    uint256 public looseFeePercent = 100;

    ///@notice sets fee for win bet
    ///@param percent percent of fee 1..100
    function setWinFeePercent(uint256 percent) public onlyOwner {
        winFeePercent = percent * 100;
    }

    ///@notice sets fee for loose bet
    ///@param percent percent of fee 1..100
    function setLooseFeePercent(uint256 percent) public onlyOwner {
        looseFeePercent = percent * 100;
    }

    ///@notice Make bet
    ///@param _amount amount of bet in selected asset
    ///@param _ref address of users referer, it sets one time
    ///@param _timeframe bet timeframe in seconds
    ///@param _betType type of bet, Up(0) or Down(1)
    ///@param _currency the currency on which a bet is made to rise or fall.
    ///@param _leverage leverage
    function makeBet(
        uint256 _amount,
        address _ref,
        uint32 _timeframe,
        BetType _betType,
        Currency _currency,
        uint8 _leverage
    ) external payable timeframeExsists(_timeframe) {
        if (isGameStopped) {
            revert BettingIsNotAllowedError();
        }
        if (msg.value != calculatorFee) {
            revert IncorrectFeeValue();
        }
        if (_leverage < 2 || _leverage > 100) {
            revert IncorrectLeverageValue();
        }
        if (_amount == 0) return;
        uint256 potentialReward = getPotentialReward(
            _currency,
            _timeframe,
            _amount
        );
        if (!pool.poolBalanceEnough(potentialReward, assetId)) {
            revert NotEnoughtPoolBalanceError();
        }
        if (!pool.userBalanceEnough(msg.sender, _amount, assetId)) {
            revert NotEnoughtUserBalanceError();
        }
        if (_amount > maxBetAmount || _amount < minBetAmount) {
            revert BetRangeError(minBetAmount, maxBetAmount);
        }
        //if user is new
        if (users[msg.sender] == false) {
            if (msg.sender != _ref) {
                referals[msg.sender] = _ref;
            }
            users[msg.sender] = true;
            emit NewUserAdded(msg.sender, _ref);
        }

        (uint80 roundId, int256 price, , , ) = getPriceFeed(_currency)
            .latestRoundData();

        bets.push(
            Bet({
                lockPrice: price,
                lockTimestamp: block.timestamp,
                amount: _amount,
                user: msg.sender,
                roundId: roundId,
                timeframe: _timeframe,
                assetId: assetId,
                leverage: _leverage,
                betType: _betType,
                currency: _currency,
                claimed: false
            })
        );

        pool.makeBetWithoutFee(_amount, potentialReward, msg.sender, assetId);
        notClaimed.push(bets.length - 1);
        emit NewBetAdded(
            msg.sender,
            bets.length - 1,
            _betType,
            _currency,
            _timeframe,
            _amount,
            _leverage,
            price,
            block.timestamp
        );
    }

    ///@notice This function is called by either the user or the admin to claim the bet.
    ///@notice You (or backend) must call getCloseRoundId function, which does a free iteration and returns a roundId with the desired close price
    ///@notice before calling this function and pass _knownRoundId
    ///@param _betId id of bet to claim
    ///@param _knownRoundId roundId on oracle which has close price for this bet
    function claim(uint256 _betId, uint80 _knownRoundId) public {
        Bet memory currentBet = bets[_betId];
        if (currentBet.claimed) {
            revert BetAllreadyClaimedError();
        }
        (uint80 latestRoundId, , , , ) = getPriceFeed(currentBet.currency)
            .latestRoundData();
        if (_knownRoundId > latestRoundId) {
            revert IncorrectKnownRoundIdError();
        }
        if (block.timestamp < currentBet.lockTimestamp + currentBet.timeframe) {
            revert ClaimBeforeTimeError(
                currentBet.lockTimestamp + currentBet.timeframe,
                block.timestamp
            );
        }
        int256 closePrice = 0;
        //if we know the round id, we need to check the previous and specified
        closePrice = getClosePriceByRoundId(_betId, _knownRoundId);
        bets[_betId].claimed = true;
        address ref = referals[currentBet.user];
        uint256 potentialReward = getPotentialReward(
            bets[_betId].currency,
            bets[_betId].timeframe,
            bets[_betId].amount
        );
        uint256 realReward = getRealReward(
            bets[_betId].currency,
            bets[_betId].timeframe,
            bets[_betId].lockPrice,
            closePrice,
            bets[_betId].amount,
            bets[_betId].leverage
        );

        bool isWin = (currentBet.betType == BetType.Up &&
            currentBet.lockPrice < closePrice) ||
            (currentBet.betType == BetType.Down &&
                currentBet.lockPrice > closePrice);

        uint256 winFee = 0;
        uint256 looseFee = 0;

        if (isWin) {
            winFee =
                ((realReward - bets[_betId].amount) * winFeePercent) /
                10000;
            realReward -= winFee;
        } else {
            realReward =
                bets[_betId].amount -
                (realReward - bets[_betId].amount);
            looseFee =
                ((bets[_betId].amount - realReward) * looseFeePercent) /
                10000;
        }
        pool.transferReward(
            _betId,
            realReward - winFee,
            winFee,
            currentBet.user,
            ref,
            currentBet.assetId
        );

        pool.unlock(
            _betId,
            looseFee,
            potentialReward - realReward,
            currentBet.user,
            ref,
            currentBet.assetId
        );
        emit BetClaimed(
            currentBet.user,
            currentBet.timeframe,
            _betId,
            closePrice,
            realReward,
            isWin
        );
    }

    ///@notice allowing bets
    function toggleAllowBetting() external onlyOwner {
        isGameStopped = !isGameStopped;
    }

    ///@notice Call this function if you dont know roundID. Warning! it is not gas effecient
    function claimWithoutRoundId(uint256 _betId) public {
        uint80 roundId = getCloseRoundId(_betId);
        claim(_betId, roundId);
    }

    ///@notice sets price oracle
    ///@param _oracle price oracle address
    ///@param _currency currency which will take price from this oracle
    function setOracle(address _oracle, Currency _currency) external onlyOwner {
        if (_currency > Currency.AVAX) {
            revert IncorrectPriceFeedNumber();
        }
        priceFeeds[_currency] = AggregatorV3Interface(_oracle);
    }

    ///@notice sets calculator fee. it needs when backend claims bets or sets reward percent
    function setCalculatorFee(uint256 fee) external onlyOwner {
        calculatorFee = fee;
    }

    ///@notice transfer fee from this contract to calculator address
    function grabCalculatorFee() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent, ) = calculator.call{value: amount}("");
        require(sent, "Failed to send");
    }

    ///@notice this function is calling only by backend when it needs to change reward percent
    function updateRewardPercent(
        Currency _currency,
        uint32 _timeframe,
        uint256 _newPercent
    ) external onlyCalculator timeframeExsists(_timeframe) {
        if (
            _newPercent < REWARD_PERCENT_MIN || _newPercent > REWARD_PERCENT_MAX
        ) {
            revert RewardPercentRangeError(
                REWARD_PERCENT_MIN,
                REWARD_PERCENT_MAX
            );
        }
        rewardPercent[_currency][_timeframe] = _newPercent;
    }

    ///@notice Sets the max and min bet size
    function setMinAndMaxBetAmount(
        uint256 _newMin,
        uint256 _newMax
    ) external onlyOwner {
        if (_newMin < 100) {
            revert MinBetValueError();
        }
        maxBetAmount = _newMax;
        minBetAmount = _newMin;
    }

    ///@notice Called to find out the real winnings
    ///@param _currency bet currency which must go Up or Down
    ///@param _timeframe bet timeframe in seconds
    ///@param _openPrice open price
    ///@param _closePrice close price
    ///@param _amount amount in asset
    ///@param _leverage leverage
    ///@return reward real reward percent for this bet
    function getRealReward(
        Currency _currency,
        uint32 _timeframe,
        int256 _openPrice,
        int256 _closePrice,
        uint256 _amount,
        uint8 _leverage
    ) public view returns (uint256 reward) {
        int256 diffMod = _closePrice > _openPrice
            ? _closePrice - _openPrice
            : _openPrice - _closePrice;
        uint256 realPercent = (uint256((diffMod * 1_000_000) / _openPrice) *
            100 *
            _leverage);
        if (realPercent > rewardPercent[_currency][_timeframe] * 1_000_000) {
            realPercent = rewardPercent[_currency][_timeframe] * 1_000_000;
        }
        uint256 realReward = _amount + (_amount * realPercent) / 100_000_000;
        return realReward;
    }

    ///@notice Called to find out the possible winnings
    ///@param _amount amount in asset
    ///@return reward potential reward for this bet
    function getPotentialReward(
        Currency _currency,
        uint32 _timeframe,
        uint256 _amount
    ) public view returns (uint256 reward) {
        uint256 potentialReward = _amount +
            (_amount * 100 * rewardPercent[_currency][_timeframe]) /
            10000;
        return potentialReward;
    }

    ///@notice Gets allowed timeframes
    ///@return array of allowed timeframes in seconds
    function getAllowedTimeframes() public pure returns (uint32[] memory) {
        uint32[] memory timeframes = new uint32[](5);
        timeframes[0] = 5 minutes;
        timeframes[1] = 15 minutes;
        timeframes[2] = 1 hours;
        timeframes[3] = 4 hours;
        timeframes[4] = 24 hours;
        return timeframes;
    }

    ///@notice Gets name of using stablecoin
    ///@return name
    function getAsset() public view returns (string memory) {
        return pool.getAssetName(assetId);
    }

    ///@notice gets asset(stablecoin) address by its name
    ///@param _name stablecoin name, USDC for example
    function getAssetAddress(
        string calldata _name
    ) public view returns (address) {
        return pool.getAssetAddress(_name);
    }

    ///@notice Gets the oracle for the specified currency
    ///@param _currency currency number
    ///@return price oracle address for currency
    function getPriceFeed(
        Currency _currency
    ) public view returns (AggregatorV3Interface) {
        if (_currency > Currency.AVAX) {
            revert IncorrectPriceFeedNumber();
        }
        return priceFeeds[_currency];
    }

    ///@notice This function must be called to get the roundId for the specified rate for free
    ///@notice In it we find roundId from which we take the closing price
    ///@param _betId id of bet to close
    ///@return roundId from price oracle that contains close price for this bet
    function getCloseRoundId(uint256 _betId) public view returns (uint80) {
        AggregatorV3Interface priceFeed = getPriceFeed(bets[_betId].currency);
        (uint80 latestRoundId, , , , ) = priceFeed.latestRoundData();
        uint80 roundId = bets[_betId].roundId;
        uint256 priceTime = 0;
        uint256 closeTime = bets[_betId].lockTimestamp + bets[_betId].timeframe;
        do {
            if (latestRoundId < roundId) {
                revert ClosePriceNotFoundError();
            }
            roundId += 1;
            (, , priceTime, , ) = priceFeed.getRoundData(roundId);
        } while (priceTime < closeTime);
        return roundId;
    }

    ///@notice Finds the closing price by iterating from selected round id
    ///@param _betId id of bet
    ///@param _latestRoundId roundId to start iterating
    ///@return closingPrice
    function getClosePrice(
        uint256 _betId,
        uint256 _latestRoundId
    ) public view returns (int256) {
        uint80 roundId = bets[_betId].roundId;
        int256 closePrice = 0;
        uint256 priceTime = 0;
        uint256 closeTime = bets[_betId].lockTimestamp + bets[_betId].timeframe;
        do {
            if (_latestRoundId < roundId) {
                revert ClosePriceNotFoundError();
            }
            roundId += 1;
            (, closePrice, priceTime, , ) = getPriceFeed(bets[_betId].currency)
                .getRoundData(roundId);
        } while (priceTime < closeTime);
        return closePrice;
    }

    ///@notice Returns the closing price for a known bet id, timeframe and round id if all data is correct
    ///@param _betId id of bet
    ///@param _roundId roundId where closing price is
    ///@dev if you slip an incorrect round of id on it, it will turn back
    function getClosePriceByRoundId(
        uint256 _betId,
        uint80 _roundId
    ) public view returns (int256) {
        if (_roundId <= 1) {
            revert IncorrectRoundIdError();
        }
        uint256 closeTime = bets[_betId].lockTimestamp + bets[_betId].timeframe;
        AggregatorV3Interface priceFeed = getPriceFeed(bets[_betId].currency);
        (, , uint256 prevTime, , ) = priceFeed.getRoundData(_roundId - 1);
        (, int256 currentClosePrice, uint256 currentTime, , ) = priceFeed
            .getRoundData(_roundId);
        //if the time of the specified _roundId is greater than the closing time, and the time of the previous one is less, then the specified is the desired interval
        if (currentTime < closeTime || prevTime >= closeTime) {
            revert IncorrectRoundIdError();
        }

        return currentClosePrice;
    }

    ///@notice determines whether there is a closing price on the oracle
    ///@param _betId id of bet
    ///@return true if bet can be claimed
    function isNeedClaim(uint256 _betId) public view returns (bool) {
        AggregatorV3Interface priceFeed = getPriceFeed(bets[_betId].currency);
        (uint80 latestRoundId, , , , ) = priceFeed.latestRoundData();
        uint80 roundId = bets[_betId].roundId;
        uint256 priceTime = 0;
        uint256 closeTime = bets[_betId].lockTimestamp + bets[_betId].timeframe;
        do {
            if (latestRoundId < roundId) {
                return false;
            }
            roundId += 1;
            (, , priceTime, , ) = priceFeed.getRoundData(roundId);
        } while (priceTime < closeTime);
        return true && !bets[_betId].claimed;
    }

    function checkUpkeep(
        bytes calldata checkData
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = false;

        for (uint256 i = 0; i < notClaimed.length && !upkeepNeeded; i++) {
            if (isNeedClaim(notClaimed[i])) {
                upkeepNeeded = true;
                performData = abi.encode(i);
            }
        }

        return (upkeepNeeded, performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 notclaimedId = abi.decode(performData, (uint256));
        claimWithoutRoundId(notClaimed[notclaimedId]);
        if (notClaimed.length > 1) {
            notClaimed[notclaimedId] = notClaimed[notClaimed.length - 1];
        }
        notClaimed.pop();
    }
}
