#!/bin/bash

# Uniswap V2 添加流动性脚本
# 使用方法: ./scripts/addLiquidity.sh

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ===== 配置参数 =====
# 请根据实际情况修改以下参数

# RPC 节点地址
RPC_URL="http://127.0.0.1:8545"

# 私钥
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# Router 地址
ROUTER_ADDRESS="0x8f86403A4DE0BB5791fa46B8e795C547942fE4Cf"

# 代币地址
TOKEN_0="0x2279b7a0a67db372996a5fab50d91eaa73d2ebe6"
TOKEN_1="0xa513e6e4b8f2a923d98304ec87f64353c4d5c853"

# 添加流动性数量（wei 单位，18 位小数）
AMOUNT_0="100000000000000000000"
AMOUNT_1="1000000000000000000000"

# 最小数量（滑点保护，建议设置为期望值的 95-99%）
# 例如：950000000000000000000 表示最小 950 个代币（5% 滑点）
AMOUNT_0_MIN="9500000000000000000"
AMOUNT_1_MIN="95000000000000000000"

# 接收 LP 代币的地址
TO_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# 交易截止时间（当前时间 + 1小时，会自动计算）
DEADLINE=$(($(date +%s) + 3600))

# Gas 配置（用于本地测试网络，如 anvil）
# 对于本地网络，可以使用较小的值或 0
GAS_PRICE="1000000000"  # 1 gwei (1000000000 wei)

AUTO_APPROVE=true
# ===== 函数定义 =====

