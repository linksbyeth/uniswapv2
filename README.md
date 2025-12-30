# 官方代码仓库

## 官方文档
https://docs.uniswap.org/contracts/v2/overview

## 代码仓库
- https://github.com/Uniswap/v2-core
- https://github.com/Uniswap/v2-periphery
- https://github.com/Uniswap/solidity-lib
- https://github.com/Uniswap/v2-subgraph

# 部署合约

## 启动 anvil 本地节点（找到默认的账户）

执行 anvil 命令：

```bash
anvil
```

地址：`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`

私钥：`0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

## 写入临时环境变量

```bash
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

# 使用源代码编译的字节码部署合约（完整流程）

## 1. 编译合约

README.md 文档中提醒 Node 版本 >= 10 需要使用 yarn 工具来编译合约，推荐使用 nvm 工具来管理本地 Node 版本。

依次执行以下命令编译合约，编译后的文件在 build 目录。找到 Combined-Json.json 文件，这个文件包含了项目中所有的合约描述。也可以直接使用合约对应名字的 json 文件。其中有两个字段 bytecode 和 deployedBytecode ， bytecode 是创建字节码，包含了构造函数的逻辑，deployedBytecode 是在链上运行时的字节码。

```bash
yarn
yarn compile
```

## 2. 部署 Core 合约 准备部署合约的 bytecode

通过 yarn compile 编译合约后，找到 `/build/UniswapV2Factory.json` 文件里面的 bytecode 内容。然后执行代码块中的 abi-encode 命令得到构造参数，这一段得到的值需要去掉前面的 0x 然后拼接到 bytecode 后面。bytecode + 构造参数。这里的地址是自己提供的一个 EOA 地址

```bash
cast abi-encode "constructor(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

[图片]

## 3. 发送交易到本地节点

```bash
cast send \
--rpc-url  $RPC_URL \
--private-key $PRIVATE_KEY \
--create \
0x........ 这里的内容是上一步拼接的 bytecode 最前面加上 0x
```

## 4. 获取合约地址

上一步执行成功后会输出一个 transactionHash，然后通过这个 transactionHash 直接获取。

```bash
cast receipt 0x81458ba89820680690e50d8a602e787b9e188c0c49cb7ac1215a2c14e83f33c7  --rpc-url $RPC_URL
```

[图片]

## 5. 部署 Periphery 合约

流程与 core 合约一致

# 使用 Foundry 部署文档（完整流程）

## 1. 环境准备

### 1.1 安装 Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

检查：

```bash
forge --version
cast --version
```

---

### 1.2 使用 forge 初始化项目

```bash
forge init uniswap-v2
cd uniswap-v2
```

需要删除创建项目默认的合约和测试用例，script脚本：

```bash
rm -rf ./src/Counter.sol
rm -rf ./test/Counter.t.sol
rm -rf ./script/Counter.s.sol
```

---

### 1.3 下载依赖库

```bash
forge install Uniswap/v2-core
forge install Uniswap/v2-periphery
forge install Uniswap/uniswap-lib
```

或者通过 git clone 方式安装：

```bash
git clone https://github.com/Uniswap/v2-core.git lib/v2-core
git clone https://github.com/Uniswap/v2-periphery.git lib/v2-periphery
```

v2-periphery 里面的 router 合约依赖 uniswap-lib 里面的代码，所以直接安装一下 uniswap-lib：

```bash
git clone https://github.com/Uniswap/uniswap-lib.git lib/uniswap-lib
```

---

### 1.4 设置 remappings.txt

```bash
echo "@uniswap/v2-core/=lib/v2-core/
@uniswap/v2-periphery/=lib/v2-periphery/
@uniswap/lib/=lib/uniswap-lib/" > remappings.txt
```

---

## 2. 编译

### 2.1 编译 v2-core

```bash
forge build lib/v2-core/contracts/UniswapV2Factory.sol
```

编译后的文件：

```
/uniswap-v2/out/UniswapV2Factory.sol/UniswapV2Factory.json
```

### 2.2 编译 v2-periphery

```bash
forge build lib/v2-periphery/contracts/UniswapV2Router01.sol
forge build lib/v2-periphery/contracts/UniswapV2Router02.sol
forge build lib/v2-periphery/contracts/UniswapV2Migrator.sol
```

---

## 3. 部署脚本（Foundry Script）

### 3.1 Factory（0.5.16，无法 forge-std）

Factory 合约 版本 0.5.16，无法使用 forge-std ，因为 forge-std vm 组件的版本最低是 >=0.6.2 需要这个组件去广播交易，没有对更低版本支持，所以无法使用 script 的方式部署，这里直接使用  bytecode 拼接的方式部署合约。

获取 bytecode：

```bash
forge inspect UniswapV2Factory bytecode
```

获取构造函数的 bytecode：

```bash
cast abi-encode "constructor(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

