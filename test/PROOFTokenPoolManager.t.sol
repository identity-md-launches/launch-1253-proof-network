// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PROOFToken} from "../src/PROOFToken.sol";
import {TokenTestBase} from "./helpers/TokenTestBase.sol";
import {V4Account, PairCurrencyFixture} from "./helpers/V4Accounts.sol";
import {PoolManager} from "./vendor/v4-core/src/PoolManager.sol";
import {IPoolManager} from "./vendor/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "./vendor/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "./vendor/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "./vendor/v4-core/src/types/PoolId.sol";
import {Currency} from "./vendor/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "./vendor/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "./vendor/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "./vendor/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "./vendor/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "./vendor/v4-core/src/libraries/TransientStateLibrary.sol";

contract PROOFTokenPoolManagerTest is TokenTestBase {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    uint24 private constant FEE = 12_500; // 1.25% in v4 fee units; PROOF itself charges no fee.
    int24 private constant SPACING = 60;
    uint256 private constant CAP = 2500 ether;
    uint256 private constant POOL_BUDGET = SUPPLY * 9000 / 10_000;
    uint256 private constant Q96 = 1 << 96;

    IPoolManager private manager;
    PairCurrencyFixture private pair;
    V4Account private factory;
    V4Account private trader;
    PROOFToken private token;
    PoolKey private key;
    bool private proofIs0;
    int24 private lower;
    int24 private upper;
    uint128 private liquidity;
    uint256 private seeded;

    function setUp() public {
        vm.chainId(1);
        // Execute the constructor at the actual manager address: merely etching a manager deployed
        // elsewhere would break its NoDelegateCall immutable and skip constructor storage writes.
        vm.etch(POOL_MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = POOL_MANAGER.call("");
        require(ok && runtime.length > 0, "construct local PoolManager in place");
        vm.etch(POOL_MANAGER, runtime);
        manager = IPoolManager(POOL_MANAGER);
        vm.etch(PAIR, address(new PairCurrencyFixture()).code);
        pair = PairCurrencyFixture(PAIR);
        factory = new V4Account(manager);
        trader = new V4Account(manager);
    }

    function test_SingleSidedLaunchBuySellAndCollectFees_PROOFIsCurrency0() public {
        _launch(true);
        _roundTrip(1 ether);
        _collectFees();
    }

    function test_SingleSidedLaunchBuySellAndCollectFees_PROOFIsCurrency1() public {
        _launch(false);
        _roundTrip(1 ether);
        _collectFees();
    }

    function testFuzz_ExactInputRoundTripHasNoTokenTax(uint256 rawInput, bool tokenFirst) public {
        _launch(tokenFirst);
        // Avoid output dust and keep the sell inside the range after paying the buy fee.
        _roundTrip(1e12 + rawInput % (10 ether - 1e12 + 1));
    }

    function test_ExactOutputBuyAndSellSettleWholeAmounts() public {
        _launch(true);
        pair.mint(address(trader), 10 ether);
        uint256 output = 1000 ether;
        uint256 beforePair = pair.balanceOf(address(trader));
        BalanceDelta buy = trader.swap(key, !proofIs0, int256(output), false);
        eq(_positive(_proofDelta(buy)), output, "exact PROOF output delta");
        eq(token.balanceOf(address(trader)), output, "exact output arrived whole");
        eq(beforePair - pair.balanceOf(address(trader)), _negative(_pairDelta(buy)), "whole pair payment");
        eq(seeded - token.balanceOf(POOL_MANAGER), output, "manager paid exact output");

        uint256 pairOutput = 0.001 ether;
        uint256 beforeProof = token.balanceOf(address(trader));
        beforePair = pair.balanceOf(address(trader));
        BalanceDelta sell = trader.swap(key, proofIs0, int256(pairOutput), false);
        eq(_positive(_pairDelta(sell)), pairOutput, "exact pair output delta");
        eq(pair.balanceOf(address(trader)) - beforePair, pairOutput, "exact pair output delivered");
        eq(beforeProof - token.balanceOf(address(trader)), _negative(_proofDelta(sell)), "exact sell payment");
        _assertSettled();
        _assertConservation();
    }

    function test_UnpaidSwapRevertsAndRollsBackOutputAndPoolState() public {
        _launch(true);
        (uint160 priceBefore, int24 tickBefore,,) = manager.getSlot0(key.toId());
        vm.expectRevert(IPoolManager.CurrencyNotSettled.selector);
        trader.swap(key, !proofIs0, -int256(1 ether), true);
        eq(token.balanceOf(address(trader)), 0, "unpaid output rolls back");
        eq(token.balanceOf(POOL_MANAGER), seeded, "pool balance rolls back");
        (uint160 priceAfter, int24 tickAfter,,) = manager.getSlot0(key.toId());
        eq(priceAfter, priceBefore, "swap price rolls back");
        require(tickAfter == tickBefore, "swap tick rolls back");
        (uint256 fee0, uint256 fee1) = manager.getFeeGrowthGlobals(key.toId());
        eq(fee0 + fee1, 0, "unpaid swap accrues no fees");
        _assertSettled();
        _roundTrip(1 ether); // A failed unlock does not prevent later legitimate swaps.
    }

    function test_UnfundedSellerCannotCreateTokensThroughSettlement() public {
        _launch(false);
        _roundTrip(1 ether); // Establish active liquidity and pair reserves first.
        vm.expectRevert(
            abi.encodeWithSelector(PROOFToken.ERC20InsufficientBalance.selector, address(trader), 0, 1 ether)
        );
        trader.swap(key, proofIs0, -int256(1 ether), false);
        eq(token.balanceOf(address(trader)), 0, "failed seller receives no PROOF");
        eq(token.balanceOf(POOL_MANAGER), seeded, "failed sale cannot alter manager balance");
        _assertSettled();
        _assertConservation();
    }

    function test_ZeroSwapIsRejectedWithoutMovingTokens() public {
        _launch(true);
        vm.expectRevert(IPoolManager.SwapAmountCannotBeZero.selector);
        trader.swap(key, !proofIs0, 0, false);
        eq(token.balanceOf(POOL_MANAGER), seeded, "zero swap preserves pool");
        _assertSettled();
    }

    function _launch(bool tokenFirst) private {
        proofIs0 = tokenFirst;
        token = factory.deployProof(PAIR, tokenFirst);
        require((address(token) < PAIR) == tokenFirst, "exercise requested currency order");
        eq(token.balanceOf(address(factory)), SUPPLY, "factory gets 100%, no constructor swarm subtraction");
        key = PoolKey({
            currency0: Currency.wrap(tokenFirst ? address(token) : PAIR),
            currency1: Currency.wrap(tokenFirst ? PAIR : address(token)),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(0))
        });

        // Derive the opening price from the economics and actual currency order. The manifest's
        // initialPrice is provenance for currency0=PROOF, not a price to reuse after sorting.
        uint256 ratioX192 = FullMath.mulDiv(tokenFirst ? CAP : SUPPLY, 1 << 192, tokenFirst ? SUPPLY : CAP);
        uint160 price = uint160(_sqrt(ratioX192));
        int24 tick = manager.initialize(key, price);
        int24 floorTick = (tick / SPACING) * SPACING;
        if (tick < 0 && tick % SPACING != 0) floorTick -= SPACING;
        lower = tokenFirst ? floorTick + SPACING : TickMath.minUsableTick(SPACING);
        upper = tokenFirst ? TickMath.maxUsableTick(SPACING) : floorTick;
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(lower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(upper);
        uint256 computedLiquidity = tokenFirst
            ? FullMath.mulDiv(POOL_BUDGET, FullMath.mulDiv(sqrtLower, sqrtUpper, Q96), sqrtUpper - sqrtLower)
            : FullMath.mulDiv(POOL_BUDGET, Q96, sqrtUpper - sqrtLower);
        require(computedLiquidity > 0 && computedLiquidity <= uint128(type(int128).max), "valid test liquidity");
        liquidity = uint128(computedLiquidity);

        factory.move(address(token), DISTRIBUTOR, SUPPLY / 10);
        (BalanceDelta seedDelta,) = factory.modify(key, lower, upper, int256(uint256(liquidity)));
        seeded = _negative(_proofDelta(seedDelta));
        require(seeded > 0 && seeded <= POOL_BUDGET, "seed fits the 90% pool budget");
        require(POOL_BUDGET - seeded < 1e12, "seed uses the budget apart from liquidity rounding");
        require(_pairDelta(seedDelta) == 0, "launch liquidity must be single-sided PROOF");
        eq(token.balanceOf(POOL_MANAGER), seeded, "manager receives the entire seed");
        eq(pair.balanceOf(POOL_MANAGER), 0, "no pair currency required to launch");
        uint256 remainder = POOL_BUDGET - seeded;
        factory.move(address(token), REMAINDER_TO, remainder);
        eq(token.balanceOf(REMAINDER_TO), remainder, "rounding remainder delivered whole");
        eq(token.balanceOf(address(factory)), 0, "factory distribution exhausts supply");
        eq(token.balanceOf(DISTRIBUTOR), SUPPLY / 10, "entire swarm share delivered");
        // Claim leg only: Merkle verification belongs to the network's distributor, absent here.
        vm.prank(DISTRIBUTOR);
        require(token.transfer(ALICE, SUPPLY / 10), "swarm claim transfer");
        eq(token.balanceOf(ALICE), SUPPLY / 10, "entire swarm claim delivered");
        eq(token.balanceOf(DISTRIBUTOR), 0, "distributor retains no token tax");
        (,,, uint24 actualFee) = manager.getSlot0(key.toId());
        eq(actualFee, FEE, "pool uses the required nonzero swap fee");
        _assertSettled();
        _assertConservation();
    }

    function _roundTrip(uint256 input) private {
        uint256 pairBefore = pair.balanceOf(address(trader));
        pair.mint(address(trader), input);
        BalanceDelta buy = trader.swap(key, !proofIs0, -int256(input), false);
        uint256 bought = _positive(_proofDelta(buy));
        require(bought > 0, "ordinary trader buys PROOF");
        eq(_negative(_pairDelta(buy)), input, "entire exact input spent");
        eq(token.balanceOf(address(trader)), bought, "buy output is not taxed");
        eq(seeded - token.balanceOf(POOL_MANAGER), bought, "buy debit equals trader receipt");
        eq(pair.balanceOf(address(trader)), pairBefore, "pair input settled exactly");
        (uint256 fee0, uint256 fee1) = manager.getFeeGrowthGlobals(key.toId());
        require((proofIs0 ? fee1 : fee0) > 0, "buy actually accrues pair-denominated LP fees");
        _assertSettled();

        BalanceDelta sell = trader.swap(key, proofIs0, -int256(bought), false);
        uint256 returnedPair = _positive(_pairDelta(sell));
        eq(_negative(_proofDelta(sell)), bought, "sell spends all bought PROOF");
        eq(token.balanceOf(address(trader)), 0, "seller can exit fully");
        eq(token.balanceOf(POOL_MANAGER), seeded, "sell settles the full PROOF amount despite LP fees");
        eq(pair.balanceOf(address(trader)) - pairBefore, returnedPair, "sell output delivered whole");
        require(returnedPair > 0 && returnedPair < input, "fee-bearing round trip returns less pair currency");
        (fee0, fee1) = manager.getFeeGrowthGlobals(key.toId());
        require(fee0 > 0 && fee1 > 0, "both swap directions accrue LP fees");
        _assertSettled();
        _assertConservation();
    }

    function _collectFees() private {
        uint256 proofBefore = token.balanceOf(address(factory));
        uint256 pairBefore = pair.balanceOf(address(factory));
        uint256 managerProofBefore = token.balanceOf(POOL_MANAGER);
        (BalanceDelta delta, BalanceDelta fees) = factory.modify(key, lower, upper, 0);
        uint256 proofFees = _positive(_proofDelta(fees));
        uint256 pairFees = _positive(_pairDelta(fees));
        require(proofFees > 0 && pairFees > 0, "fees in both currencies are collectible");
        require(BalanceDelta.unwrap(delta) == BalanceDelta.unwrap(fees), "zero-liquidity poke withdraws only fees");
        eq(token.balanceOf(address(factory)) - proofBefore, proofFees, "PROOF fee collection is not taxed");
        eq(managerProofBefore - token.balanceOf(POOL_MANAGER), proofFees, "manager pays exact PROOF fees");
        eq(pair.balanceOf(address(factory)) - pairBefore, pairFees, "pair fees delivered whole");
        (delta, fees) = factory.modify(key, lower, upper, 0);
        require(BalanceDelta.unwrap(delta) == 0 && BalanceDelta.unwrap(fees) == 0, "fees cannot be collected twice");
        _assertSettled();
        _assertConservation();
    }

    function _assertSettled() private view {
        require(!manager.isUnlocked(), "manager relocks after each operation");
        eq(manager.getNonzeroDeltaCount(), 0, "no unsettled currency debts");
        require(manager.currencyDelta(address(factory), key.currency0) == 0, "factory currency0 settled");
        require(manager.currencyDelta(address(factory), key.currency1) == 0, "factory currency1 settled");
        require(manager.currencyDelta(address(trader), key.currency0) == 0, "trader currency0 settled");
        require(manager.currencyDelta(address(trader), key.currency1) == 0, "trader currency1 settled");
    }

    function _assertConservation() private view {
        eq(token.totalSupply(), SUPPLY, "launch and swaps preserve fixed supply");
        uint256 accounted = token.balanceOf(address(factory)) + token.balanceOf(address(trader))
            + token.balanceOf(POOL_MANAGER) + token.balanceOf(DISTRIBUTOR) + token.balanceOf(ALICE)
            + token.balanceOf(REMAINDER_TO);
        eq(accounted, SUPPLY, "every PROOF unit remains accounted for");
        eq(
            pair.balanceOf(address(factory)) + pair.balanceOf(address(trader)) + pair.balanceOf(POOL_MANAGER),
            pair.totalSupply(),
            "pair settlement conserves all input funds"
        );
    }

    function _proofDelta(BalanceDelta delta) private view returns (int128) {
        return proofIs0 ? delta.amount0() : delta.amount1();
    }

    function _pairDelta(BalanceDelta delta) private view returns (int128) {
        return proofIs0 ? delta.amount1() : delta.amount0();
    }

    function _positive(int128 delta) private pure returns (uint256) {
        require(delta >= 0, "expected credit");
        return uint128(delta);
    }

    function _negative(int128 delta) private pure returns (uint256) {
        require(delta <= 0, "expected debt");
        return uint256(-int256(delta));
    }

    function _sqrt(uint256 value) private pure returns (uint256 result) {
        result = value;
        uint256 next = value / 2 + 1;
        while (next < result) {
            result = next;
            next = (value / next + next) / 2;
        }
    }
}
