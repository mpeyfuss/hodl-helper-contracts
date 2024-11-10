// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface ICreate2Deployer {
    function deploy(uint256 value, bytes32 salt, bytes memory code) external;
    function computeAddress(bytes32 salt, bytes32 codeHash) external view returns (address);
}

contract DeployHODLHelperV1 is Script {
    using Strings for address;

    function run() public {
        // get environment variables
        ICreate2Deployer create2Deployer = ICreate2Deployer(vm.envAddress("CREATE2_DEPLOYER"));
        bytes memory constructorArgs = vm.envBytes("CONSTRUCTOR_ARGS");
        bytes32 salt = vm.envBytes32("SALT");

        // get bytecode
        bytes memory bytecode = abi.encodePacked(vm.getCode("HODLHelperV1.sol:HODLHelperV1"), constructorArgs);

        // deploy
        address deployedContract = create2Deployer.computeAddress(salt, keccak256(bytecode));
        console.logAddress(deployedContract);
        vm.broadcast();
        create2Deployer.deploy(0, salt, bytecode);

        // save deployed contract address
        vm.writeLine("out.txt", deployedContract.toHexString());
    }
}