拼接 bytecode 使用 cast 发送交易 快速拼接，写入到文件：

```bash
forge inspect UniswapV2Factory bytecode > UniswapV2FactoryBytecode.hex
```

然后把构造函数的 bytecode 加入到末尾：

```bash
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY --create "$(cat UniswapV2FactoryBytecode.hex)"
```

```bash
cast call 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 "feeToSetter()(address)" --rpc-url $RPC_URL
```

如果输出是上面设置的地址 `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` 则部署成功

---

### 3.2 WETH官方版本（如果需要）

直接使用 ETH 官方的 WETH9 代码

https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2#code

由于官方的 WETH9 版本更低，也是用 bytecode 方式部署

```bash
forge inspect WETH9 bytecode > WETH9Bytecode.hex
```

```bash
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY --create "$(cat WETH9Bytecode.hex)"
```

---

### 3.3 Router（0.6.6，可用 forge-std）

```solidity
// script/DeployRouter.s.sol
pragma solidity =0.6.6;
import "@uniswap/v2-periphery/contracts/UniswapV2Router02.sol";
import "forge-std/Script.sol";

contract DeployRouter is Script {
    function run(address factoryAddress, address wethAddress) external  {
        vm.startBroadcast();   // 开始广播
        UniswapV2Router02 router = new UniswapV2Router02(factoryAddress, wethAddress);
        vm.stopBroadcast();    // 停止广播
        console.log("Router deployed at:", address(router));
    }
}
```

```bash
forge script script/DeployRouter.s.sol:DeployRouter \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
```

注意：传参数直接写在命令末尾，使用空格分开

---

## 4. 注意事项

### 编译部署事项

1. Factory Router 使用的 pragma 版本不一样，需要分开编译
2. 使用 Script 脚本部署合约，不能引用 forge-std 里面的一些依赖高版本的组件，否则会报错
3. remappings.txt 必须补充完整，否则找不到依赖路径

### 部署顺序：

- Factory（0.5.16）
- WETH
- Router（0.6.6）

---

## 5. 总结流程图

```
[lib/v2-core] (pragma 0.5.16)     --> Factory Script  --> deploy Factory
[lib/uniswap-lib]                 --> Factory / Router Script
[lib/v2-periphery] (pragma 0.6.6) --> Router Script   --> deploy Router
[WETH9]                           --> WETH Script     --> deploy WETH
每个 Script 独立编译 → 避免 pragma 冲突
remapping 完整 → import 无报错
部署顺序 Factory → WETH → Router → 确保 Router 构造参数正确
```

---

# 总结

两种部署方式各有优点，个人认为使用 foundry scrpit 来部署合约更加简洁明了，不用和 bytecode 打交道，直接使用 script 的方式部署。如果使用 bytecode 拼接的方式部署稍微有点麻烦，需要反复的字符串对比是否一致，且容易出错，特别是在 构造函数复杂的情况下。

推荐使用 foundry 的方式部署，我已经准备好了部署源码 Github 使用 UnswapV2 的标准版本。
https://github.com/linksbyeth/uniswapv2