# 打印信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 比较两个大数，如果第一个小于第二个返回 true
compare_numbers() {
    local num1=$1
    local num2=$2
    if [ ${#num1} -lt ${#num2} ]; then
        return 0  # num1 < num2
    elif [ ${#num1} -gt ${#num2} ]; then
        return 1  # num1 > num2
    else
        # 长度相同，使用字符串比较
        [ "$num1" \< "$num2" ]
    fi
}

# 授权代币
approve_token() {
    local token_address=$1
    local spender=$2
    local amount=$3
    local token_name=$4
    
    info "授权 $token_name ($token_address)..."
    
    # 使用最大额度授权
    local max_amount="115792089237316195423570985008687907853269984665640564039457584007913129639935"
    
    if cast send "$token_address" \
        "approve(address,uint256)" \
        "$spender" \
        "$max_amount" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --gas-price "$GAS_PRICE" \
        > /dev/null 2>&1; then
        info "$token_name 授权成功"
    else
        error "$token_name 授权失败"
        return 1
    fi
}

# ===== 主程序 =====

info "开始添加流动性..."
echo ""
info "配置参数:"
echo "  Router: $ROUTER_ADDRESS"
echo "  Token 0: $TOKEN_0"
echo "  Token 1: $TOKEN_1"
echo "  Amount 0: $AMOUNT_0"
echo "  Amount 1: $AMOUNT_1"
echo "  Amount 0 Min: $AMOUNT_0_MIN"
echo "  Amount 1 Min: $AMOUNT_1_MIN"
echo "  To: $TO_ADDRESS"
echo "  Deadline: $DEADLINE ($(date -d @$DEADLINE 2>/dev/null || date -r $DEADLINE))"
echo ""

# 授权代币
if [ "$AUTO_APPROVE" = "true" ]; then
    info "正在授权代币..."
    approve_token "$TOKEN_0" "$ROUTER_ADDRESS" "$AMOUNT_0" "Token 0" || exit 1
    approve_token "$TOKEN_1" "$ROUTER_ADDRESS" "$AMOUNT_1" "Token 1" || exit 1
    echo ""
else
    warn "跳过授权步骤（AUTO_APPROVE=false）"
    warn "请确保已手动授权代币给 Router 合约"
    echo ""
fi

# 添加流动性
info "正在添加流动性..."

# 先检查代币余额
info "检查代币余额..."
BALANCE_0=$(cast call "$TOKEN_0" "balanceOf(address)(uint256)" "$TO_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
BALANCE_1=$(cast call "$TOKEN_1" "balanceOf(address)(uint256)" "$TO_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")

if [ "$BALANCE_0" = "0" ] || [ -z "$BALANCE_0" ]; then
    error "Token 0 余额不足或查询失败"
    exit 1
fi

if [ "$BALANCE_1" = "0" ] || [ -z "$BALANCE_1" ]; then
    error "Token 1 余额不足或查询失败"
    exit 1
fi

info "Token 0 余额: $BALANCE_0 (需要: $AMOUNT_0)"
info "Token 1 余额: $BALANCE_1 (需要: $AMOUNT_1)"

# 检查余额是否足够（使用字符串长度和字典序比较大数）
# 函数：比较两个大数，如果第一个小于第二个返回 true
compare_numbers() {
    local num1=$1
    local num2=$2
    if [ ${#num1} -lt ${#num2} ]; then
        return 0  # num1 < num2
    elif [ ${#num1} -gt ${#num2} ]; then
        return 1  # num1 > num2
    else
        # 长度相同，使用字符串比较
        [ "$num1" \< "$num2" ]
    fi
}

# 检查余额是否足够
if compare_numbers "$BALANCE_0" "$AMOUNT_0"; then
    error "Token 0 余额不足！需要: $AMOUNT_0, 实际: $BALANCE_0"
    exit 1
fi

if compare_numbers "$BALANCE_1" "$AMOUNT_1"; then
    error "Token 1 余额不足！需要: $AMOUNT_1, 实际: $BALANCE_1"
    exit 1
fi

# 检查授权额度
info "检查授权额度（需要: Token 0=$AMOUNT_0, Token 1=$AMOUNT_1）..."
APPROVE_0=$(cast call "$TOKEN_0" "allowance(address,address)(uint256)" "$TO_ADDRESS" "$ROUTER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
APPROVE_1=$(cast call "$TOKEN_1" "allowance(address,address)(uint256)" "$TO_ADDRESS" "$ROUTER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
info "Token 0 授权额度: $APPROVE_0 (需要: $AMOUNT_0)"
info "Token 1 授权额度: $APPROVE_1 (需要: $AMOUNT_1)"

# 检查 pair 是否存在以及当前储备
info "检查 pair 状态..."
FACTORY_ADDRESS=$(cast call "$ROUTER_ADDRESS" "factory()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -n "$FACTORY_ADDRESS" ] && [ "$FACTORY_ADDRESS" != "0x0000000000000000000000000000000000000000" ]; then
    PAIR_ADDRESS=$(cast call "$FACTORY_ADDRESS" "getPair(address,address)(address)" "$TOKEN_0" "$TOKEN_1" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    if [ -n "$PAIR_ADDRESS" ] && [ "$PAIR_ADDRESS" != "0x0000000000000000000000000000000000000000" ]; then
        info "Pair 已存在: $PAIR_ADDRESS"
        RESERVES=$(cast call "$PAIR_ADDRESS" "getReserves()(uint112,uint112,uint32)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
        if [ -n "$RESERVES" ]; then
            info "Pair 当前储备: $RESERVES"
            warn "Pair 已存在流动性，Router 会根据当前汇率调整实际需要的代币数量"
            warn "如果调整后的数量 < AMOUNT_*_MIN，交易将失败"
        fi
    else
        info "Pair 不存在，将自动创建"
    fi
fi

# 检查授权是否足够（使用添加流动性的额度来判断）
MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"

if [ "$APPROVE_0" != "$MAX_UINT" ]; then
    if compare_numbers "$APPROVE_0" "$AMOUNT_0"; then
        error "Token 0 授权不足！需要: $AMOUNT_0, 实际授权: $APPROVE_0"
        exit 1
    fi
fi

if [ "$APPROVE_1" != "$MAX_UINT" ]; then
    if compare_numbers "$APPROVE_1" "$AMOUNT_1"; then
        error "Token 1 授权不足！需要: $AMOUNT_1, 实际授权: $APPROVE_1"
        exit 1
    fi
fi

echo ""

# 发送交易
info "正在发送交易（这可能需要几秒钟）..."
echo ""

# 直接执行并实时打印输出
cast send "$ROUTER_ADDRESS" \
    "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)" \
    "$TOKEN_0" \
    "$TOKEN_1" \
    "$AMOUNT_0" \
    "$AMOUNT_1" \
    "$AMOUNT_0_MIN" \
    "$AMOUNT_1_MIN" \
    "$TO_ADDRESS" \
    "$DEADLINE" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --gas-price "$GAS_PRICE"

SEND_EXIT_CODE=$?
echo ""

if [ $SEND_EXIT_CODE -eq 0 ]; then
    info "交易已成功发送!"
else
    error "添加流动性失败（退出码: $SEND_EXIT_CODE)"
    exit $SEND_EXIT_CODE
fi

info "完成!"

