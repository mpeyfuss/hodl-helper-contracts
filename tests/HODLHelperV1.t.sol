// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {HODLHelperV1, Ownable} from "src/HODLHelperV1.sol";
import {MockERC20, ERC20} from "./mocks/MockERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract HODLHelperV1Test is Test {
    HODLHelperV1 public hh;
    MockERC20 public token;

    address feeRecipient = address(0xc0ffee);

    function setUp() public {
        HODLHelperV1.Settings memory s =
            HODLHelperV1.Settings({feeRecipient: feeRecipient, fee: 0.00042 ether, penaltyBps: 690});
        hh = new HODLHelperV1(address(this), s);

        token = new MockERC20(address(this), type(uint256).max);
    }

    function test_setUp() public view {
        (address r, uint256 f, uint256 p) = hh.settings();

        assertEq(r, feeRecipient);
        assertEq(f, 0.00042 ether);
        assertEq(p, 690);
    }

    function test_updateSettings(address hacker) public {
        vm.assume(hacker != address(this));

        // new settings
        HODLHelperV1.Settings memory s =
            HODLHelperV1.Settings({feeRecipient: address(1), fee: 0.00069 ether, penaltyBps: 420});

        // hacker
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        vm.prank(hacker);
        hh.updateSettings(s);

        // owner can update
        hh.updateSettings(s);
        (address r, uint256 f, uint256 p) = hh.settings();
        assertEq(r, address(1));
        assertEq(f, 0.00069 ether);
        assertEq(p, 420);
    }

    function test_lock_errors() public {
        // deal eth
        vm.deal(address(this), 1 ether);
        vm.deal(address(1), 1 ether);

        // test token with no code
        vm.expectRevert(HODLHelperV1.InvalidToken.selector);
        hh.createLock(address(0), 1, 1);

        // test 0 amount
        vm.expectRevert(HODLHelperV1.InvalidLockAmount.selector);
        hh.createLock(address(token), 0, 1);

        // test no fee sent
        vm.expectRevert(HODLHelperV1.InsufficientFee.selector);
        hh.createLock(address(token), 1, 1);

        // test no allowance given
        vm.expectRevert(); // can revert with anything tbh
        hh.createLock{value: 0.00042 ether}(address(token), 1, 1);

        // test insufficient approval
        token.approve(address(hh), 1);
        vm.expectRevert(); // can revert with anything tbh
        hh.createLock{value: 0.00042 ether}(address(token), 2, 1);

        // test insuffcient balance
        vm.startPrank(address(1));
        token.approve(address(hh), 1);
        vm.expectRevert(); // can revert with anything tbh
        hh.createLock{value: 0.00042 ether}(address(token), 1, 1);
        vm.stopPrank();

        // create lock
        hh.createLock{value: 0.00042 ether}(address(token), 1, 1);

        // test adding more, not lock owner
        vm.expectRevert(HODLHelperV1.NotLockOwner.selector);
        vm.prank(address(1));
        hh.addToLock{value: 0.00042 ether}(1, 1);

        // test adding more, 0 amount
        vm.expectRevert(HODLHelperV1.InvalidLockAmount.selector);
        hh.addToLock{value: 0.00042 ether}(1, 0);

        // test adding more, no fee
        vm.expectRevert(HODLHelperV1.InsufficientFee.selector);
        hh.addToLock(1, 1);

        // test adding more, insufficient allowance
        vm.expectRevert();
        hh.addToLock{value: 0.00042 ether}(1, 1);

        // test adding more, insufficient approval
        token.approve(address(hh), 1);
        vm.expectRevert(); // can revert with anything tbh
        hh.addToLock{value: 0.00042 ether}(1, 2);

        // test adding more, insufficient balance
        token.transfer(address(1), token.balanceOf(address(this)));
        vm.expectRevert(); // can revert with anything tbh
        hh.addToLock{value: 0.00042 ether}(1, 1);
    }

    function test_lock(uint128 amount, address user, uint128 lockDuration, uint64 amount2, uint256 fee) public {
        vm.assume(amount > 0);
        vm.assume(user != address(hh));
        vm.assume(user != address(this));
        vm.assume(user != address(0));
        vm.assume(user != feeRecipient);
        vm.assume(amount2 > 0);

        if (fee > 1 ether) {
            fee %= 1 ether;
        }

        uint256 endTime = block.timestamp + lockDuration;

        // update settings
        HODLHelperV1.Settings memory s = HODLHelperV1.Settings({feeRecipient: feeRecipient, fee: fee, penaltyBps: 690});
        hh.updateSettings(s);

        // deal eth
        vm.deal(user, fee * 3);

        // transfer tokens to user to lock
        token.transfer(user, amount);

        // give allowance
        vm.prank(user);
        token.approve(address(hh), amount);

        // lock
        HODLHelperV1.Lock memory l = HODLHelperV1.Lock({
            owner: user,
            token: address(token),
            amount: amount,
            startTime: block.timestamp,
            unlockTime: block.timestamp + lockDuration
        });
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockCreated(1, l);
        vm.prank(user);
        hh.createLock{value: fee}(address(token), amount, lockDuration);

        // check fee
        assertEq(feeRecipient.balance, fee);

        // check balances
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(hh)), amount);

        // get lock
        HODLHelperV1.Lock memory retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // transfer tokens to user to lock
        token.transfer(user, amount2);

        // give allowance
        vm.prank(user);
        token.approve(address(hh), amount2);

        // lock again
        l.amount = uint256(amount) + uint256(amount2);
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockUpdated(1, l);
        vm.prank(user);
        hh.addToLock{value: fee}(1, amount2);

        // get lock
        retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // check fee
        assertEq(feeRecipient.balance, 2 * fee);

        // check balances
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(hh)), uint256(amount) + uint256(amount2));

        // lock after unlock time
        vm.warp(endTime + 1);

        // transfer tokens to user to lock
        token.transfer(user, 1);

        // give allowance
        vm.prank(user);
        token.approve(address(hh), 1);

        // lock again
        l.amount = uint256(amount) + uint256(amount2) + 1;
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockUpdated(1, l);
        vm.prank(user);
        hh.addToLock{value: fee}(1, 1);

        // get lock
        retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // check fee
        assertEq(feeRecipient.balance, 3 * fee);

        // check balances
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(hh)), uint256(amount) + uint256(amount2) + 1);
    }

    function test_unlock_errors(address hacker, uint128 amount, uint128 extra) public {
        vm.assume(hacker != address(this));
        vm.assume(amount > 0);

        token.approve(address(hh), amount);
        vm.deal(address(this), 100 ether);
        (, uint256 fee,) = hh.settings();
        hh.createLock{value: fee}(address(token), amount, 0);

        // try not token owner
        vm.expectRevert(HODLHelperV1.NotLockOwner.selector);
        vm.prank(hacker);
        hh.withdrawFromLock(1, amount);

        // try unlocking more than amount and getting that back
        uint256 initBalance = token.balanceOf(address(this));
        hh.withdrawFromLock(1, uint256(amount) + uint256(extra));
        assertEq(token.balanceOf(address(this)) - initBalance, amount);
    }

    function test_unlock_full_no_penalty(address user, uint256 amount, uint128 lockDuration) public {
        vm.assume(amount > 0);
        vm.assume(user != address(hh));
        vm.assume(user != address(this));
        vm.assume(user != address(0));
        vm.assume(user != feeRecipient);

        uint256 endTime = block.timestamp + lockDuration;

        // get settings
        (, uint256 fee,) = hh.settings();

        // deal eth
        vm.deal(user, fee);

        // transfer tokens to user to lock
        token.transfer(user, amount);

        // give allowance
        vm.prank(user);
        token.approve(address(hh), amount);

        // check effects
        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(address(hh)), 0);

        // lock
        HODLHelperV1.Lock memory l = HODLHelperV1.Lock({
            owner: user,
            token: address(token),
            amount: amount,
            startTime: block.timestamp,
            unlockTime: block.timestamp + lockDuration
        });
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockCreated(1, l);
        vm.prank(user);
        hh.createLock{value: fee}(address(token), amount, lockDuration);

        // get lock
        HODLHelperV1.Lock memory retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // check effects
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(hh)), amount);

        // warp to past unlock
        vm.warp(endTime + 1);

        // unlock
        l.amount = 0;
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockUpdated(1, l);
        vm.prank(user);
        hh.withdrawFromLock(1, amount);

        // check effects
        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(address(hh)), 0);

        // get lock
        retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);
    }

    function test_unlock_partial_no_penalty(address user, uint256 amount, uint256 bps, uint128 lockDuration) public {
        vm.assume(amount > 0);
        vm.assume(user != address(hh));
        vm.assume(user != address(this));
        vm.assume(user != address(0));
        vm.assume(user != feeRecipient);
        if (bps > 10_000) {
            bps %= 10_000;
        }

        uint256 endTime = block.timestamp + lockDuration;

        // get settings
        (, uint256 fee,) = hh.settings();

        // deal eth
        vm.deal(user, fee);

        // transfer tokens to user to lock
        token.transfer(user, amount);

        // give allowance
        vm.prank(user);
        token.approve(address(hh), amount);

        // check effects
        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(address(hh)), 0);

        // lock
        HODLHelperV1.Lock memory l = HODLHelperV1.Lock({
            owner: user,
            token: address(token),
            amount: amount,
            startTime: block.timestamp,
            unlockTime: block.timestamp + lockDuration
        });
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockCreated(1, l);
        vm.prank(user);
        hh.createLock{value: fee}(address(token), amount, lockDuration);

        // get lock
        HODLHelperV1.Lock memory retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // check effects
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(hh)), amount);

        // warp to past unlock
        vm.warp(endTime + 1);

        // adjust amount
        amount = amount < 10_000 ? amount * bps / 10_000 : amount / 10_000 * bps;

        // unlock
        l.amount -= amount;
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockUpdated(1, l);
        vm.prank(user);
        hh.withdrawFromLock(1, amount);

        // get lock
        retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // check effects
        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(address(hh)), l.amount);
    }

    function test_unlock_penalty(address user, uint256 amount, uint128 lockDuration) public {
        vm.assume(amount > 0);
        vm.assume(lockDuration > 0);
        vm.assume(user != address(hh));
        vm.assume(user != address(this));
        vm.assume(user != address(0));
        vm.assume(user != feeRecipient);

        // get settings
        (, uint256 fee, uint256 penaltyBps) = hh.settings();

        // deal eth
        vm.deal(user, fee);

        // transfer tokens to user to lock
        token.transfer(user, amount);

        // give allowance
        vm.prank(user);
        token.approve(address(hh), amount);

        // check effects
        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(address(hh)), 0);

        // lock
        HODLHelperV1.Lock memory l = HODLHelperV1.Lock({
            owner: user,
            token: address(token),
            amount: amount,
            startTime: block.timestamp,
            unlockTime: block.timestamp + lockDuration
        });
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockCreated(1, l);
        vm.prank(user);
        hh.createLock{value: fee}(address(token), amount, lockDuration);

        // get lock
        HODLHelperV1.Lock memory retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // check effects
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(hh)), amount);

        // calculate penalty
        uint256 penalty = amount < 10_000 ? amount * penaltyBps / 10_000 : amount / 10_000 * penaltyBps;

        // unlock
        l.amount = 0;
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockUpdated(1, l);
        vm.prank(user);
        hh.withdrawFromLock(1, amount);

        // check effects
        assertEq(token.balanceOf(user), amount - penalty);
        assertEq(token.balanceOf(address(hh)), 0);
        assertEq(token.balanceOf(feeRecipient), penalty);

        // get lock
        retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);
    }

    function test_unlock_penalty_partial(address user, uint256 amount, uint256 bps, uint128 lockDuration) public {
        vm.assume(amount > 0);
        vm.assume(lockDuration > 0);
        vm.assume(user != address(hh));
        vm.assume(user != address(this));
        vm.assume(user != address(0));
        vm.assume(user != feeRecipient);
        if (bps > 10_000) {
            bps %= 10_000;
        }

        // get settings
        (, uint256 fee, uint256 penaltyBps) = hh.settings();

        // deal eth
        vm.deal(user, fee);

        // transfer tokens to user to lock
        token.transfer(user, amount);

        // give allowance
        vm.prank(user);
        token.approve(address(hh), amount);

        // check effects
        assertEq(token.balanceOf(user), amount);
        assertEq(token.balanceOf(address(hh)), 0);

        // lock
        HODLHelperV1.Lock memory l = HODLHelperV1.Lock({
            owner: user,
            token: address(token),
            amount: amount,
            startTime: block.timestamp,
            unlockTime: block.timestamp + lockDuration
        });
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockCreated(1, l);
        vm.prank(user);
        hh.createLock{value: fee}(address(token), amount, lockDuration);

        // get lock
        HODLHelperV1.Lock memory retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);

        // check effects
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(address(hh)), amount);

        // adjust amount
        amount = amount < 10_000 ? amount * bps / 10_000 : amount / 10_000 * bps;

        // calculate penalty
        uint256 penalty = amount < 10_000 ? amount * penaltyBps / 10_000 : amount / 10_000 * penaltyBps;

        // unlock
        l.amount -= amount;
        vm.expectEmit(true, true, true, true);
        emit HODLHelperV1.LockUpdated(1, l);
        vm.prank(user);
        hh.withdrawFromLock(1, amount);

        // check effects
        assertEq(token.balanceOf(user), amount - penalty);
        assertEq(token.balanceOf(address(hh)), l.amount);
        assertEq(token.balanceOf(feeRecipient), penalty);

        // get lock
        retLock = hh.getLock(1);
        assertEq(retLock.owner, l.owner);
        assertEq(retLock.token, l.token);
        assertEq(retLock.amount, l.amount);
        assertEq(retLock.startTime, l.startTime);
        assertEq(retLock.unlockTime, l.unlockTime);
    }

    function test_multiple_locks_same_token(address user1, uint128 amount1, address user2, uint128 amount2) public {
        vm.assume(user1 != address(0));
        vm.assume(user1 != address(this));
        vm.assume(user1 != address(hh));
        vm.assume(amount1 > 0);
        vm.assume(user2 != address(0));
        vm.assume(user2 != address(this));
        vm.assume(user2 != address(hh));
        vm.assume(amount2 > 0);

        // deal tokens
        token.transfer(user1, amount1);
        token.transfer(user2, amount2);

        // get settings
        (, uint256 fee,) = hh.settings();

        // assert tokens
        if (user1 != user2) {
            assertEq(token.balanceOf(user1), amount1);
            assertEq(token.balanceOf(user2), amount2);
        } else {
            assertEq(token.balanceOf(user1), uint256(amount1) + uint256(amount2));
        }
        assertEq(token.balanceOf(address(hh)), 0);

        // lock tokens
        vm.deal(user1, fee);
        vm.prank(user1);
        token.approve(address(hh), amount1);
        vm.prank(user1);
        hh.createLock{value: fee}(address(token), amount1, 0);

        vm.deal(user2, fee);
        vm.prank(user2);
        token.approve(address(hh), amount2);
        vm.prank(user2);
        hh.createLock{value: fee}(address(token), amount2, 0);

        // assert tokens
        assertEq(token.balanceOf(user1), 0);
        assertEq(token.balanceOf(user2), 0);
        assertEq(token.balanceOf(address(hh)), uint256(amount1) + uint256(amount2));

        // unlock tokens
        vm.prank(user1);
        hh.withdrawFromLock(1, amount1);
        vm.prank(user2);
        hh.withdrawFromLock(2, amount2);

        // assert tokens
        if (user1 != user2) {
            assertEq(token.balanceOf(user1), amount1);
            assertEq(token.balanceOf(user2), amount2);
        } else {
            assertEq(token.balanceOf(user1), uint256(amount1) + uint256(amount2));
        }
        assertEq(token.balanceOf(address(hh)), 0);
    }

    function test_multiple_locks_diff_token(address user1, uint128 amount1, address user2, uint128 amount2) public {
        vm.assume(user1 != address(0));
        vm.assume(user1 != address(this));
        vm.assume(user1 != address(hh));
        vm.assume(amount1 > 0);
        vm.assume(user2 != address(0));
        vm.assume(user2 != address(this));
        vm.assume(user2 != address(hh));
        vm.assume(amount2 > 0);

        // create tokens
        MockERC20 token1 = new MockERC20(user1, amount1);
        MockERC20 token2 = new MockERC20(user2, amount2);

        // get settings
        (, uint256 fee,) = hh.settings();

        // approve tokens
        vm.prank(user1);
        token1.approve(address(hh), amount1);
        vm.prank(user2);
        token2.approve(address(hh), amount2);

        // assert tokens
        assertEq(token1.balanceOf(user1), amount1);
        assertEq(token2.balanceOf(user2), amount2);
        assertEq(token1.balanceOf(address(hh)), 0);
        assertEq(token2.balanceOf(address(hh)), 0);

        // lock tokens
        vm.deal(user1, fee);
        vm.prank(user1);
        hh.createLock{value: fee}(address(token1), amount1, 0);

        vm.deal(user2, fee);
        vm.prank(user2);
        hh.createLock{value: fee}(address(token2), amount2, 0);

        // assert tokens
        assertEq(token1.balanceOf(user1), 0);
        assertEq(token2.balanceOf(user2), 0);
        assertEq(token1.balanceOf(address(hh)), amount1);
        assertEq(token2.balanceOf(address(hh)), amount2);

        // unlock tokens
        vm.prank(user1);
        hh.withdrawFromLock(1, amount1);
        vm.prank(user2);
        hh.withdrawFromLock(2, amount2);

        // assert tokens
        assertEq(token1.balanceOf(user1), amount1);
        assertEq(token2.balanceOf(user2), amount2);
        assertEq(token1.balanceOf(address(hh)), 0);
        assertEq(token2.balanceOf(address(hh)), 0);
    }
}
