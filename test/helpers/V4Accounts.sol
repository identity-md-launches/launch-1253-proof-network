// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PROOFToken} from "../../src/PROOFToken.sol";
import {IPoolManager} from "../vendor/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../vendor/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "../vendor/v4-core/src/types/PoolKey.sol";
import {Currency} from "../vendor/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../vendor/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "../vendor/v4-core/src/libraries/TickMath.sol";

interface TestCurrency {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Offline stand-in for the pair currency only; the AMM itself is the pinned upstream PoolManager.
contract PairCurrencyFixture {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev A test-controlled account that can act as a factory or an ordinary trader. All token
/// movement is through transfer and PoolManager sync/settle/take, never storage edits or balance deals.
contract V4Account is IUnlockCallback {
    address private immutable controller = msg.sender;
    IPoolManager public immutable manager;

    struct Request {
        PoolKey key;
        bool isSwap;
        bool skipPayment;
        IPoolManager.ModifyLiquidityParams liquidity;
        IPoolManager.SwapParams trade;
    }

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    modifier onlyController() {
        require(msg.sender == controller, "test controller only");
        _;
    }

    function deployProof(address pair, bool proofIsCurrency0) external onlyController returns (PROOFToken) {
        bytes32 initHash = keccak256(type(PROOFToken).creationCode);
        for (uint256 i; i < 1024; ++i) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initHash)))));
            if ((predicted < pair) == proofIsCurrency0) return new PROOFToken{salt: salt}();
        }
        revert("test currency-order salt search exhausted");
    }

    function move(address token, address to, uint256 amount) external onlyController {
        require(TestCurrency(token).transfer(to, amount), "token transfer returned false");
    }

    function modify(PoolKey calldata key, int24 lower, int24 upper, int256 liquidity)
        external
        onlyController
        returns (BalanceDelta delta, BalanceDelta fees)
    {
        Request memory request;
        request.key = key;
        request.liquidity = IPoolManager.ModifyLiquidityParams(lower, upper, liquidity, bytes32(0));
        return abi.decode(manager.unlock(abi.encode(request)), (BalanceDelta, BalanceDelta));
    }

    function swap(PoolKey calldata key, bool zeroForOne, int256 amountSpecified, bool skipPayment)
        external
        onlyController
        returns (BalanceDelta delta)
    {
        Request memory request;
        request.key = key;
        request.isSwap = true;
        request.skipPayment = skipPayment;
        request.trade = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });
        (delta,) = abi.decode(manager.unlock(abi.encode(request)), (BalanceDelta, BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only PoolManager callback");
        Request memory request = abi.decode(data, (Request));
        BalanceDelta delta;
        BalanceDelta fees = BalanceDeltaLibrary.ZERO_DELTA;
        if (request.isSwap) {
            delta = manager.swap(request.key, request.trade, "");
        } else {
            (delta, fees) = manager.modifyLiquidity(request.key, request.liquidity, "");
        }
        _settle(request.key.currency0, delta.amount0(), request.skipPayment);
        _settle(request.key.currency1, delta.amount1(), request.skipPayment);
        return abi.encode(delta, fees);
    }

    function _settle(Currency currency, int128 delta, bool skipPayment) private {
        if (delta > 0) {
            manager.take(currency, address(this), uint128(delta));
        } else if (delta < 0 && !skipPayment) {
            uint256 owed = uint256(-int256(delta));
            manager.sync(currency);
            require(TestCurrency(Currency.unwrap(currency)).transfer(address(manager), owed), "settlement transfer");
            require(manager.settle() == owed, "PoolManager must receive the entire payment");
        }
    }
}
