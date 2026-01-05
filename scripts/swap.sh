#!/bin/bash

# Uniswap V2 Swap 脚本
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ===== 配置参数 =====
RPC_URL="http://127.0.0.1:8545"
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ROUTER_ADDRESS="0x8f86403A4DE0BB5791fa46B8e795C547942fE4Cf"
TOKEN_IN="0x2279b7a0a67db372996a5fab50d91eaa73d2ebe6"
TOKEN_OUT="0xa513e6e4b8f2a923d98304ec87f64353c4d5c853"
AMOUNT_IN="100000000000000000000"
SLIPPAGE_TOLERANCE="1"
TO_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
DEADLINE=$(($(date +%s) + 3600))
GAS_PRICE="1000000000"
MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"

# ===== 工具函数 =====
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

compare_numbers() {
    local num1=$1 num2=$2
    [ ${#num1} -lt ${#num2} ] || ([ ${#num1} -eq ${#num2} ] && [ "$num1" \< "$num2" ])
}

calc_percent() {
    echo "scale=0; $1 * $2 / 100" | bc
}

parse_amounts_out() {
    # cast 返回格式: [100000000000000000000 [1e20], 869158752191931108640 [8.691e20]]
    # 提取最后一个长数字（至少10位，避免匹配科学计数法中的数字）
    local result=$(echo "$1" | grep -oE '[0-9]{10,}' | tail -1)
    if [ -z "$result" ]; then
        error "无法解析查询结果: $1"
    fi
    echo "$result"
}

approve_if_needed() {
    local allowance=$(cast call "$TOKEN_IN" "allowance(address,address)(uint256)" "$TO_ADDRESS" "$ROUTER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
    
    if [ "$allowance" != "$MAX_UINT" ] && compare_numbers "$allowance" "$AMOUNT_IN"; then
        warn "授权不足，正在授权..."
        cast send "$TOKEN_IN" "approve(address,uint256)" "$ROUTER_ADDRESS" "$MAX_UINT" \
            --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --gas-price "$GAS_PRICE" >/dev/null 2>&1 || error "授权失败"
        info "授权成功"
    fi
}

# ===== 主程序 =====
info "开始执行 Swap"
info "配置: Token In=$TOKEN_IN, Token Out=$TOKEN_OUT, Amount In=$AMOUNT_IN, Slippage=$SLIPPAGE_TOLERANCE%"
echo ""

# 检查余额
BALANCE=$(cast call "$TOKEN_IN" "balanceOf(address)(uint256)" "$TO_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
[ "$BALANCE" = "0" ] || [ -z "$BALANCE" ] && error "输入代币余额不足"
compare_numbers "$BALANCE" "$AMOUNT_IN" && error "余额不足: $BALANCE < $AMOUNT_IN"
info "余额充足: $BALANCE"

# 检查并授权
approve_if_needed

# 查询输出数量
info "查询预期输出数量..."
set +e  # 暂时关闭 set -e，以便检查退出码
AMOUNTS_RAW=$(cast call "$ROUTER_ADDRESS" "getAmountsOut(uint256,address[])(uint256[])" \
    "$AMOUNT_IN" "[$TOKEN_IN,$TOKEN_OUT]" --rpc-url "$RPC_URL" 2>&1)
CAST_EXIT=$?
set -e  # 重新开启 set -e

if [ $CAST_EXIT -ne 0 ] || [ -z "$AMOUNTS_RAW" ]; then
    error "查询失败: $AMOUNTS_RAW"
fi

AMOUNT_OUT=$(parse_amounts_out "$AMOUNTS_RAW")
if [ -z "$AMOUNT_OUT" ] || [ "$AMOUNT_OUT" = "0" ]; then
    error "无法解析预期输出数量: $AMOUNTS_RAW"
fi
info "预期输出: $AMOUNT_OUT"

# 计算最小输出
AMOUNT_OUT_MIN=$(calc_percent "$AMOUNT_OUT" $((100 - SLIPPAGE_TOLERANCE)))
info "最小输出 ($SLIPPAGE_TOLERANCE% 滑点): $AMOUNT_OUT_MIN"
echo ""

# 执行 Swap
info "执行 Swap..."
cast send "$ROUTER_ADDRESS" "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" \
    "$AMOUNT_IN" "$AMOUNT_OUT_MIN" "[$TOKEN_IN,$TOKEN_OUT]" "$TO_ADDRESS" "$DEADLINE" \
    --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --gas-price "$GAS_PRICE" || error "Swap 失败"

info "Swap 交易已成功发送!"
