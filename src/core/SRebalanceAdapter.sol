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
import {ILendingPool} from "@src/interfaces/IAave.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";

contract SRebalanceAdapter is Ownable, IRebalanceAdapter {
    using PRBMathUD60x18 for uint256;
    error NoRebalanceNeeded();
    error NotALM();

    ILendingAdapter public lendingAdapter;
    IALM public alm;

    uint160 public sqrtPriceAtLastRebalance;
    uint256 public timeAtLastRebalance;

    IERC20 WETH = IERC20(ALMBaseLib.WETH);
    IERC20 USDC = IERC20(ALMBaseLib.USDC);

    // AaveV2
    address constant lendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    ILendingPool constant LENDING_POOL = ILendingPool(lendingPool);

    // ** Parameters
    int24 public tickDeltaThreshold = 2000;
    uint256 public rebalanceTimeThreshold = 2000;
    uint256 public weight = 6 * 1e17; // 0.6%
    uint256 public longLeverage = 3 * 1e18;
    uint256 public shortLeverage = 2 * 1e18;
    uint256 public maxDeviationLong = 1e16; // 0.01%
    uint256 public maxDeviationShort = 1e16; // 0.01%
    bool public invertAssets = false;

    constructor() Ownable(msg.sender) {
        USDC.approve(lendingPool, type(uint256).max);
        WETH.approve(lendingPool, type(uint256).max);

        USDC.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        WETH.approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
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

    function setALM(address _alm) external onlyOwner {
        alm = IALM(_alm);
    }

    function setTickDeltaThreshold(int24 _tickDeltaThreshold) external onlyOwner {
        tickDeltaThreshold = _tickDeltaThreshold;
    }

    function setSqrtPriceAtLastRebalance(uint160 _sqrtPriceAtLastRebalance) external onlyOwner {
        sqrtPriceAtLastRebalance = _sqrtPriceAtLastRebalance;
    }

    function setTimeAtLastRebalance(uint256 _timeAtLastRebalance) external onlyOwner {
        timeAtLastRebalance = _timeAtLastRebalance;
    }

    function setRebalanceTimeThreshold(uint256 _rebalanceTimeThreshold) external onlyOwner {
        rebalanceTimeThreshold = _rebalanceTimeThreshold;
    }

    function setWeight(uint256 _weight) external onlyOwner {
        weight = _weight;
    }

    function setLongLeverage(uint256 _longLeverage) external onlyOwner {
        longLeverage = _longLeverage;
    }

    function setShortLeverage(uint256 _shortLeverage) external onlyOwner {
        shortLeverage = _shortLeverage;
    }

    function setMaxDeviationLong(uint256 _maxDeviationLong) external onlyOwner {
        maxDeviationLong = _maxDeviationLong;
    }

    function setMaxDeviationShort(uint256 _maxDeviationShort) external onlyOwner {
        maxDeviationShort = _maxDeviationShort;
    }

    function setIsInvertAssets(bool _isInvertAssets) external onlyOwner {
        invertAssets = _isInvertAssets;
    }

    // ** Logic

    function isRebalanceNeeded() public view returns (bool, int24, uint256) {
        (bool _isPriceRebalance, int24 tickDelta) = isPriceRebalance();
        (bool _isTimeRebalance, uint256 auctionTriggerTime) = isTimeRebalance();

        return (_isPriceRebalance || _isTimeRebalance, tickDelta, auctionTriggerTime);
    }

    function isPriceRebalance() public view returns (bool, int24) {
        int24 tickLastRebalance = ALMMathLib.getTickFromSqrtPrice(sqrtPriceAtLastRebalance);
        int24 tickCurrent = ALMMathLib.getTickFromSqrtPrice(alm.sqrtPriceCurrent());

        int24 tickDelta = tickCurrent - tickLastRebalance;
        tickDelta = tickDelta > 0 ? tickDelta : -tickDelta;

        return (tickDelta > tickDeltaThreshold, tickDelta);
    }

    function isTimeRebalance() public view returns (bool, uint256) {
        uint256 auctionTriggerTime = timeAtLastRebalance + rebalanceTimeThreshold;

        return (block.timestamp >= auctionTriggerTime, auctionTriggerTime);
    }

    function rebalance(uint256 slippage) external onlyOwner {
        (bool isRebalance, , ) = isRebalanceNeeded();
        if (!isRebalance) revert NoRebalanceNeeded();
        alm.refreshReserves();

        (uint256 ethToFl, uint256 usdcToFl, bytes memory data) = rebalanceCalculations(1e18 + int256(slippage));

        address[] memory assets = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes = new uint256[](2);
        (assets[0], amounts[0], modes[0]) = (address(WETH), ethToFl, 0);
        (assets[1], amounts[1], modes[1]) = (address(USDC), ALMBaseLib.c18to6(usdcToFl), 0);
        // console.log("ethToFl", ethToFl);
        // console.log("usdcToFl", usdcToFl);
        LENDING_POOL.flashLoan(address(this), assets, amounts, modes, address(this), data, 0);

        // ** Check max deviation
        checkDeviations();

        // Update state
        sqrtPriceAtLastRebalance = alm.sqrtPriceCurrent();
        alm.updateBoundaries();
        timeAtLastRebalance = block.timestamp;
    }

    function checkDeviations() internal view {
        uint256 price = IOracle(alm.oracle()).price();
        uint256 currentCL = lendingAdapter.getCollateralLong();
        uint256 currentCS = lendingAdapter.getCollateralShort();

        uint256 _longLeverage = (currentCL.mul(price)).div(currentCL.mul(price) - lendingAdapter.getBorrowedLong());
        uint256 _shortLeverage = currentCS.div(currentCS - lendingAdapter.getBorrowedShort().mul(price));

        // console.log("longLeverage %s", _longLeverage);
        // console.log("shortLeverage %s", _shortLeverage);

        require(_longLeverage - longLeverage <= 1e17, "D1");
        require(_shortLeverage - shortLeverage <= 1e17, "D2");
    }

    // @Notice: this function is mainly for removing stack too deep error
    function rebalanceCalculations(
        int256 k
    ) internal view returns (uint256 ethToFl, uint256 usdcToFl, bytes memory data) {
        // console.log("> rebalanceCalculations");
        // console.log("k %s", k);
        uint256 targetDL;
        uint256 targetDS;

        int256 deltaCL;
        int256 deltaCS;
        int256 deltaDL;
        int256 deltaDS;
        {
            // console.log("price %s", IOracle(alm.oracle()).price());
            // console.log("currentCL", lendingAdapter.getCollateralLong());
            // console.log("currentCS", lendingAdapter.getCollateralShort());
            // console.log("currentDL", lendingAdapter.getBorrowedLong());
            // console.log("currentDS", lendingAdapter.getBorrowedShort());

            uint256 targetCL;
            uint256 targetCS;
            uint256 price = IOracle(alm.oracle()).price();
            if (invertAssets) {
                targetCL = alm.TVL().mul(weight).mul(longLeverage).div(price);
                targetCS = alm.TVL().mul(1e18 - weight).mul(shortLeverage);

                targetDL = targetCL.mul(price).mul(1e18 - uint256(1e18).div(longLeverage));
                targetDS = targetCS.div(price).mul(1e18 - uint256(1e18).div(shortLeverage));
            } else {
                targetCL = alm.TVL().mul(weight).mul(longLeverage);
                targetCS = alm.TVL().mul(1e18 - weight).mul(shortLeverage).mul(price);

                targetDL = targetCL.mul(price).mul(1e18 - uint256(1e18).div(longLeverage));
                targetDS = targetCS.div(price).mul(1e18 - uint256(1e18).div(shortLeverage));
            }

            // console.log("targetCL", targetCL);
            // console.log("targetCS", targetCS);
            // console.log("targetDL", targetDL);
            // console.log("targetDS", targetDS);

            deltaCL = (int256(targetCL - lendingAdapter.getCollateralLong()));
            deltaCS = (int256(targetCS - lendingAdapter.getCollateralShort()));
            deltaDL = (int256(targetDL - lendingAdapter.getBorrowedLong()));
            deltaDS = (int256(targetDS - lendingAdapter.getBorrowedShort()));

            // console.log("deltaCL", deltaCL);
            // console.log("deltaCS", deltaCS);
            // console.log("deltaDL", deltaDL);
            // console.log("deltaDS", deltaDS);
        }

        if (deltaCL > 0) ethToFl += uint256(deltaCL);
        if (deltaCS > 0) usdcToFl += uint256(deltaCS);
        if (deltaDL < 0) usdcToFl += uint256(-deltaDL);
        if (deltaDS < 0) ethToFl += uint256(-deltaDS);

        data = abi.encode(
            deltaCL,
            deltaCS,
            deltaDL,
            deltaDS,
            uint256(targetDL).mul(uint256(k)),
            uint256(targetDS).mul(uint256(k))
        );
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata data
    ) external returns (bool) {
        // console.log("executeOperation");
        require(msg.sender == lendingPool, "M0");
        _positionManagement(data);

        // console.log("afterCL %s", lendingAdapter.getCollateralLong());
        // console.log("afterCS %s", lendingAdapter.getCollateralShort());
        // console.log("afterDL %s", lendingAdapter.getBorrowedLong());
        // console.log("afterDS %s", lendingAdapter.getBorrowedShort());

        uint256 borrowedWETH = amounts[0] + premiums[0];
        uint256 borrowedUSDC = ALMBaseLib.c6to18(amounts[1] + premiums[1]);
        // ** Flash loan management

        // console.log("premium0 %s", premiums[0]);
        // console.log("premium1 %s", premiums[1]);

        // console.log("borrowedWETH %s", borrowedWETH);
        // console.log("wethBalance %s", ALMBaseLib.wethBalance(address(this)));

        // console.log("borrowedUSDC %s", borrowedUSDC);
        // console.log("usdcBalance %s", ALMBaseLib.usdcBalance(address(this)));

        // console.log("borrowedWETH %s", borrowedWETH);

        if (borrowedWETH > ALMBaseLib.wethBalance(address(this))) {
            // console.log("I want to get eth", borrowedWETH - ALMBaseLib.wethBalance(address(this)));
            // console.log("I have USDC", ALMBaseLib.usdcBalance(address(this)));
            ALMBaseLib.swapExactOutput(
                address(USDC),
                address(WETH),
                borrowedWETH - ALMBaseLib.wethBalance(address(this))
            );
        }

        if (borrowedWETH > ALMBaseLib.wethBalance(address(this)))
            ALMBaseLib.swapExactInput(
                address(WETH),
                address(USDC),
                borrowedWETH - ALMBaseLib.wethBalance(address(this))
            );
        // console.log("here2");
        if (borrowedUSDC > ALMBaseLib.usdcBalance(address(this)))
            lendingAdapter.repayLong(borrowedUSDC - ALMBaseLib.usdcBalance(address(this)));
        // console.log("here3");
        return true;
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _positionManagement(bytes calldata data) internal {
        (int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS, uint256 _targetDL, uint256 _targetDS) = abi
            .decode(data, (int256, int256, int256, int256, uint256, uint256));

        if (deltaCL > 0) lendingAdapter.addCollateralLong(uint256(deltaCL));
        else if (deltaCL < 0) lendingAdapter.removeCollateralLong(uint256(-deltaCL));

        if (deltaCS > 0) lendingAdapter.addCollateralShort(uint256(deltaCS));
        else if (deltaCS < 0) lendingAdapter.removeCollateralShort(uint256(-deltaCS));

        if (deltaDL < 0) lendingAdapter.repayLong(uint256(-deltaDL));
        if (deltaDS < 0) lendingAdapter.repayShort(uint256(-deltaDS));

        if (deltaDL != 0) lendingAdapter.borrowLong(_targetDL - lendingAdapter.getBorrowedLong());
        if (deltaDS != 0) lendingAdapter.borrowShort(_targetDS - lendingAdapter.getBorrowedShort());
    }
}
