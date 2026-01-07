// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IUniswapV2Pair.sol";

/**
 * @title Uniswap V2 TWAP Oracle (Multi-Pair Support)
 * @dev 提供抗闪电贷攻击的时间加权平均价格（TWAP）
 *      支持多个交易对，标准实现：分离更新和查询逻辑
 *      - update(): 需要外部定期调用（建议使用 keeper）
 *      - consult(): 只读查询，可频繁调用
 */
contract UniswapV2TWAPOracle {
    uint32 public immutable period; // 观察窗口（秒）

    // 每个交易对的数据结构
    struct PairData {
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint32 blockTimestampLast;
        uint256 price0Average;
        uint256 price1Average;
        bool initialized;
    }

    // 映射：pair 地址 => 数据
    mapping(address => PairData) public pairs;

    // 事件
    event PriceUpdated(address indexed pair, uint256 twapPrice0, uint256 twapPrice1, uint32 window);

    error InvalidPeriod();
    error InvalidPair();
    error PairNotInitialized();
    error TooEarly();
    error Overflow();

    /**
     * @param _period 观察窗口（秒），建议 ≥ 900（15分钟）
     */
    constructor(uint32 _period) {
        if (_period == 0) revert InvalidPeriod();
        period = _period;
    }

    /// @notice 初始化交易对（首次使用前必须调用）
    /// @param pair Uniswap V2 Pair 地址
    function initialize(address pair) external {
        if (pair == address(0)) revert InvalidPair();
        PairData storage pairData = pairs[pair];
        if (pairData.initialized) return; // 已初始化则跳过

        IUniswapV2Pair _pair = IUniswapV2Pair(pair);
        (,, uint32 blockTimestamp) = _pair.getReserves();
        
        pairData.price0CumulativeLast = _pair.price0CumulativeLast();
        pairData.price1CumulativeLast = _pair.price1CumulativeLast();
        pairData.blockTimestampLast = blockTimestamp;
        pairData.initialized = true;
    }

    /// @notice 更新指定交易对的 TWAP 价格（需要外部定期调用，建议使用 keeper）
    /// @param pair Uniswap V2 Pair 地址
    /// @dev 需要等待至少 period 秒后才能调用
    function update(address pair) external {
        PairData storage pairData = pairs[pair];
        if (!pairData.initialized) revert PairNotInitialized();

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 timestamp) = 
            _currentCumulativePrices(pair);

        // 处理时间戳回绕
        if (timestamp < pairData.blockTimestampLast) {
            revert Overflow();
        }

        // 检查是否已积累足够时间
        uint32 timeElapsed = timestamp - pairData.blockTimestampLast;
        if (timeElapsed < period) {
            revert TooEarly();
        }

        // 计算 TWAP = Δcumulative / Δtime
        pairData.price0Average = (price0Cumulative - pairData.price0CumulativeLast) / timeElapsed;
        pairData.price1Average = (price1Cumulative - pairData.price1CumulativeLast) / timeElapsed;

        // 更新快照
        pairData.price0CumulativeLast = price0Cumulative;
        pairData.price1CumulativeLast = price1Cumulative;
        pairData.blockTimestampLast = timestamp;

        emit PriceUpdated(pair, pairData.price0Average, pairData.price1Average, timeElapsed);
    }

    /// @notice 批量更新多个交易对
    /// @param pairList 交易对地址数组
    function updateBatch(address[] calldata pairList) external {
        for (uint256 i = 0; i < pairList.length; i++) {
            if (pairs[pairList[i]].initialized) {
                update(pairList[i]);
            }
        }
    }

    /// @notice 查询指定交易对的 TWAP 价格（只读，可频繁调用）
    /// @param pair Uniswap V2 Pair 地址
    /// @return twapPrice0: token1/token0 的平均价格（UQ112.112 格式）
    /// @return twapPrice1: token0/token1 的平均价格（UQ112.112 格式）
    /// @dev 如果 update() 从未被调用或时间不足，返回 0
    function consult(address pair) external view returns (uint256 twapPrice0, uint256 twapPrice1) {
        PairData memory pairData = pairs[pair];
        return (pairData.price0Average, pairData.price1Average);
    }

    /// @notice 查询指定代币数量的输出（基于存储的平均价格）
    /// @param pair Uniswap V2 Pair 地址
    /// @param tokenIn 输入代币地址
    /// @param amountIn 输入数量
    /// @return amountOut 输出数量
    function consult(address pair, address tokenIn, uint256 amountIn) 
        external 
        view 
        returns (uint256 amountOut) 
    {
        PairData storage pairData = pairs[pair];
        IUniswapV2Pair _pair = IUniswapV2Pair(pair);
        address token0 = _pair.token0();
        
        if (tokenIn == token0) {
            // 使用 price1Average (token0/token1)
            amountOut = (pairData.price1Average * amountIn) >> 112;
        } else {
            // 使用 price0Average (token1/token0)
            amountOut = (pairData.price0Average * amountIn) >> 112;
        }
    }

    /// @dev 安全获取指定交易对的当前累计价格和时间戳
    function _currentCumulativePrices(address pair)
        private
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        IUniswapV2Pair _pair = IUniswapV2Pair(pair);
        blockTimestamp = uint32(block.timestamp % 2**32);
        price0Cumulative = _pair.price0CumulativeLast();
        price1Cumulative = _pair.price1CumulativeLast();

        // 如果自上次交易以来有时间流逝，需手动计算最新累计值
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = _pair.getReserves();

        if (blockTimestampLast != blockTimestamp && reserve0 > 0 && reserve1 > 0) {
            // 计算时间差
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            if (timeElapsed > 0) {
                // 当前瞬时价格（UQ112.112 格式）
                uint256 price0 = (uint256(reserve1) << 112) / reserve0;
                uint256 price1 = (uint256(reserve0) << 112) / reserve1;

                // 累加未计入的部分
                price0Cumulative += price0 * timeElapsed;
                price1Cumulative += price1 * timeElapsed;
            }
        }
    }

    /// @notice 检查交易对是否已初始化
    /// @param pair Uniswap V2 Pair 地址
    function isInitialized(address pair) external view returns (bool) {
        return pairs[pair].initialized;
    }
}
