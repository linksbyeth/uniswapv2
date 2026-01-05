#!/bin/bash

# Uniswap V2 移除流动性脚本（自动计算预期输出和滑点）
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== 配置参数 =====
RPC_URL="http://127.0.0.1:8545"
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ROUTER_ADDRESS="0x8f86403A4DE0BB5791fa46B8e795C547942fE4Cf"
TOKEN_0="0x2279b7a0a67db372996a5fab50d91eaa73d2ebe6"
TOKEN_1="0xa513e6e4b8f2a923d98304ec87f64353c4d5c853"
LIQUIDITY="1000000000000000000"  # 要移除的 LP 代币数量
SLIPPAGE_TOLERANCE="1"  # 滑点 1%
TO_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
DEADLINE=$(($(date +%s) + 3600))
GAS_PRICE="1000000000"
MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"

# ===== 工具函数 =====
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 提取纯数字（去掉科学计数法）
extract_number() {
    echo "$1" | awk '{print $1}' | grep -oE '^[0-9]+'
}

# 计算预期输出和最小值
calc_amounts() {
    local liquidity=$1 reserve=$2 total_supply=$3 slippage=$4
    python3 << EOF
liquidity = int('$liquidity')
reserve = int('$reserve')
total_supply = int('$total_supply')
slippage = int('$slippage')

amount_out = (liquidity * reserve) // total_supply
amount_min = (amount_out * (100 - slippage)) // 100
print(f"{amount_out},{amount_min}")
EOF
}

# ===== 主程序 =====
info "开始移除流动性"
info "配置: Token 0=$TOKEN_0, Token 1=$TOKEN_1, Liquidity=$LIQUIDITY, Slippage=$SLIPPAGE_TOLERANCE%"
echo ""

