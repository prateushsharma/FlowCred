// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockUSDC
/// @notice Local-test-only asset for FlowCred. Never deployed by the Sepolia deployment script.
contract MockUSDC is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e6;

    constructor(address initialOwner) ERC20("FlowCred Mock USDC", "mUSDC") Ownable(initialOwner) {
        _mint(initialOwner, INITIAL_SUPPLY);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Testnet convenience minting. Owner-only by design.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
