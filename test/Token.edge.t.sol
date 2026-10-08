// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Token} from "src/Token.sol";

/// @dev Complements the deployment and basic ERC-20 tests with boundary and repeated-call properties.
/// forge-config: default.fuzz.runs = 1000
contract TokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    Token internal token;
    address internal holder;
    address internal recipient;
    address internal spender;
    address internal stranger;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Token();
        holder = makeAddr("edge-holder");
        recipient = makeAddr("edge-recipient");
        spender = makeAddr("edge-spender");
        stranger = makeAddr("edge-stranger");
    }

    function test_oneWeiRoundTrip() public {
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(holder), 1);
        vm.prank(holder);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferCannotBypassInsufficientBalance() public {
        assertTrue(token.transfer(holder, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(holder);
        token.transfer(holder, 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferRevertsWithoutOverflowOrBalanceChanges() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(recipient, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferFromWithInfiniteApprovalStillChecksBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), recipient, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteApprovalIsNotInfinite() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_infiniteApprovalCanBeRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_transferFromByHolderRequiresItsOwnApproval() public {
        assertTrue(token.transfer(holder, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);
        vm.prank(holder);
        assertTrue(token.approve(holder, 1));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_approvalBelongsToCallerNotTransactionOrigin() public {
        assertTrue(token.transfer(holder, 2));
        vm.prank(holder);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 1));
        vm.prank(stranger, spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.balanceOf(holder), 2);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender, stranger);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), 1);
        assertEq(token.allowance(holder, stranger), 0);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_spenderCannotDelegateAnotherOwnersApproval() public {
        assertTrue(token.transfer(holder, 1));
        vm.prank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.approve(stranger, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 1));
        vm.prank(stranger);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, stranger), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.allowance(spender, stranger), type(uint256).max);
    }

    function test_zeroTransferFromPreservesFiniteApprovalAndEmitsEvent() public {
        vm.prank(holder);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromToZeroRevertsWithInfiniteApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalToZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferConsumesOnlyFiniteAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.transfer(holder, amount));
        vm.prank(holder);
        assertTrue(token.approve(spender, infinite ? type(uint256).max : amount));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, holder, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));
        assertEq(token.balanceOf(holder), amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_repeatingApprovalReplacesRatherThanAdds(uint256 first, uint256 replacement) public {
        vm.startPrank(holder);
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.allowance(spender, holder), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(uint256 balance, uint256 shortfall, bool infinite) public {
        balance = bound(balance, 0, SUPPLY - 1);
        shortfall = bound(shortfall, 1, SUPPLY - balance);
        uint256 amount = balance + shortfall;
        uint256 allowance_ = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(holder, balance));
        vm.prank(holder);
        assertTrue(token.approve(spender, allowance_));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), allowance_);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), 0);

        // Retrying uses the original approval: the failed call must not have consumed it.
        assertTrue(token.transfer(holder, shortfall));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(token.allowance(holder, spender), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitSpendingExhaustsExactlyOneApproval(uint256 amount, uint256 first) public {
        amount = bound(amount, 1, SUPPLY);
        first = bound(first, 0, amount);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, first));
        assertEq(token.allowance(address(this), spender), amount - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount - first));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), recipient, 1);
        assertEq(token.balanceOf(holder), first);
        assertEq(token.balanceOf(recipient), amount - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
