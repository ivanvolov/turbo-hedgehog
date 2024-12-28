// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** v4 imports
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";

// ** contracts
import {ERC721} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {BaseStrategyHook} from "@src/core/BaseStrategyHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

interface ILendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract SRebalanceAdapter is Ownable {
    using PRBMathUD60x18 for uint256;
    error NoRebalanceNeeded();
    error NotALM();

    ILendingAdapter public lendingAdapter;
    IALM public alm;

    uint160 public sqrtPriceLastRebalance;

    int24 public tickDeltaThreshold = 2000;

    IERC20 WETH = IERC20(ALMBaseLib.WETH);
    IERC20 USDC = IERC20(ALMBaseLib.USDC);

    // aavev2
    address constant lendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    ILendingPool constant LENDING_POOL = ILendingPool(lendingPool);

    constructor() Ownable(msg.sender) {
        USDC.approve(lendingPool, type(uint256).max);
        WETH.approve(lendingPool, type(uint256).max);

        USDC.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        WETH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
    }

    function setALM(address _alm) external onlyOwner {
        alm = IALM(_alm);
    }

    function setSqrtPriceLastRebalance(uint160 _sqrtPriceLastRebalance) external onlyOwner {
        sqrtPriceLastRebalance = _sqrtPriceLastRebalance;
    }

