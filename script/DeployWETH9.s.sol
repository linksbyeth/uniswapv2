// script/DeployWETH.s.sol
pragma solidity >=0.6.0 * *;
import "../src/WETH9.sol";

contract DeployWETH9 {
    function run() external {
        vm.startBroadcast(); // 开始广播
        WETH9 weth = new WETH9();
        vm.stopBroadcast(); // 停止广播

        console.log("WETH deployed at:", address(weth));
    }
}
