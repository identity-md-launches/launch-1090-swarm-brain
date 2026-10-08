// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "../src/Token.sol";

/// @dev Drives successful and rejected calls over a closed set of holders, including aliases.
/// Ghost state starts from the specified supply and changes only from requested operations;
/// it is never resynchronized from the token's balance or allowance getters.
contract TokenHandler is Test {
    Token internal immutable token;
    address[4] internal actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Token token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 1e18;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        _approve(owner, spender, amount);
    }

    /// @dev Deliberately revisit revocation, infinite approval, and the largest finite approval.
    function approveBoundary(uint8 ownerSeed, uint8 spenderSeed, uint8 mode) external {
        uint256 amount = mode % 3 == 0 ? 0 : (mode % 3 == 1 ? type(uint256).max : type(uint256).max - 1);
        _approve(actors[ownerSeed % 4], actors[spenderSeed % 4], amount);
    }

    function transferFrom(uint8 spenderSeed, uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % 4];
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 allowanceBefore = expectedAllowance[from][spender];
        uint256 limit = expectedBalance[from];
        if (allowanceBefore < limit) limit = allowanceBefore;
        amount = bound(amount, 0, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        uint256 expected = allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount;
        expectedAllowance[from][spender] = expected;
        _recordTransfer(from, to, amount);
        assertEq(token.allowance(from, spender), expected);
    }

    function transferAboveBalance(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(actors[toSeed % 4], amount);
    }

    function transferFromAboveAllowance(
        uint8 fromSeed,
        uint8 spenderSeed,
        uint8 toSeed,
        uint256 allowance_,
        uint256 excess
    ) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        allowance_ = bound(allowance_, 0, 1_000_000_000 * 1e18);
        uint256 amount = allowance_ + bound(excess, 1, type(uint256).max - allowance_);
        _approve(from, spender, allowance_);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, actors[toSeed % 4], amount);
    }

    /// @dev Approval is sufficient: failure must roll back any allowance spent before the balance check.
    function transferFromAboveBalance(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount, bool infinite)
        external
    {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(from, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, actors[toSeed % 4], amount);
    }

    function transferToZero(uint8 fromSeed, uint8 spenderSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 limit = expectedBalance[from];
        if (delegated && expectedAllowance[from][spender] < limit) limit = expectedAllowance[from][spender];
        amount = bound(amount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : from);
        if (delegated) token.transferFrom(from, address(0), amount);
        else token.transfer(address(0), amount);
    }

    function approveZeroSpender(uint8 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[ownerSeed % 4]);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract TokenInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    Token internal token;
    TokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new Token();
        actors = [makeAddr("holder-0"), makeAddr("holder-1"), makeAddr("holder-2"), makeAddr("holder-3")];
        assertTrue(token.transfer(actors[0], SUPPLY));
        handler = new TokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.approveBoundary.selector;
        selectors[4] = TokenHandler.transferAboveBalance.selector;
        selectors[5] = TokenHandler.transferFromAboveAllowance.selector;
        selectors[6] = TokenHandler.transferFromAboveBalance.selector;
        selectors[7] = TokenHandler.transferToZero.selector;
        selectors[8] = TokenHandler.approveZeroSpender.selector;
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
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// @dev Detects misdirected transfers even when the total of balances remains correct.
    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
        }
    }

    /// @dev Also checks untouched owner/spender pairs and rollback after rejected calls.
    function invariant_eachAllowanceMatchesApprovalsAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
