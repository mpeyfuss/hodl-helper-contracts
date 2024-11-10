// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title HODLHelperV1.sol
 * @notice Contract to help people HODL tokens
 * @author mpeyfuss
 * @custom:version 1.0.0
 */
contract HODLHelperV1 is Ownable2Step, ReentrancyGuard {
    /////////////////////////////////////////
    /// TYPES
    /////////////////////////////////////////

    using SafeERC20 for IERC20;

    struct Settings {
        address feeRecipient;
        uint256 fee;
        uint256 penaltyBps;
    }

    struct Lock {
        address owner;
        address token;
        uint256 amount;
        uint256 startTime;
        uint256 unlockTime;
    }

    /////////////////////////////////////////
    /// STORAGE
    /////////////////////////////////////////

    uint256 public constant BASIS = 10_000;
    uint256 private _lockCounter;
    mapping(uint256 => Lock) private _locks;
    Settings public settings;

    /////////////////////////////////////////
    /// EVENTS
    /////////////////////////////////////////

    event LockCreated(uint256 indexed lockId, Lock lock);
    event LockUpdated(uint256 indexed lockId, Lock lock);
    event SettingsUpdated(address indexed sender, Settings settings);

    /////////////////////////////////////////
    /// ERRORS
    /////////////////////////////////////////

    error InvalidToken();
    error InvalidLockAmount();
    error InsufficientFee();
    error NotLockOwner();

    /////////////////////////////////////////
    /// CONSTRUTOR
    /////////////////////////////////////////
    constructor(address initOwner, Settings memory initSettings) Ownable(initOwner) ReentrancyGuard() {
        _updateSettings(initSettings);
    }

    /////////////////////////////////////////
    /// PUBLIC FUNCTIONS
    /////////////////////////////////////////

    /**
     * @notice Function to lock away tokens in a new Lock
     * @param token The token address
     * @param amount The amount of the token to lock
     * @param lockDuration The time to lock up the tokens without a penalty
     */
    function createLock(address token, uint256 amount, uint256 lockDuration) public payable nonReentrant {
        // load Settings into memory
        Settings memory s = settings;

        // run sanity checks on the user supplied values
        if (token.code.length == 0) revert InvalidToken();
        if (amount == 0) revert InvalidLockAmount();
        if (msg.value != s.fee) revert InsufficientFee();

        // create Lock
        uint256 lockId = ++_lockCounter;
        Lock memory lock = Lock({
            owner: msg.sender,
            token: token,
            amount: amount,
            startTime: block.timestamp,
            unlockTime: block.timestamp + lockDuration
        });
        _locks[lockId] = lock;

        // transfer amount into the contract
        IERC20(lock.token).safeTransferFrom(msg.sender, address(this), amount);

        // transfer fee to fee recipient
        Address.sendValue(payable(s.feeRecipient), msg.value);

        // emit LockCreated
        emit LockCreated(lockId, lock);
    }

    /**
     * @notice Function to add tokens to an existing Lock
     * @dev `msg.sender` must be the `Lock.owner`
     * @param lockId The Lock id
     * @param amount The amount of the Lock token to add
     */
    function addToLock(uint256 lockId, uint256 amount) public payable nonReentrant {
        // load Lock and Settings into memory
        Lock memory lock = _locks[lockId];
        Settings memory s = settings;

        // check Lock ownership and other conditions
        if (lock.owner != msg.sender) revert NotLockOwner();
        if (amount == 0) revert InvalidLockAmount();
        if (msg.value != s.fee) revert InsufficientFee();

        // adjust memory and storage Lock amounts
        // adjusting memory Lock saves an SLOAD
        lock.amount += amount;
        _locks[lockId].amount += amount;

        // transfer amount into the contract
        IERC20(lock.token).safeTransferFrom(msg.sender, address(this), amount);

        // transfer fee to fee recipient
        Address.sendValue(payable(s.feeRecipient), msg.value);

        // emit LockUpdated
        emit LockUpdated(lockId, lock);
    }

    /**
     * Function to withdraw a subset of tokens from a Lock
     * @dev `msg.sneder` must be the `Lock.owner`
     * @param lockId The Lock id
     * @param amount The amount of the Lock token to add
     */
    function withdrawFromLock(uint256 lockId, uint256 amount) public nonReentrant {
        // load Lock & settings into memory
        Lock memory lock = _locks[lockId];
        Settings memory s = settings;

        // check Lock ownership
        if (lock.owner != msg.sender) revert NotLockOwner();

        // check withdraw amount and adjust if needed
        if (amount > lock.amount) amount = lock.amount;

        // subtract amount being removed from the memory and storage Lock
        // it is subtracted from the memory Lock to remove an SLOAD when emitting the event
        lock.amount -= amount;
        _locks[lockId].amount -= amount;

        // if unlocking prior to the unlock time, it incurs a penalty
        // transfer penalty and adjust amount to transfer to the Lock owner.
        if (block.timestamp < lock.unlockTime) {
            // divide before multiple only for values larger than `BASIS` to avoid overlow. Multiply before divide for values lower to avoid truncation to 0 penalty.
            uint256 penalty = amount < BASIS ? amount * s.penaltyBps / BASIS : amount / BASIS * s.penaltyBps;
            IERC20(lock.token).safeTransfer(s.feeRecipient, penalty);
            amount -= penalty;
        }

        // transfer remaining amount to the Lock owner
        IERC20(lock.token).safeTransfer(lock.owner, amount);

        // emit LockUpdated event
        emit LockUpdated(lockId, lock);
    }

    /**
     * @notice Function to get lock details
     * @param lockId The id of the lock
     * @return Lock
     */
    function getLock(uint256 lockId) public view returns (Lock memory) {
        return _locks[lockId];
    }

    /**
     * @notice Function to update settings of the contract
     * @dev Only callable by the contract owner
     * @param newSettings The new Settings
     */
    function updateSettings(Settings calldata newSettings) public onlyOwner {
        _updateSettings(newSettings);
    }

    /////////////////////////////////////////
    /// PRIVATE FUNCTIONS
    /////////////////////////////////////////

    /**
     * Private helper to set contract settings
     * @param newSettings The new settings
     */
    function _updateSettings(Settings memory newSettings) private {
        settings = newSettings;
        emit SettingsUpdated(msg.sender, newSettings);
    }
}
