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