# 1. 获取 Pair 地址
info "查询 Pair 地址..."
FACTORY_ADDRESS=$(cast call "$ROUTER_ADDRESS" "factory()(address)" --rpc-url "$RPC_URL" 2>/dev/null || error "无法获取 Factory 地址")
PAIR_ADDRESS=$(cast call "$FACTORY_ADDRESS" "getPair(address,address)(address)" "$TOKEN_0" "$TOKEN_1" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0")
[ "$PAIR_ADDRESS" = "0x0" ] && error "Pair 不存在"
info "Pair: $PAIR_ADDRESS"

# 2. 检查 LP 余额
info "检查 LP 代币余额..."
LP_BALANCE=$(extract_number "$(cast call "$PAIR_ADDRESS" "balanceOf(address)(uint256)" "$TO_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")")
[ "$LP_BALANCE" = "0" ] && error "LP 代币余额不足"
[ ${#LP_BALANCE} -lt ${#LIQUIDITY} ] || ([ ${#LP_BALANCE} -eq ${#LIQUIDITY} ] && [ "$LP_BALANCE" \< "$LIQUIDITY" ]) && error "余额不足: $LP_BALANCE < $LIQUIDITY"
info "LP 余额: $LP_BALANCE"

# 3. 查询储备量和总供应量
info "查询储备量..."
RESERVES_RAW=$(cast call "$PAIR_ADDRESS" "getReserves()(uint112,uint112,uint32)" --rpc-url "$RPC_URL" 2>/dev/null || error "无法查询储备量")
TOTAL_SUPPLY_RAW=$(cast call "$PAIR_ADDRESS" "totalSupply()(uint256)" --rpc-url "$RPC_URL" 2>/dev/null || error "无法查询总供应量")

RESERVE_0=$(extract_number "$(echo "$RESERVES_RAW" | head -1)")
RESERVE_1=$(extract_number "$(echo "$RESERVES_RAW" | head -2 | tail -1)")
TOTAL_SUPPLY=$(extract_number "$TOTAL_SUPPLY_RAW")

info "Reserve 0: $RESERVE_0"
info "Reserve 1: $RESERVE_1"
info "Total Supply: $TOTAL_SUPPLY"

# 4. 查询 token0/token1 地址（转换为小写进行比较）
TOKEN0_ADDR=$(cast call "$PAIR_ADDRESS" "token0()(address)" --rpc-url "$RPC_URL" 2>/dev/null || error "无法查询 token0")
TOKEN1_ADDR=$(cast call "$PAIR_ADDRESS" "token1()(address)" --rpc-url "$RPC_URL" 2>/dev/null || error "无法查询 token1")
TOKEN0_ADDR_LOWER=$(echo "$TOKEN0_ADDR" | tr '[:upper:]' '[:lower:]')
TOKEN_0_LOWER=$(echo "$TOKEN_0" | tr '[:upper:]' '[:lower:]')

# 5. 计算预期输出
info "计算预期输出..."
AMOUNT0_RESULT=$(calc_amounts "$LIQUIDITY" "$RESERVE_0" "$TOTAL_SUPPLY" "$SLIPPAGE_TOLERANCE")
AMOUNT1_RESULT=$(calc_amounts "$LIQUIDITY" "$RESERVE_1" "$TOTAL_SUPPLY" "$SLIPPAGE_TOLERANCE")

AMOUNT0_OUT=$(echo "$AMOUNT0_RESULT" | cut -d',' -f1)
AMOUNT0_MIN=$(echo "$AMOUNT0_RESULT" | cut -d',' -f2)
AMOUNT1_OUT=$(echo "$AMOUNT1_RESULT" | cut -d',' -f1)
AMOUNT1_MIN=$(echo "$AMOUNT1_RESULT" | cut -d',' -f2)

# 6. 映射到 TOKEN_0/TOKEN_1
if [ "$TOKEN0_ADDR_LOWER" = "$TOKEN_0_LOWER" ]; then
    AMOUNT_0_OUT=$AMOUNT0_OUT
    AMOUNT_0_MIN=$AMOUNT0_MIN
    AMOUNT_1_OUT=$AMOUNT1_OUT
    AMOUNT_1_MIN=$AMOUNT1_MIN
else
    AMOUNT_0_OUT=$AMOUNT1_OUT
    AMOUNT_0_MIN=$AMOUNT1_MIN
    AMOUNT_1_OUT=$AMOUNT0_OUT
    AMOUNT_1_MIN=$AMOUNT0_MIN
fi

info "预期输出 Token 0: $AMOUNT_0_OUT"
info "预期输出 Token 1: $AMOUNT_1_OUT"
info "最小输出 ($SLIPPAGE_TOLERANCE% 滑点) Token 0: $AMOUNT_0_MIN"
info "最小输出 ($SLIPPAGE_TOLERANCE% 滑点) Token 1: $AMOUNT_1_MIN"
echo ""

# 7. 检查并授权
info "检查授权..."
ALLOWANCE=$(extract_number "$(cast call "$PAIR_ADDRESS" "allowance(address,address)(uint256)" "$TO_ADDRESS" "$ROUTER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")")

if [ "$ALLOWANCE" != "$MAX_UINT" ]; then
    if [ ${#ALLOWANCE} -lt ${#LIQUIDITY} ] || ([ ${#ALLOWANCE} -eq ${#LIQUIDITY} ] && [ "$ALLOWANCE" \< "$LIQUIDITY" ]); then
        warn "授权不足，正在授权..."
        cast send "$PAIR_ADDRESS" "approve(address,uint256)" "$ROUTER_ADDRESS" "$MAX_UINT" \
            --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --gas-price "$GAS_PRICE" >/dev/null 2>&1 || error "授权失败"
        info "授权成功"
    fi
fi

# 8. 移除流动性
info "执行移除流动性..."
cast send "$ROUTER_ADDRESS" \
    "removeLiquidity(address,address,uint256,uint256,uint256,address,uint256)" \
    "$TOKEN_0" "$TOKEN_1" "$LIQUIDITY" "$AMOUNT_0_MIN" "$AMOUNT_1_MIN" "$TO_ADDRESS" "$DEADLINE" \
    --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --gas-price "$GAS_PRICE" || error "移除流动性失败"

info "移除流动性交易已成功发送!"
