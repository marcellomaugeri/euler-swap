// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EVaultTestBase, TestERC20, IRMTestDefault} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVault, IRiskManager} from "evk/EVault/IEVault.sol";
import {IEulerSwap, IEVC, EulerSwap} from "../../src/EulerSwap.sol";
import {EulerSwapFactory} from "../../src/EulerSwapFactory.sol";
import {EulerSwapPeriphery} from "../../src/EulerSwapPeriphery.sol";
import {IPoolManager, PoolManagerDeployer} from "../utils/PoolManagerDeployer.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {MetaProxyDeployer} from "../../src/utils/MetaProxyDeployer.sol";


struct AssetConfig {
    string name;
    string symbol;
    uint8 decimals;
    uint256 initialPrice;
}

contract EulerSwapTestBase is EVaultTestBase {
    uint256 public constant MAX_QUOTE_ERROR = 2;

    address public depositor = makeAddr("depositor"); // Someone who deposits into the vaults
    address public holder = makeAddr("holder"); // The owner of the EulerSwap
    address public recipient = makeAddr("recipient"); // The recipient of a swap operation
    address public anyone = makeAddr("anyone");

    //TestERC20 assetTST3;
    //IEVault public eTST3;
    TestERC20[] public tokens;
    IEVault[] public vaults;
    EulerSwap public eulerSwap;

    address public eulerSwapImpl;
    IPoolManager public poolManager;
    EulerSwapFactory public eulerSwapFactory;
    EulerSwapPeriphery public periphery;

    uint256 currSalt = 0;
    address installedOperator;

    modifier monotonicHolderNAV() {
        int256 orig = getHolderNAV();
        _;
        assertGe(getHolderNAV(), orig);
    }

    function deployEulerSwap(address poolManager_) public {
        eulerSwapImpl = address(new EulerSwap(address(evc), poolManager_));
        eulerSwapFactory =
            new EulerSwapFactory(address(evc), address(factory), eulerSwapImpl, address(this), address(this));
        periphery = new EulerSwapPeriphery();
    }

    function removeInstalledOperator() public {
        if (installedOperator == address(0)) return;

        vm.prank(holder);
        evc.setAccountOperator(holder, installedOperator, false);

        installedOperator = address(0);
    }

    // Update the price of asset and vault in the oracle by index
    function updatePrice(uint256 index, uint256 price) public {
        require(index < tokens.length, "Index out of bounds");
        require(index < vaults.length, "Index out of bounds");
        oracle.setPrice(address(tokens[index]), unitOfAccount, price);
        oracle.setPrice(address(vaults[index]), unitOfAccount, price);
    }

    function setUp() public virtual override {
        super.setUp();
            poolManager = PoolManagerDeployer.deploy(address(this));

        oracle.setPrice(unitOfAccount, unitOfAccount, 1e18);
        deployEulerSwap(address(0)); 

        string memory configJson = vm.readFile("test/poc/config.json");
        // 1. Define the struct layout for the parser
        string memory typeDescription = "AssetConfig(string name,string symbol,uint8 decimals,uint256 initialPrice)";
        // 2. Parse the JSON array into ABI-encoded bytes
        bytes memory assetConfigsBytes = vm.parseJsonTypeArray(configJson, ".assets", typeDescription);
        // 3. Decode the bytes into a usable struct array
        AssetConfig[] memory assetConfigs = abi.decode(assetConfigsBytes, (AssetConfig[]));
        // 4. Create the assets and vaults based on the parsed configuration
        for (uint i = 0; i < assetConfigs.length; i++) {
            string memory assetName = assetConfigs[i].name;
            string memory assetSymbol = assetConfigs[i].symbol;
            uint8 assetDecimals = assetConfigs[i].decimals;
            uint256 assetInitialPrice = assetConfigs[i].initialPrice;

            // Debug
            console.log("Creating asset:", assetName, assetSymbol, assetDecimals);

            // Create asset
            TestERC20 asset = new TestERC20(assetName, assetSymbol, assetDecimals, false);
            tokens.push(asset);

            // Create vault
            IEVault vault = IEVault(
                factory.createProxy(address(0), true, abi.encodePacked(address(asset), address(oracle), unitOfAccount))
            );
            vault.setHookConfig(address(0), 0);
            vaults.push(vault);
            vault.setInterestRateModel(address(new IRMTestDefault()));
            vault.setMaxLiquidationDiscount(0.2e4);
            vault.setFeeReceiver(feeReceiver);

            // Set LTV to 93%
            vault.setLTV(address(asset), 0.93e4, 0.93e4, 0);

            console.log("Created vault:", address(vault));

            // Set the price
            updatePrice(i, assetInitialPrice);

            // Debug all the informations:
            console.log("Created asset:");
            console.log("  Address: %s", address(asset));
            console.log("  Name: %s", assetName);
            console.log("  Symbol: %s", assetSymbol);
            console.log("  Decimals: %s", uint256(assetDecimals));
            console.log("Created vault:");
            console.log("  Vault Address: %s", address(vault));
            console.log("  Asset Address: %s", address(asset));
            console.log("  Initial Price: %s", assetInitialPrice);

        }

        // Set the LTV between vaults
        vaults[0].setLTV(address(vaults[1]), 0.93e4, 0.93e4, 0);
        vaults[1].setLTV(address(vaults[0]), 0.93e4, 0.93e4, 0);

        // ======================= EulerSwap Setup =======================
        // 1. Get the parameters to send in the createEulerSwap, excluding the address reserves which will be assets[0] and assets[1]
        string memory createEulerSwapParamsTypeDescription =
            "EulerSwapConfig(uint112 reserve0, uint112 reserve1, uint256 fee, uint256 px, uint256 py, uint256 cx, uint256 cy)";

        // 2. Parse the JSON array into ABI-encoded bytes
        bytes memory eulerSwapParamsBytes = vm.parseJsonType(configJson, ".eulerSwap", createEulerSwapParamsTypeDescription);

        // 3. Extract the parameters from the bytes
       (uint112 reserve0, uint112 reserve1, uint256 fee, uint256 px, uint256 py, uint256 cx, uint256 cy) =
            abi.decode(eulerSwapParamsBytes, (uint112, uint112, uint256, uint256, uint256, uint256, uint256));

        // Debug, print the variables
        console.log("Before creating EulerSwap:");
        console.log("reserve0:", reserve0);
        console.log("reserve1:", reserve1);
        console.log("fee:", fee);
        console.log("px:", px);
        console.log("py:", py);
        console.log("cx:", cx);
        console.log("cy:", cy);

        // px is the price of USDC, so it must be converted to the 18-decimal format
        px = px * 1e12;

        // 3. Create the EulerSwap instance on behalf of the holder
        eulerSwap = createEulerSwapHook(
            address(vaults[0]),
            address(vaults[1]),
            reserve0,
            reserve1,
            fee,
            px,
            py,
            cx,
            cy
        );


        // Deposit initial liquidity into the vaults
        mintAndDeposit(depositor, vaults[0], 200_000_000e6);  // 200M USDC
        mintAndDeposit(depositor, vaults[1], 100_000e18);      // 100k WSTETH (~$218M)

        // Deposit some collateral
        mintAndDeposit(holder, vaults[0], 10_000e6);

        // Enable vault as collateral in EVC so the holder can borrow

        //vm.startPrank(holder);
        //evc.enableCollateral(holder, address(vaults[0]));
        //evc.enableController(holder, address(vaults[0]));
        //vaults[0].borrow(100_000e6, holder);
        //vm.stopPrank();

        // Deposit the holder's assets into the vaults
        //mintAndDeposit(holder, vaults[0], 10e18);
        ///mintAndDeposit(holder, vaults[1], 10e18);

        // Set the hooks
        /*for (uint i = 0; i < vaults.length; i++) {
            vaults[i].setHookConfig(address(eulerSwap), 0);
        }*/

    }

    function skimAll(EulerSwap ml, bool order) public {
        if (order) {
            runSkimAll(ml, true);
            runSkimAll(ml, false);
        } else {
            runSkimAll(ml, false);
            runSkimAll(ml, true);
        }
    }

    /// @notice Reinstalls the EulerSwap operator by deploying a new contract with updated parameters.
    /// @dev EulerSwap operator parameters are immutable. Any change requires deploying a new contract.
    /// This function handles the full lifecycle: uninstalls the old operator, deploys the new one with
    /// the specified parameters while preserving reserves, and authorizes the new operator.
    function reinstallOperator(
        IEulerSwap oldOperator,
        uint256 newPx,
        uint256 newPy,
        uint256 newCx,
        uint256 newCy
    ) public returns (IEulerSwap newOperator) {
        vm.prank(holder);
        evc.setAccountOperator(holder, address(periphery), true);

        // 1. Get old params and reserves
        IEulerSwap.Params memory oldParams = oldOperator.getParams();
        (uint112 r0, uint112 r1,) = oldOperator.getReserves();

        // 2. Uninstall old operator -> no needed, since there is already in the code when I deploy
        //vm.prank(holder);
        //evc.setAccountOperator(holder, address(oldOperator), false);

        // 3. Configure new params
        IEulerSwap.Params memory newParams = oldParams;
        newParams.priceX = newPx;
        newParams.priceY = newPy;
        newParams.concentrationX = newCx;
        newParams.concentrationY = newCy;

        // 4. Configure initial state
        //IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({currReserve0: r0, currReserve1: r1});

        // 5. Create a new EulerSwap Hook:
        eulerSwap = createEulerSwapHook(
            oldParams.vault0,
            oldParams.vault1,
            r0,
            r1,
            oldParams.fee,
            newPx,
            newPy,
            newCx,
            newCy
        );

        // 6. Set new operator
        vm.prank(holder);
        evc.setAccountOperator(holder, address(eulerSwap), true);

        // 7. Update installedOperator for test tracking
        installedOperator = address(eulerSwap);

        return eulerSwap;
    }

    function getHolderNAV() public view returns (int256) {
        uint256 balance0 = vaults[0].convertToAssets(vaults[0].balanceOf(holder));
        uint256 debt0 = vaults[0].debtOf(holder);
        uint256 balance1 = vaults[1].convertToAssets(vaults[1].balanceOf(holder));
        uint256 debt1 = vaults[1].debtOf(holder);

        uint256 balValue = oracle.getQuote(balance0, address(tokens[0]), unitOfAccount)
            + oracle.getQuote(balance1, address(tokens[1]), unitOfAccount);
        uint256 debtValue = oracle.getQuote(debt0, address(tokens[0]), unitOfAccount)
            + oracle.getQuote(debt1, address(tokens[1]), unitOfAccount);

        return int256(balValue) - int256(debtValue);
    }

    function createEulerSwap(
        address vault0,
        address vault1,
        uint112 reserve0,
        uint112 reserve1,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) internal returns (EulerSwap) {
        IEulerSwap.Params memory params = getEulerSwapParams(vault0, vault1, reserve0, reserve1, px, py, cx, cy, fee, 0, address(0));
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({currReserve0: reserve0, currReserve1: reserve1});

        return createEulerSwapFull(params, initialState);

    }

    function createEulerSwapFull(
        IEulerSwap.Params memory params,
        IEulerSwap.InitialState memory initialState
    ) internal returns (EulerSwap) {
        removeInstalledOperator();

        bytes32 salt = bytes32(currSalt++);

        address predictedAddr = eulerSwapFactory.computePoolAddress(params, salt);

        vm.prank(holder);
        evc.setAccountOperator(holder, predictedAddr, true);
        installedOperator = predictedAddr;

        vm.prank(holder);
        eulerSwap = EulerSwap(eulerSwapFactory.deployPool(params, initialState, salt));

        return eulerSwap;
    }

    function createEulerSwapHook(
        address vault0,
        address vault1,
        uint112 reserve0,
        uint112 reserve1,
        uint256 fee,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy
    ) internal returns (EulerSwap) {

        // Get the fees from the periphery
        uint256 factoryProtocolFee = eulerSwapFactory.protocolFee();
        address factoryProtocolFeeRecipient = eulerSwapFactory.protocolFeeRecipient();

        console.log("factoryProtocolFee:", factoryProtocolFee);
        console.log("factoryProtocolFeeRecipient:", factoryProtocolFeeRecipient);

        // Construct the struct directly in this function to avoid a deep stack call.
        IEulerSwap.Params memory params = IEulerSwap.Params({
            vault0: vault0,
            vault1: vault1,
            eulerAccount: holder,
            equilibriumReserve0: reserve0,
            equilibriumReserve1: reserve1,
            priceX: px,
            priceY: py,
            concentrationX: cx,
            concentrationY: cy,
            fee: fee,
            protocolFee: factoryProtocolFee,
            protocolFeeRecipient: factoryProtocolFeeRecipient
        });
        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({currReserve0: reserve0, currReserve1: reserve1});
        return createEulerSwapHookFull(params, initialState);
    }

    function createEulerSwapHookFull(
        IEulerSwap.Params memory params,
        IEulerSwap.InitialState memory initialState
    ) internal returns (EulerSwap) {
        removeInstalledOperator();

        bytes memory creationCode = MetaProxyDeployer.creationCodeMetaProxy(eulerSwapImpl, abi.encode(params));
        (address predictedAddr, bytes32 salt) = HookMiner.find(
            address(eulerSwapFactory),
            uint160(
                Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.BEFORE_DONATE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
            ),
            creationCode
        );

        vm.prank(holder);
        evc.setAccountOperator(holder, predictedAddr, true);
        installedOperator = predictedAddr;

        vm.prank(holder);
        eulerSwap = EulerSwap(eulerSwapFactory.deployPool(params, initialState, salt));

        return eulerSwap;
    }

    function mintAndDeposit(address who, IEVault vault, uint256 amount) internal {
        TestERC20 tok = TestERC20(vault.asset());
        tok.mint(who, amount);

        vm.prank(who);
        tok.approve(address(vault), type(uint256).max);

        vm.prank(who);
        vault.deposit(amount, who);
    }

    function runSkimAll(EulerSwap ml, bool dir) internal returns (uint256) {
        uint256 skimmed = 0;
        uint256 val = 1;

        // Phase 1: Keep doubling skim amount until it fails

        while (true) {
            (uint256 amount0, uint256 amount1) = dir ? (val, uint256(0)) : (uint256(0), val);

            try ml.swap(amount0, amount1, address(0xDEAD), "") {
                skimmed += val;
                val *= 2;
            } catch {
                break;
            }
        }

        // Phase 2: Keep halving skim amount until 1 wei skim fails

        while (true) {
            if (val > 1) val /= 2;

            (uint256 amount0, uint256 amount1) = dir ? (val, uint256(0)) : (uint256(0), val);

            try ml.swap(amount0, amount1, address(0xDEAD), "") {
                skimmed += val;
            } catch {
                if (val == 1) break;
            }
        }

        return skimmed;
    }

    function getEulerSwapParams(
        address vault0,
        address vault1,
        uint112 reserve0,
        uint112 reserve1,
        uint256 px,
        uint256 py,
        uint256 cx,
        uint256 cy,
        uint256 fee,
        uint256 protocolFee,
        address protocolFeeRecipient
    ) internal view returns (EulerSwap.Params memory) {
        return IEulerSwap.Params({
            vault0: vault0,
            vault1: vault1,
            eulerAccount: holder,
            equilibriumReserve0: reserve0,
            equilibriumReserve1: reserve1,
            priceX: px,
            priceY: py,
            concentrationX: cx,
            concentrationY: cy,
            fee: fee,
            protocolFee: protocolFee,
            protocolFeeRecipient: protocolFeeRecipient
        });
    }

    function _getHealthFactor(address account, bool liquidation) internal view returns (uint256) {
        // It doesn't matter which vault we call this on; it's a system-wide check.
        try vaults[0].accountLiquidity(account, liquidation) returns (uint256 collateralValue, uint256 liabilityValue) {
            // If the call succeeds and there's no debt, health is infinite.
            console.log("Liability Value: ", liabilityValue);
            console.log("Collateral Value: ", collateralValue);        
            if (liabilityValue == 0) return type(uint256).max;
            // Otherwise, calculate health factor.
            return (collateralValue * 1e18) / liabilityValue;
        } catch {
            // The accountLiquidity function is known to revert when an account has no debt.
            // We will catch any revert from this function and assume it means the health factor is infinite.
            console.log("No debt found for account, returning max health factor.");
            return type(uint256).max;
        }
    }

    function logState(address ml) internal view {
        (uint112 reserve0, uint112 reserve1,) = EulerSwap(ml).getReserves();

        console.log("--------------------");
        console.log("Holder States:");
        console.log("  Vault[0] assets:  ", vaults[0].convertToAssets(vaults[0].balanceOf(holder)));
        console.log("  Vault[0] debt:    ", vaults[0].debtOf(holder));
        console.log("  Vault[1] assets: ", vaults[1].convertToAssets(vaults[1].balanceOf(holder)));
        console.log("  Vault[1] debt:   ", vaults[1].debtOf(holder));

        console.log("  Health Factor: ", _getHealthFactor(holder, true) / 1e18);

        console.log("  reserve0:           ", reserve0);
        console.log("  reserve1:           ", reserve1);
    }
}