    function setLendingAdapter(address _lendingAdapter) external onlyOwner {
        if (address(lendingAdapter) != address(0)) {
            WETH.approve(address(lendingAdapter), 0);
            USDC.approve(address(lendingAdapter), 0);
        }
        lendingAdapter = ILendingAdapter(_lendingAdapter);
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);
    }

    function setTickDeltaThreshold(int24 _tickDeltaThreshold) external onlyOwner {
        tickDeltaThreshold = _tickDeltaThreshold;
    }

    function isPriceRebalanceNeeded() public view returns (bool, int24) {
        // int24 tickLastRebalance = ALMMathLib.getTickFromSqrtPrice(sqrtPriceLastRebalance);
        // int24 tickCurrent = ALMMathLib.getTickFromSqrtPrice(alm.sqrtPriceCurrent());

        // int24 tickDelta = tickCurrent - tickLastRebalance;
        // tickDelta = tickDelta > 0 ? tickDelta : -tickDelta;

        // return (tickDelta > tickDeltaThreshold, tickDelta);
        return (true, 0);
    }

    function withdraw(uint256 deltaDebt, uint256 deltaCollateral) external {
        // if (msg.sender != address(alm)) revert NotALM();
        // address[] memory assets = new address[](1);
        // uint256[] memory amounts = new uint256[](1);
        // uint256[] memory modes = new uint256[](1);
        // (assets[0], amounts[0], modes[0]) = (address(USDC), deltaDebt, 0);
        // LENDING_POOL.flashLoan(address(this), assets, amounts, modes, address(this), abi.encode(deltaCollateral), 0);
    }

    function rebalance(uint256 slippage) external onlyOwner {
        (bool isRebalance, ) = isPriceRebalanceNeeded();
        if (!isRebalance) revert NoRebalanceNeeded();
        alm.refreshReserves();

        uint256 tvl = alm.TVL();
        uint256 weight = alm.weight();
        uint256 longLeverage = alm.longLeverage();
        uint256 shortLeverage = alm.shortLeverage();
        uint256 price = IOracle(alm.oracle()).price();

        uint256 currentCL = lendingAdapter.getCollateralLong();
        uint256 currentCS = lendingAdapter.getCollateralShort();
        uint256 currentDL = lendingAdapter.getBorrowedLong();
        uint256 currentDS = lendingAdapter.getBorrowedShort();

        uint256 targetCL = tvl.mul(weight).mul(longLeverage);
        uint256 targetCS = tvl.mul(1 - weight).mul(price).mul(shortLeverage);
        uint256 targetDL = currentCL.mul(price).mul(1e18 - uint256(1e18).div(longLeverage));
        uint256 targetDS = currentCS.mul(1e18 - uint256(1e18).div(shortLeverage)).div(price);

        int256 k = (1e18 + int256(slippage));

        int256 deltaCL = (int256(targetCL - currentCL) * k) / 1e18;
        int256 deltaCS = (int256(targetCS - currentCS) * k) / 1e18;
        int256 deltaDL = (int256(targetDL - currentDL) * k) / 1e18;
        int256 deltaDS = (int256(targetDS - currentDS) * k) / 1e18;

        uint256 ethToFl;
        uint256 usdcToFl;
        if (deltaCL > 0) ethToFl += uint256(deltaCL);
        if (deltaCS > 0) usdcToFl += uint256(deltaCS);
        if (deltaDL < 0) usdcToFl += uint256(-deltaDL);
        if (deltaDS < 0) ethToFl += uint256(-deltaDS);

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        (assets[0], amounts[0], modes[0]) = (address(WETH), ethToFl, 0);
        (assets[1], amounts[1], modes[1]) = (address(USDC), usdcToFl, 0);
        LENDING_POOL.flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            abi.encode(slippage, deltaCL, deltaCS, deltaDL, deltaDS, targetDL, targetDS),
            0
        );

        // ** Check max deviation

        price = IOracle(alm.oracle()).price();
        currentCL = lendingAdapter.getCollateralLong();
        currentDL = lendingAdapter.getBorrowedLong();
        currentCS = lendingAdapter.getCollateralShort();
        currentDS = lendingAdapter.getBorrowedShort();

        {
            uint256 _longLeverage = (currentCL.mul(price)).div(currentCL.mul(price) - currentDL);
            uint256 _shortLeverage = currentCS.div(currentCS - currentDS.mul(price));

            require(ALMMathLib.abs(int256(longLeverage) - int256(_longLeverage)) <= 1e17, "D1");
            require(ALMMathLib.abs(int256(shortLeverage) - int256(_shortLeverage)) <= 1e17, "D2");
        }

        sqrtPriceLastRebalance = alm.sqrtPriceCurrent();
        alm.updateBoundaries();
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata data
    ) external returns (bool) {
        require(msg.sender == lendingPool, "M0");

        (
            uint256 slippage,
            int256 deltaCL,
            int256 deltaCS,
            int256 deltaDL,
            int256 deltaDS,
            uint256 targetDL,
            uint256 targetDS
        ) = abi.decode(data, (uint256, int256, int256, int256, int256, uint256, uint256));
        uint256 k = (1e18 + slippage);

        if (deltaCL > 0) lendingAdapter.addCollateralLong(uint256(deltaCL));
        else if (deltaCL < 0) lendingAdapter.removeCollateralLong(uint256(-deltaCL));

        if (deltaCS > 0) lendingAdapter.addCollateralShort(uint256(deltaCS));
        else if (deltaCS < 0) lendingAdapter.removeCollateralShort(uint256(-deltaCS));

        if (deltaDL < 0) lendingAdapter.repayLong(uint256(-deltaDL));
        if (deltaDS < 0) lendingAdapter.repayShort(uint256(-deltaDS));

        if (deltaDL != 0) lendingAdapter.borrowLong(targetDL.mul(k) - lendingAdapter.getBorrowedLong());
        if (deltaDS != 0) lendingAdapter.borrowShort(targetDS.mul(k) - lendingAdapter.getBorrowedShort());

        // ** Flash loan management

        if (amounts[0] + premiums[0] > WETH.balanceOf(address(this))) {
            // here is modified 6.a
        }
        uint256 extraETH = amounts[0] + premiums[0] - WETH.balanceOf(address(this));

        if (extraETH > 0) ALMBaseLib.swapExactInput(address(WETH), address(USDC), extraETH);

        uint256 extraUSDC = amounts[1] + premiums[1] - USDC.balanceOf(address(this));
        if (extraUSDC > 0) lendingAdapter.repayLong(extraUSDC);
        return true;
    }
}
