// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Swarm brain (BRAIN)
/// @notice A fixed-supply ERC-20 with 18 decimals, minted entirely to its deployer.
contract Token is ERC20 {
    /// @notice The entire supply in minor units: one billion tokens with 18 decimals.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The immediate creator receives the supply, including when deployed by a factory.
    constructor() ERC20("Swarm brain", "BRAIN") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
