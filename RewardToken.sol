// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

///@title LP Token
contract RewardToken is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    uint256 private constant USDT_DECIMALS = 6;
    uint256 public constant PRICE_1_TO_1 = 1 * 10 ** USDT_DECIMALS;

    ///@notice base asset
    ERC20 public immutable asset;
    uint256 public blockedStablecoinCount;
    ///@notice price of asset, initialize start price 1 USDT
    uint256 public currentPrice = PRICE_1_TO_1;
    ///@notice total amount of assets in pool
    uint256 public totalAssets;

    ///@notice LP Tokens are soulbound, you can`t transfer them to anybody else
    error TokensCantBeTransferedError();

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        asset = _asset;
    }

    ///@notice function that checks is balance in selected stablecoin of pool enought for pay this bet in case of user wins
    ///@param _amount amount in stablecoin
    ///@return true if enought, else false
    function poolBalanceEnough(uint256 _amount) external view returns (bool) {
        return totalAssets >= _amount + blockedStablecoinCount;
    }

    ///@notice makes bet
    ///@param _player address of player who makes bet
    ///@param _amount amount of assets
    ///@param _blocked amount that will be blocked on pool when user makes bet
    function makeBet(
        address _player,
        uint256 _amount,
        uint256 _blocked
    ) external onlyOwner {
        totalAssets += _amount;
        blockedStablecoinCount += _blocked;
        asset.safeTransferFrom(_player, address(this), _amount);
    }

    ///@notice unlock assets and update price
    ///@param _amount amount of assets
    function unblockAssets(uint256 _amount) external onlyOwner {
        blockedStablecoinCount -= _amount;
        updatePrice();
    }

    ///@notice transfers assets, update price
    ///@param _to who will receive asset
    ///@param _amount amount of assets
    function transferAssets(address _to, uint256 _amount) external onlyOwner {
        totalAssets -= _amount;
        blockedStablecoinCount -= _amount;
        asset.safeTransfer(_to, _amount);
        updatePrice();
    }

    ///@notice updates price based on current asset quantity
    function updatePrice() internal {
        uint256 newPrice = totalSupply() == 0
            ? PRICE_1_TO_1
            : ((totalAssets - blockedStablecoinCount) * PRICE_1_TO_1) /
                totalSupply();
        if (newPrice > currentPrice) {
            currentPrice = newPrice;
        }
    }

    ///@notice make deposit of assets to pool
    ///@param assets number of assets that user wants to deposit
    ///@param sender address of user who make deposit
    function deposit(uint256 assets, address sender) public returns (uint256) {
        totalAssets += assets;
        asset.safeTransferFrom(sender, address(this), assets);
        uint256 shares = (assets * PRICE_1_TO_1) / currentPrice; // Calculation of the number of shares based on the current price
        _mint(sender, shares);
        updatePrice();
        return shares;
    }

    ///@notice withdraw assets from pool
    ///@param shares number of shares that user wants to withdraw
    ///@param sender address of user who make withdraw
    function withdraw(uint256 shares, address sender) public returns (uint256) {
        uint256 assets = (shares * currentPrice) / PRICE_1_TO_1; // Calculation of the number of assets based on the current price
        totalAssets -= assets;
        asset.safeTransfer(sender, assets);
        _burn(sender, shares);
        updatePrice();
        return assets;
    }

    ///@notice viewing the number of assets that will be withdrawn
    ///@param shares number of shares
    ///@return calculated value of assets
    function previewWithdraw(uint256 shares) public view returns (uint256) {
        return (shares * currentPrice) / PRICE_1_TO_1;
    }

    ///@notice viewing the number of shares that will be withdrawn
    ///@param assets number of assets
    ///@return calculated value of shares
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return (assets * PRICE_1_TO_1) / currentPrice;
    }

    ///@notice Hook that is called before any transfer of tokens.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(0) && to != address(0)) {
            revert TokensCantBeTransferedError();
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}
