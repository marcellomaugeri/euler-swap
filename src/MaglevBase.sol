// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Ownable, Context} from "openzeppelin-contracts/access/Ownable.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IERC20, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";
import {IUniswapV2Callee} from "./interfaces/IUniswapV2Callee.sol";

abstract contract MaglevBase is EVCUtil, Ownable {
    address public immutable vault0;
    address public immutable vault1;
    address public immutable asset0;
    address public immutable asset1;
    address public immutable myAccount;

    uint112 public reserve0;
    uint112 public reserve1;
    uint32 private locked;

    modifier nonReentrant() {
        require(locked == 0, "reentrancy");
        locked = 1;
        _;
        locked = 0;
    }

    function _msgSender() internal view override(Context, EVCUtil) returns (address) {
        return EVCUtil._msgSender();
    }

    struct Params {
        address evc;
        address vault0;
        address vault1;
        address myAccount;
    }

    constructor(Params memory params) EVCUtil(params.evc) Ownable(msg.sender) {
        vault0 = params.vault0;
        vault1 = params.vault1;
        asset0 = IEVault(vault0).asset();
        asset1 = IEVault(vault1).asset();
        myAccount = params.myAccount;
    }

    /// @dev Call *after* installing as operator
    function configure(uint112 _reserve0, uint112 _reserve1) external onlyOwner {
        reserve0 = _reserve0;
        reserve1 = _reserve1;

        IERC20(asset0).approve(vault0, type(uint256).max);
        IERC20(asset1).approve(vault1, type(uint256).max);

        IEVC(evc).enableCollateral(myAccount, vault0);
        IEVC(evc).enableCollateral(myAccount, vault1);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data)
        external
        callThroughEVC
        nonReentrant
    {
        // Optimistically send tokens

        if (amount0Out > 0) withdrawAssets(vault0, amount0Out, to);
        if (amount1Out > 0) withdrawAssets(vault1, amount1Out, to);

        // Invoke callback

        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);

        // Deposit all available funds

        uint256 amount0In = IERC20(asset0).balanceOf(address(this));
        uint256 amount1In = IERC20(asset1).balanceOf(address(this));
        if (amount0In > 0) depositAssets(vault0, amount0In);
        if (amount1In > 0) depositAssets(vault1, amount1In);

        // Verify curve invariant is satisified

        {
            uint256 oldReserve0 = reserve0;
            uint256 oldReserve1 = reserve1;
            uint256 newReserve0 = oldReserve0 + amount0In - amount0Out;
            uint256 newReserve1 = oldReserve1 + amount1In - amount1Out;

            require(newReserve0 <= type(uint112).max && newReserve1 <= type(uint112).max, "overflow");
            verify(oldReserve0, oldReserve1, amount0In, amount1In, newReserve0, newReserve1);

            reserve0 = uint112(newReserve0);
            reserve1 = uint112(newReserve1);
        }
    }

    function withdrawAssets(address vault, uint256 amount, address to) internal {
        uint256 balance;
        {
            uint256 shares = IEVault(vault).balanceOf(myAccount);
            balance = shares == 0 ? 0 : IEVault(vault).convertToAssets(shares);
        }

        if (balance > 0) {
            uint256 a = amount < balance ? amount : balance;
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IERC4626.withdraw, (a, to, myAccount)));
            amount -= a;
        }

        if (amount > 0) {
            IEVC(evc).enableController(myAccount, vault);
            IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IBorrowing.borrow, (amount, to)));
        }
    }

    function depositAssets(address vault, uint256 amount) internal {
        IEVault(vault).deposit(amount, myAccount);

        uint256 debt = IEVault(vault).debtOf(myAccount);

        if (debt > 0) {
            IEVC(evc).call(
                vault, myAccount, 0, abi.encodeCall(IBorrowing.repayWithShares, (type(uint256).max, myAccount))
            );

            if (debt <= amount) {
                IEVC(evc).call(vault, myAccount, 0, abi.encodeCall(IRiskManager.disableController, ()));
            }
        }
    }

    // Verification implemented by sub-class

    function verify(
        uint256 oldReserve0,
        uint256 oldReserve1,
        uint256 amount0In,
        uint256 amount1In,
        uint256 newReserve0,
        uint256 newReserve1
    ) internal view virtual;
}
