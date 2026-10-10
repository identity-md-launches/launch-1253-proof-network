// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PROOFToken} from "../src/PROOFToken.sol";
import {TokenTestBase} from "./helpers/TokenTestBase.sol";

/// @dev Closed actor set makes the balance sum exhaustive. Ghost state records intended effects,
/// never balanceOf/allowance results, so a faulty token cannot redefine the expected ledger.
contract PROOFTokenHandler is TokenTestBase {
    PROOFToken public immutable token;
    address[5] public actors;
    uint256[5] public expectedBalance;
    uint256[5][5] public expectedAllowance;
    uint256 public successfulCalls;
    uint256 public rejectedCalls;

    constructor() {
        token = new PROOFToken();
        actors = [address(this), ALICE, BOB, DISTRIBUTOR, POOL_MANAGER];
        expectedBalance[0] = SUPPLY;
        for (uint256 i = 1; i < actors.length; ++i) {
            require(token.transfer(actors[i], SUPPLY / 10), "initial actor funding");
            expectedBalance[0] -= SUPPLY / 10;
            expectedBalance[i] = SUPPLY / 10;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        uint256 from = fromSeed % 5;
        uint256 to = toSeed % 5;
        uint256 amount = rawAmount % (expectedBalance[from] + 1);
        vm.prank(actors[from]);
        require(token.transfer(actors[to], amount), "valid transfer must succeed");
        _move(from, to, amount);
        ++successfulCalls;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool infinite) external {
        uint256 owner = ownerSeed % 5;
        uint256 spender = spenderSeed % 5;
        // Include revocations, finite amounts above the supply, and the infinite sentinel.
        if (infinite) amount = type(uint256).max;
        vm.prank(actors[owner]);
        require(token.approve(actors[spender], amount), "valid approval must succeed");
        expectedAllowance[owner][spender] = amount;
        ++successfulCalls;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        uint256 owner = ownerSeed % 5;
        uint256 spender = spenderSeed % 5;
        uint256 to = toSeed % 5;
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 maximum = allowed < expectedBalance[owner] ? allowed : expectedBalance[owner];
        uint256 amount = rawAmount % (maximum + 1);
        vm.prank(actors[spender]);
        require(token.transferFrom(actors[owner], actors[to], amount), "valid delegated transfer must succeed");
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _move(owner, to, amount);
        ++successfulCalls;
    }

    function rejectOverdraw(uint256 fromSeed, uint256 toSeed, uint256 rawExtra) external {
        uint256 from = fromSeed % 5;
        uint256 to = toSeed % 5;
        uint256 amount = expectedBalance[from] + 1 + rawExtra % SUPPLY;
        vm.prank(actors[from]);
        (bool ok, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (actors[to], amount)));
        require(!ok, "overdraw must fail even for self transfer");
        eqBytes(
            reason,
            abi.encodeWithSelector(
                PROOFToken.ERC20InsufficientBalance.selector, actors[from], expectedBalance[from], amount
            ),
            "overdraw error"
        );
        ++rejectedCalls;
    }

    function rejectUnauthorizedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        uint256 owner = ownerSeed % 5;
        uint256 spender = spenderSeed % 5;
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed == type(uint256).max) return;
        vm.prank(actors[spender]);
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (actors[owner], actors[toSeed % 5], allowed + 1)));
        require(!ok, "allowance cannot be exceeded");
        eqBytes(
            reason,
            abi.encodeWithSelector(
                PROOFToken.ERC20InsufficientAllowance.selector, actors[spender], allowed, allowed + 1
            ),
            "allowance error"
        );
        ++rejectedCalls;
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        uint256 owner = ownerSeed % 5;
        uint256 spender = spenderSeed % 5;
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 maximum = allowed < expectedBalance[owner] ? allowed : expectedBalance[owner];
        uint256 amount = rawAmount % (maximum + 1);
        vm.prank(actors[spender]);
        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (actors[owner], address(0), amount)));
        require(!ok, "zero recipient must fail");
        eqBytes(reason, abi.encodeWithSelector(PROOFToken.ERC20InvalidReceiver.selector, address(0)), "recipient error");
        ++rejectedCalls;
    }

    function _move(uint256 from, uint256 to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

contract PROOFTokenInvariantTest is TokenTestBase {
    PROOFTokenHandler private handler;
    PROOFToken private token;

    function setUp() public {
        handler = new PROOFTokenHandler();
        token = handler.token();
    }

    /// @dev Foundry's StdInvariant discovery ABI, implemented locally to avoid a test-library dependency.
    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 32
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_FixedSupplyAndExactBalancesAndAllowances() public view {
        eq(token.totalSupply(), SUPPLY, "supply is fixed forever");
        uint256 balanceSum;
        for (uint256 i; i < 5; ++i) {
            address holder = handler.actors(i);
            uint256 actual = token.balanceOf(holder);
            eq(actual, handler.expectedBalance(i), "transfer, self transfer, or revert corrupted balance");
            balanceSum += actual;
            for (uint256 j; j < 5; ++j) {
                eq(
                    token.allowance(holder, handler.actors(j)),
                    handler.expectedAllowance(i, j),
                    "approval, spend, or revert corrupted allowance"
                );
            }
        }
        eq(balanceSum, SUPPLY, "no tax, mint, burn, or untracked allocation");
        eq(token.balanceOf(address(0)), 0, "zero address never receives supply");
        eq(token.balanceOf(address(token)), 0, "token never collects fees");
    }

    function test_HandlerExercisesSuccessfulAndRejectedActions() public {
        handler.approve(0, 1, 12, false);
        handler.transferFrom(0, 1, 2, 7);
        handler.rejectUnauthorizedSpend(0, 1, 2);
        handler.rejectOverdraw(0, 2, 0);
        handler.rejectZeroRecipient(0, 1, 1);
        handler.transfer(2, 2, 1);
        handler.approve(0, 1, 0, true);
        handler.transferFrom(0, 1, 2, 3);
        handler.approve(0, 1, 0, false);
        invariant_FixedSupplyAndExactBalancesAndAllowances();
        eq(handler.successfulCalls(), 6, "valid handler actions were exercised");
        eq(handler.rejectedCalls(), 3, "invalid handler actions were exercised");
    }
}
