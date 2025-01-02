// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IERC20, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";
import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";
import {IMaglevBase} from "./interfaces/IMaglevBase.sol";

abstract contract MaglevBase is IMaglevBase, EVCUtil {
    address public immutable vault0;
    address public immutable vault1;
    address public immutable asset0;
    address public immutable asset1;
    address public immutable myAccount;
    uint112 public immutable debtLimit0;
    uint112 public immutable debtLimit1;
    uint256 public immutable feeMultiplier;

    uint112 internal reserve0;
    uint112 internal reserve1;
    uint32 internal locked; // uses single storage slot, accessible via getReserves()

    error Locked();
    error Overflow();
    error UnsupportedPair();
    error BadFee();
    error InsufficientReserves();
    error InsufficientCash();
    error DifferentEVC();

    modifier nonReentrant() {
        require(locked == 0, Locked());
        locked = 1;
        _;
        locked = 0;
    }

    struct BaseParams {
        address evc;
        address vault0;
        address vault1;
        address myAccount;
        uint112 debtLimit0;
        uint112 debtLimit1;
        uint256 fee;
    }

    constructor(BaseParams memory params) EVCUtil(params.evc) {
        require(params.fee < 1e18, BadFee());

        address vault0Evc = IEVault(params.vault0).EVC();
        require(vault0Evc == IEVault(params.vault1).EVC(), DifferentEVC());
        require(vault0Evc == params.evc, DifferentEVC());

        vault0 = params.vault0;
        vault1 = params.vault1;
        asset0 = IEVault(vault0).asset();
        asset1 = IEVault(vault1).asset();

        require(asset0 != asset1, UnsupportedPair());

        myAccount = params.myAccount;
        reserve0 = offsetReserve(params.debtLimit0, vault0);
        reserve1 = offsetReserve(params.debtLimit1, vault1);
        feeMultiplier = 1e18 - params.fee;
    }

    // Owner functions

    /// @dev Call *after* installing as operator
    function configure() external {
        IERC20(asset0).approve(vault0, type(uint256).max);
        IERC20(asset1).approve(vault1, type(uint256).max);

        IEVC(evc).enableCollateral(myAccount, vault0);
        IEVC(evc).enableCollateral(myAccount, vault1);
    }

    // Swapper interface

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        callThroughEVC
        nonReentrant
    {
        // Optimistically send tokens

        if (amount0Out > 0) withdrawAssets(vault0, amount0Out, to);
        if (amount1Out > 0) withdrawAssets(vault1, amount1Out, to);

        // Invoke callback

        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(_msgSender(), amount0Out, amount1Out, data);

        // Deposit all available funds, adjust received amounts downward to collect fees

        uint256 amount0In = IERC20(asset0).balanceOf(address(this));
        if (amount0In > 0) {
            depositAssets(vault0, amount0In);
            amount0In = amount0In * feeMultiplier / 1e18;
        }

        uint256 amount1In = IERC20(asset1).balanceOf(address(this));
        if (amount1In > 0) {
            depositAssets(vault1, amount1In);
            amount1In = amount1In * feeMultiplier / 1e18;
        }

        // Verify curve invariant is satisified

        {
            uint256 newReserve0 = reserve0 + amount0In - amount0Out;
            uint256 newReserve1 = reserve1 + amount1In - amount1Out;

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, Overflow());
            verify(newReserve0, newReserve1);

            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);
        }
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, locked);
    }

    function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256) {
        return _computeQuote(tokenIn, tokenOut, amountIn, true);
    }

    function quoteExactOutput(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256) {
        return _computeQuote(tokenIn, tokenOut, amountOut, false);
    }

    // Internal utilities

    function myDebt(address vault) internal view returns (uint256) {
        return IEVault(vault).debtOf(myAccount);
    }

    function myBalance(address vault) internal view returns (uint256) {
        uint256 shares = IEVault(vault).balanceOf(myAccount);
        return shares == 0 ? 0 : IEVault(vault).convertToAssets(shares);
    }

    function offsetReserve(uint112 reserve, address vault) internal view returns (uint112) {
        uint256 offset;
        uint256 debt = myDebt(vault);

        if (debt != 0) {
            offset = reserve > debt ? reserve - debt : 0;
        } else {
            offset = reserve + myBalance(vault);
        }

        require(offset <= type(uint112).max, Overflow());
        return uint112(offset);
    }

    function withdrawAssets(address vault, uint256 amount, address to) internal {
        uint256 balance = myBalance(vault);

        if (balance > 0) {
            uint256 avail = amount < balance ? amount : balance;
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IERC4626.withdraw, (avail, to, myAccount)));
            amount -= avail;
        }

        if (amount > 0) {
            IEVC(evc).enableController(myAccount, vault);
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IBorrowing.borrow, (amount, to)));
        }
    }

    function depositAssets(address vault, uint256 amount) internal {
        IEVault(vault).deposit(amount, myAccount);

        uint256 debt = myDebt(vault);

        if (debt > 0) {
            IEVC(evc).call(
                vault, myAccount, 0, abi.encodeCall(IBorrowing.repayWithShares, (type(uint256).max, myAccount))
            );

            if (debt <= amount) {
                IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }
    }

    function _computeQuote(address tokenIn, address tokenOut, uint256 amount, bool exactIn)
        internal
        view
        returns (uint256)
    {
        // exactIn: decrease received amountIn, rounding down
        if (exactIn) amount = amount * feeMultiplier / 1e18;

        bool asset0IsInput;
        if (tokenIn == asset0 && tokenOut == asset1) asset0IsInput = true;
        else if (tokenIn == asset1 && tokenOut == asset0) asset0IsInput = false;
        else revert UnsupportedPair();

        uint256 quote = computeQuote(amount, exactIn, asset0IsInput);

        require(quote <= (asset0IsInput ? reserve1 : reserve0), InsufficientReserves());
        require(
            quote <= IERC20(asset0IsInput ? asset1 : asset0).balanceOf(asset0IsInput ? vault1 : vault0),
            InsufficientCash()
        );

        // exactOut: increase required amountIn, rounding up
        if (!exactIn) quote = (quote * 1e18 + (feeMultiplier - 1)) / feeMultiplier;

        return quote;
    }

    // To be implemented by sub-class

    function verify(uint256 newReserve0, uint256 newReserve1) internal view virtual;

    function computeQuote(uint256 amount, bool exactIn, bool asset0IsInput) internal view virtual returns (uint256);
}
