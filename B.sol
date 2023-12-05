// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Utility Token for BorB Finance
/// @author Borb Team
/// @notice for utility usage
contract B is ERC20, Ownable {
    constructor(address receiver) ERC20("BorB", "B") {
        _mint(receiver, 1_000_000 * 10 ** decimals());
    }

    ///@notice override decimals to match USDT and USDC
    function decimals() public view override returns (uint8) {
        return 6;
    }
}
