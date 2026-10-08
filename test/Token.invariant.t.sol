// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Token} from "../src/Token.sol";

/// @dev Generates successful transactions over a closed set of holders, including self-transfers.
contract TokenHandler is Test {
    Token internal immutable token;
    address[4] internal actors;

    constructor(Token token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint8 spenderSeed, uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % 4];
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 allowanceBefore = token.allowance(from, spender);
        uint256 limit = token.balanceOf(from);
        if (allowanceBefore < limit) limit = allowanceBefore;
        amount = bound(amount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        uint256 expected = allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount;
        assertEq(token.allowance(from, spender), expected);
    }
}

contract TokenInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    Token internal token;
    address[4] internal actors;

    function setUp() public {
        token = new Token();
        actors = [makeAddr("holder-0"), makeAddr("holder-1"), makeAddr("holder-2"), makeAddr("holder-3")];
        assertTrue(token.transfer(actors[0], SUPPLY));
        TokenHandler handler = new TokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_allTokensRemainAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
