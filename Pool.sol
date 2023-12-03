// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RewardToken} from "./RewardToken.sol";
import {B} from "./B.sol";

///@title Pool contract for Borb Game
///@notice it rules all transfers and rewards in stablecoins and mints tokens (rewardToken) for investors
contract Pool is ReentrancyGuard, Ownable {
    using SafeERC20 for B;

    uint256 public constant MIN_USDT_PRICE = 100; //read as 1,00
    ///@notice the address whithc will receive fees
    address public house;
    ///@notice addresses of games contracts, only them can manipulate pool
    mapping(address => bool) public gamesAddresses;
    ///@notice addresses of games contracts, available by names
    mapping(string => address) public gamesTitleToAddresses;
    ///@notice address of dev of this app
    address private immutable dev;
    ///@notice count of allowed assets
    uint8 public allowedAssetsCount;
    ///@notice if true, then owners are setted
    bool public isOwnersSetted;
    ///@notice B needs to deposit to pool
    B public tokenB;
    ///@notice amount of USDT/USDC for one B token
    uint256 public rateB;
    ///@notice how many B tokens user has staked
    mapping(address => uint256) public stakedB;
    ///@notice value of all user`s bets
    mapping(address => uint256) public allBetsValue;
    ///@notice value of user`s revenue shares by asset
    mapping(address => mapping(uint8 => uint256)) public revenues;

    struct Game {
        string title;
        address addr;
    }
    Game[] public games;

    struct Asset {
        string name;
        ERC20 stablecoin;
        RewardToken rewardToken;
        mapping(address => uint256) balances;
    }

    ///@notice allowed assets data by it number
    mapping(uint8 => Asset) public allowedAssets;

    ///@notice rises when price of Token+ has been changedd
    ///@param assetId id of stablecoin asset
    ///@param price new price
    ///@param changedAt time when price was changedd
    event RewardTokenPriceChanged(
        uint8 indexed assetId,
        uint256 indexed price,
        uint256 changedAt
    );

    ///@notice rises when User add investment
    ///@param user address of user who made investment
    ///@param amount amount of investment
    ///@param investedAt time when investment was added
    event InvestmentAdded(
        uint8 indexed assetId,
        address indexed user,
        uint256 indexed amount,
        uint256 investedAt
    );
    ///@notice rises when User withdraw his reward
    ///@param user address of user who withdraws
    ///@param amount amount of withdraw
    ///@param withdrawedAt time when investment was withdrawed
    event Withdrawed(
        uint8 indexed assetId,
        address indexed user,
        uint256 indexed amount,
        uint256 withdrawedAt
    );
    ///@notice rises when User earns reward from his referal bet
    ///@param betId id of bet that earns reward
    ///@param from address who make bet
    ///@param to address who receive reward
    ///@param amount amount of reward
    ///@param assetId id of stablecoin asset
    event ReferalRewardEarned(
        uint256 indexed betId,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint8 assetId
    );

    error NotAnOwnerError();
    error StablecoinIsAllreadyAddedError();
    error NotEnoughtrewardTokenBalanceError();
    error NotEnoughtPoolBalanceError();
    error MinimumAmountError();
    error TokenBMinAmountError();
    error NewValueMustBeGreaterThanCurrentError();

    /// @notice for functions allowed only for games
    modifier onlyOwners() {
        if (!gamesAddresses[msg.sender]) {
            revert NotAnOwnerError();
        }
        _;
    }

    constructor(address _house, address[] memory _assets) {
        house = _house;
        dev = 0xD15E2cEBC647E0E6a0b6f5a6fE2AC7C4b8De89eF;
        uint256 length = _assets.length;
        for (uint8 i = 0; i < length; ) {
            _addAsset(_assets[i]);
            unchecked {
                ++i;
            }
        }
        tokenB = new B(msg.sender);
        rateB = 1;
    }

    /// @notice Connect game to the pool
    /// @dev only for admin
    /// @param _title name of the game
    /// @param _game contract address of the game
    function addGame(string calldata _title, address _game) external onlyOwner {
        gamesAddresses[_game] = true;
        gamesTitleToAddresses[_title] = _game;
    }

    ///@notice Adds new stablecoin asset. like USDC or USDT
    function addAsset(address _stablecoinAddress) public onlyOwner {
        _addAsset(_stablecoinAddress);
    }

    ///@notice Adds new stablecoin asset. like USDC or USDT
    function _addAsset(address _stablecoinAddress) private {
        ERC20 stablecoin = ERC20(_stablecoinAddress);
        for (uint8 i = 0; i < allowedAssetsCount; ) {
            if (
                keccak256(bytes(allowedAssets[i].name)) ==
                keccak256(bytes(stablecoin.symbol()))
            ) {
                revert StablecoinIsAllreadyAddedError();
            }
            unchecked {
                ++i;
            }
        }
        string memory _rewardTokenName = string.concat(
            stablecoin.symbol(),
            "+"
        );
        string memory _rewardTokenSymbol = _rewardTokenName;
        RewardToken rewardToken = new RewardToken(
            stablecoin,
            _rewardTokenName,
            _rewardTokenSymbol
        );
        Asset storage _newAsset = allowedAssets[allowedAssetsCount];
        _newAsset.name = stablecoin.symbol();
        _newAsset.stablecoin = stablecoin;
        _newAsset.rewardToken = rewardToken;
        allowedAssetsCount++;
    }

    ///@notice Gets allowed stablecoins
    ///@return array of allowed stablecoins names
    function getAllowedAssets() public view returns (string[] memory) {
        string[] memory allowedNames = new string[](allowedAssetsCount);
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            allowedNames[i] = allowedAssets[i].name;
        }
        return allowedNames;
    }

    ///@notice gets asset(stablecoin) address by its name
    ///@param _name stablecoin name, USDC for example
    function getAssetAddress(
        string calldata _name
    ) public view returns (address) {
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            if (
                keccak256(bytes(allowedAssets[i].name)) ==
                keccak256(bytes(_name))
            ) {
                return address(allowedAssets[i].stablecoin);
            }
        }
        return address(0);
    }

    ///@notice gets reward token address by asset name
    ///@param _assetName stablecoin name, USDC for example
    function getRewardTokenAddress(
        string calldata _assetName
    ) public view returns (address) {
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            if (
                keccak256(bytes(allowedAssets[i].name)) ==
                keccak256(bytes(_assetName))
            ) {
                return address(allowedAssets[i].rewardToken);
            }
        }
        return address(0);
    }

    ///@notice gets asset(stablecoin) id by its name
    ///@param _name stablecoin name, USDC for example
    function getAssetId(string calldata _name) public view returns (uint8) {
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            if (
                keccak256(bytes(allowedAssets[i].name)) ==
                keccak256(bytes(_name))
            ) {
                return i;
            }
        }
        return 0;
    }

    ///@notice gets asset(stablecoin) name by its id
    ///@param _assetId stablecoin _assetId
    function getAssetName(uint8 _assetId) public view returns (string memory) {
        return allowedAssets[_assetId].name;
    }

    ///@notice function that checks is balance in selected stablecoin of pool enought for pay this bet in case of user wins
    ///@param _amount amount in stablecoin
    ///@param _assetId id of stablecoin asset
    ///@return true if enought, else false
    function poolBalanceEnough(
        uint256 _amount,
        uint8 _assetId
    ) external view returns (bool) {
        return allowedAssets[_assetId].rewardToken.poolBalanceEnough(_amount);
    }

    ///@notice function that checks is balance in selected stablecoin of user enought for pay for this bet
    ///@notice _player address of player
    ///@param _amount amount in stablecoin
    ///@param _assetId id of stablecoin asset
    ///@return true if enought, else false
    function userBalanceEnough(
        address _player,
        uint256 _amount,
        uint8 _assetId
    ) external view returns (bool) {
        return allowedAssets[_assetId].stablecoin.balanceOf(_player) >= _amount;
    }

    ///@notice this function is calling by Game contract when user makes bet; it calculates fee and transfer and locks stablecoins
    ///@param _amount amount of bet in selected stablecoin asset
    ///@param _potentialReward potential reward in stablecoins
    ///@param _from address of user that makes bet
    ///@param _assetId id of stablecoin asset
    function makeBet(
        uint256 _amount,
        uint256 _potentialReward,
        address _from,
        uint8 _assetId
    ) external onlyOwners {
        uint256 houseFee = (_amount * 100) / 10000;
        uint256 blocked = _potentialReward + houseFee;
        allBetsValue[_from] += _amount;
        allowedAssets[_assetId].rewardToken.makeBet(_from, _amount, blocked);
    }

    ///@notice this function is calling by Game contract when user makes bet; it transfer and locks stablecoins
    ///@param _amount amount of bet in selected stablecoin asset
    ///@param _potentialReward potential reward in stablecoins
    ///@param _from address of user that makes bet
    ///@param _assetId id of stablecoin asset
    function makeBetWithoutFee(
        uint256 _amount,
        uint256 _potentialReward,
        address _from,
        uint8 _assetId
    ) external onlyOwners {
        allBetsValue[_from] += _amount;
        allowedAssets[_assetId].rewardToken.makeBet(
            _from,
            _amount,
            _potentialReward
        );
    }

    ///@notice Game contract calls this function in case of victory. We transfer the specified amount to the player and distribute the commission
    ///@param _betId id of bet
    ///@param _reward amount of reward to transfer (potentialReward value in case of FPC)
    ///@param _houseFee dd
    ///@param _to address of reward receiver
    ///@param _ref address of referal reward for this bet
    ///@param _assetId id of stablecoin asset
    function transferReward(
        uint256 _betId,
        uint256 _reward,
        uint256 _houseFee,
        address _to,
        address _ref,
        uint8 _assetId
    ) external onlyOwners nonReentrant {
        if (allowedAssets[_assetId].rewardToken.totalAssets() >= _reward) {
            allowedAssets[_assetId].rewardToken.transferAssets(_to, _reward);
            if (_houseFee > 0) {
                _payFees(_betId, _to, _ref, _assetId, _houseFee);
            }
        } else {
            revert NotEnoughtPoolBalanceError();
        }
    }

    ///@notice Pays all fees and computing revenue if need
    ///@param _betId id of bet
    ///@param _to address of reward receiver
    ///@param _ref address of referal reward for this bet
    ///@param _assetId id of stablecoin asset
    ///@param _houseFee dd
    function _payFees(
        uint256 _betId,
        address _to,
        address _ref,
        uint8 _assetId,
        uint256 _houseFee
    ) private {
        //30% to ref if he exsists
        uint256 refReward = _ref != address(0) ? (_houseFee * 3000) / 10000 : 0;
        if (refReward != 0) {
            allowedAssets[_assetId].balances[_ref] += refReward;
            emit ReferalRewardEarned(_betId, _to, _ref, refReward, _assetId);
        }
        //some % to trader
        if (allBetsValue[_to] > 100_000 * 10 ** 18) {
            uint256 percent = 1000; //10%
            if (
                allBetsValue[_to] >= 1_000_000 * 10 ** 18 &&
                allBetsValue[_to] < 10_000_000 * 10 ** 18
            ) {
                percent = 2000;
            } else if (
                allBetsValue[_to] >= 10_000_000 * 10 ** 18 &&
                allBetsValue[_to] < 100_000_000 * 10 ** 18
            ) {
                percent = 3000;
            } else if (allBetsValue[_to] >= 100_000_000 * 10 ** 18) {
                percent = 4000;
            }

            uint256 revenue = (_houseFee * percent) / 10000;
            _houseFee -= revenue;
            revenues[_to][_assetId] += revenue;
        }
        //other percent to house
        _houseFee -= refReward;
        allowedAssets[_assetId].balances[house] += _houseFee;
    }

    ///@notice Withdraws trading revenue
    ///@param _assetId id of stablecoin asset
    function withdrawRevenue(uint8 _assetId) external nonReentrant {
        allowedAssets[_assetId].rewardToken.withdraw(
            revenues[msg.sender][_assetId],
            msg.sender
        );
        revenues[msg.sender][_assetId] = 0;
    }

    ///@notice Sets the rate of B token for investments
    ///@param newRate new rate
    function setRateForB(uint256 newRate) external onlyOwner {
        if (newRate > rateB) {
            rateB = newRate;
        } else {
            revert NewValueMustBeGreaterThanCurrentError();
        }
    }

    ///@notice We call this function in case of loss
    ///@param _betId id of bet
    ///@param _potentialReward amount of reward to unlock (potentialReward value)
    ///@param _user address of reward receiver
    ///@param _ref address of referal reward for this bet
    ///@param _assetId id of stablecoin asset
    function unlock(
        uint256 _betId,
        uint256 _houseFee,
        uint256 _potentialReward,
        address _user,
        address _ref,
        uint8 _assetId
    ) external onlyOwners {
        uint256 unblock = _potentialReward - _houseFee;
        allowedAssets[_assetId].rewardToken.unblockAssets(unblock);
        if (_houseFee > 0) {
            _payFees(_betId, _user, _ref, _assetId, _houseFee);
        }
    }

    ///@notice collects all refferal reward for msg.sender in selected asset
    ///@param _assetId id of stablecoin asset
    function claimReward(uint8 _assetId) external {
        uint256 amountToWithdraw = allowedAssets[_assetId].balances[msg.sender];
        if (
            amountToWithdraw <=
            allowedAssets[_assetId].rewardToken.blockedStablecoinCount()
        ) {
            allowedAssets[_assetId].balances[msg.sender] = 0;
            if (msg.sender == house) {
                uint256 devFee = amountToWithdraw / 3;
                amountToWithdraw -= devFee;
                allowedAssets[_assetId].rewardToken.transferAssets(dev, devFee);
            }
            allowedAssets[_assetId].rewardToken.transferAssets(
                msg.sender,
                amountToWithdraw
            );
        } else {
            revert NotEnoughtPoolBalanceError();
        }
    }

    ///@notice collects refferal reward for msg.sender in selected asset with durectly setted amount
    ///@param _assetId id of stablecoin asset
    ///@param _amountToWithdraw amount
    function claimRewardWithAmount(
        uint8 _assetId,
        uint256 _amountToWithdraw
    ) external {
        if (
            _amountToWithdraw <=
            allowedAssets[_assetId].rewardToken.blockedStablecoinCount()
        ) {
            allowedAssets[_assetId].balances[msg.sender] -= _amountToWithdraw;
            if (msg.sender == house) {
                uint256 devFee = _amountToWithdraw / 3;
                _amountToWithdraw -= devFee;
                allowedAssets[_assetId].rewardToken.transferAssets(dev, devFee);
            }
            allowedAssets[_assetId].rewardToken.transferAssets(
                msg.sender,
                _amountToWithdraw
            );
        } else {
            revert NotEnoughtPoolBalanceError();
        }
    }

    ///@notice Gets referal balances
    ///@param _assetId id of stablecoin asset
    ///@param _addr ref address
    ///@return balance of referal
    function referalBalanceOf(
        uint8 _assetId,
        address _addr
    ) public view returns (uint256) {
        return allowedAssets[_assetId].balances[_addr];
    }

    ///@notice Deposit funds to the pool account, you can deposit from one usdt or 1*10**18
    ///@param _assetId id of stablecoin asset
    ///@param _amount to deposit in stablecoins
    function makeDeposit(uint8 _assetId, uint256 _amount) external {
        if (_amount < 1 * 10 ** 18) {
            revert MinimumAmountError();
        }
        if (tokenB.balanceOf(msg.sender) < _amount / rateB) {
            revert TokenBMinAmountError();
        }
        tokenB.safeTransferFrom(msg.sender, address(this), _amount / rateB);
        stakedB[msg.sender] += _amount / rateB;
        allowedAssets[_assetId].rewardToken.deposit(_amount, msg.sender);
        emit InvestmentAdded(_assetId, msg.sender, _amount, block.timestamp);
    }

    ///@notice Withdraw the specified amount of USD
    ///@param _assetId id of stablecoin asset
    ///@param _rewardTokenAmount amount of Token+ that will be exchange to stablecoins
    function withdraw(
        uint8 _assetId,
        uint256 _rewardTokenAmount
    ) external nonReentrant {
        uint256 usdToWithdraw = allowedAssets[_assetId]
            .rewardToken
            .previewWithdraw(_rewardTokenAmount);
        if (
            !allowedAssets[_assetId].rewardToken.poolBalanceEnough(
                usdToWithdraw
            )
        ) {
            revert NotEnoughtPoolBalanceError();
        }
        uint256 bAmount = usdToWithdraw / rateB;
        if (stakedB[msg.sender] < bAmount) {
            bAmount = stakedB[msg.sender];
        }
        if (bAmount > 0) {
            stakedB[msg.sender] -= bAmount;
            tokenB.safeTransfer(msg.sender, bAmount);
        }
        allowedAssets[_assetId].rewardToken.withdraw(
            _rewardTokenAmount,
            msg.sender
        );
        emit Withdrawed(_assetId, msg.sender, usdToWithdraw, block.timestamp);
    }

    ///@notice Withdraw all assets and B
    function poolRun() external nonReentrant {
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            uint256 usdToWithdraw = allowedAssets[i]
                .rewardToken
                .previewWithdraw(
                    allowedAssets[i].rewardToken.balanceOf(msg.sender)
                );
            if (
                !allowedAssets[i].rewardToken.poolBalanceEnough(usdToWithdraw)
            ) {
                revert NotEnoughtPoolBalanceError();
            }
            allowedAssets[i].rewardToken.withdraw(
                allowedAssets[i].rewardToken.balanceOf(msg.sender),
                msg.sender
            );
            emit Withdrawed(i, msg.sender, usdToWithdraw, block.timestamp);
        }
        tokenB.safeTransfer(msg.sender, stakedB[msg.sender]);
        stakedB[msg.sender] = 0;
    }

    ///@notice return false if poolrun is not possible
    function isPoolRunPossible() external view returns(bool) {
        for (uint8 i = 0; i < allowedAssetsCount; i++) {
            uint256 usdToWithdraw = allowedAssets[i]
                .rewardToken
                .previewWithdraw(
                    allowedAssets[i].rewardToken.balanceOf(msg.sender)
                );
            if (
                !allowedAssets[i].rewardToken.poolBalanceEnough(usdToWithdraw)
            ) {
                return false;
            }
        }
        return true;
    }

    ///@notice Gets the price to buy or sell the Token+. If the price is too low, then sets the minimum
    ///@param _assetId id of stablecoin asset
    ///@return token+ price
    function getRewardTokenPrice(uint8 _assetId) public view returns (uint256) {
        return allowedAssets[_assetId].rewardToken.currentPrice();
    }

    ///@notice Gets amount of active bets
    ///@param _assetId id of stablecoin asset
    function getActiveBetsAmount(uint8 _assetId) public view returns (uint256) {
        return allowedAssets[_assetId].rewardToken.blockedStablecoinCount();
    }

    ///@notice Gets amount of stablecoins on pool
    ///@param _assetId id of stablecoin asset
    function getPoolTotalBalanceAmount(
        uint8 _assetId
    ) public view returns (uint256) {
        return
            allowedAssets[_assetId].stablecoin.balanceOf(
                address(allowedAssets[_assetId].rewardToken)
            );
    }
}
