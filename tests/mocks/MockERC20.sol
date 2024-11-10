// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(address recipient, uint256 amount) ERC20("Mock Token", "MOCK") {
        _mint(recipient, amount);
    }
}
