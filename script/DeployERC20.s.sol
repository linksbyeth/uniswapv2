// script/DeployERC20.s.sol
pragma solidity =0.6.6;
import "forge-std/Script.sol";
import "../src/ERC20Token.sol";

contract DeployERC20 is Script {
    function run(string calldata name, string calldata symbol, uint256 totalSupply) external {
        vm.startBroadcast(); // 开始广播

        // 部署 ERC20 代币，所有代币会自动 mint 给部署者（msg.sender）
        ERC20Token token = new ERC20Token(name, symbol, totalSupply);

        vm.stopBroadcast(); // 停止广播

        console.log("ERC20 Token deployed at:", address(token));
        console.log("Token name:", name);
        console.log("Token symbol:", symbol);
        console.log("Total supply:", totalSupply);
        console.log("Balance of deployer:", token.balanceOf(msg.sender));
    }
}

