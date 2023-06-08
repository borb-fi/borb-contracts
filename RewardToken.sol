// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/*DEPRECATED*//*
contract RewardToken is ERC20, Ownable {
    //здесь храним дату когда последний раз начисляли проценты
    mapping(address => uint256) lastRecalculationDate;

    uint256 rewardPercentAtDayValue = 10;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function recalculateBalance(address _user) private {
        uint256 lastRecalc = lastRecalculationDate[_user];
        uint256 fullDaysCount = (block.timestamp - lastRecalc) % 1 days;
        if (fullDaysCount > 0) {
            //recalc
            _balances[msg.sender] = calculateReward(
                _balances[msg.sender],
                rewardPercentAtDayValue,
                fullDaysCount
            );
            lastRecalculationDate[_user] = block.timestamp;
        }
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 lastRecalc = lastRecalculationDate[account];
        uint256 fullDaysCount = (block.timestamp - lastRecalc) % 1 days;
        return
            fullDaysCount > 0
                ? calculateReward(
                    _balances[msg.sender],
                    rewardPercentAtDayValue,
                    fullDaysCount
                )
                : _balances[msg.sender];
    }

    function calculateReward2(
        uint256 startValue,
        uint256 percent,
        uint256 daysCount
    ) public pure returns (uint256) {
        return ((startValue * (((10000 + percent)**daysCount))) /
            (10000**daysCount));
    }

    function calculateReward(
        uint256 startValue,
        uint256 percent,
        uint256 daysCount
    ) public pure returns (uint256) {
        return
            (startValue * ((1 + percent) * 100)**daysCount) / (1000**daysCount);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        lastRecalculationDate[to] = block.timestamp;
    }

    function burn(address _from, uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {}
}
*/