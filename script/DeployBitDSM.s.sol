 // SPDX-License-Identifier: MIT
 pragma solidity ^0.8.12;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";

// import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";
// import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
// import {IRewardsCoordinator} from "@eigenlayer/src/contracts/interfaces/IRewardsCoordinator.sol";
// import {BitDSMServiceManager} from "../src/core/BitDSMServiceManager.sol";
// import {AppRegistry} from "../src/core/AppRegistry.sol";
// import {BitcoinPodManager} from "../src/core/BitcoinPodManager.sol";
// import {BitDSMRegistry} from "../src/core/BitDSMRegistry.sol";

// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
// import {Quorum, StrategyParams, IStrategy} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

// contract DeployBitDSM is Script {
//     using stdJson for string;
//     using Strings for *;

//      struct StrategyInfo {
//         string name;
//         address strategy;
//     }
//     uint256 deployerPrivateKey;
//     address deployer;

//     ProxyAdmin public proxyAdmin;
//     IAVSDirectory public avsDirectory;
//     IDelegationManager public delegationManager;
//     IRewardsCoordinator public rewardsCoordinator;
    
//    // ECDSAStakeRegistry public stakeRegistry;
//     BitDSMServiceManager public serviceManager;

//     Quorum quorum;
//     uint256 thresholdWeight = 1;

//     AppRegistry public appRegistry;
//     BitcoinPodManager public bitcoinPodManager;
//     BitDSMRegistry public bitDSMRegistry;

//     function _loadEigenlayerAddresses(string memory targetEnv) internal {
//         string memory root = vm.projectRoot();
//         string memory path = string.concat(root, "/script/eigenlayer_addresses.json");
//         string memory json = vm.readFile(path);

//         avsDirectory = IAVSDirectory(json.readAddress(string(abi.encodePacked(".", targetEnv, ".avsDirectory"))));
//         delegationManager = IDelegationManager(json.readAddress(string(abi.encodePacked(".", targetEnv, ".delegationManager"))));
//         rewardsCoordinator = IRewardsCoordinator(json.readAddress(string(abi.encodePacked(".", targetEnv, ".rewardsCoordinator"))));
        
        
//         StrategyInfo[] memory strategies = abi.decode(
//             vm.parseJson(json, string(abi.encodePacked(".", targetEnv, ".strategies"))),
//             (StrategyInfo[])
//         );

        
        
//         StrategyParams memory strategyParam;

//         uint96 totalMultipliers = 10_000;
//         uint96 multiplier;

//         uint96 strategyCount = uint96(strategies.length);
//         for (uint96 i = 0; i < strategyCount; i++) {
//             // the multipliers need to add up to 10,000, so we divide the total by the number of strategies for the first n-1 strategies
//             // and then the last strategy gets the remainder
//             if (i < strategyCount - 1) {
//                 multiplier = totalMultipliers / uint96(strategyCount);
//             } else {
//                 multiplier =
//                     totalMultipliers -
//                     multiplier *
//                     uint96(strategyCount - 1);
//             }
//             strategyParam = StrategyParams({
//                 strategy: IStrategy(strategies[i].strategy),
//                 multiplier: multiplier
//             });
//             quorum.strategies.push(strategyParam);
//         }
//     }

//     function run(string memory network, string memory metadataUri) external {
//         deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
//         deployer = vm.addr(deployerPrivateKey);
        
//         //Load Eigenlayer addresses for network
//         _loadEigenlayerAddresses(network);
        
//         vm.startBroadcast(deployerPrivateKey);

//         // Deploy ProxyAdmin
//         proxyAdmin = new ProxyAdmin();

//         // Deploy AppRegistry
//         AppRegistry appRegistryImpl = new AppRegistry();
//         TransparentUpgradeableProxy appRegistryProxy = new TransparentUpgradeableProxy(
//             address(appRegistryImpl),
//             address(proxyAdmin),
//             abi.encodeCall(AppRegistry.initialize, (deployer))
//         );
//         appRegistry = AppRegistry(address(appRegistryProxy));

        
        
//         // Deploy BitDSMRegistry inherited from ECDSAStakeRegistry
//         BitDSMRegistry bitDSMRegistryImpl = new BitDSMRegistry(delegationManager);
//         TransparentUpgradeableProxy bitDSMRegistryProxy = new TransparentUpgradeableProxy(
//             address(bitDSMRegistryImpl),
//             address(proxyAdmin),
//             ""
//         );
       
//         // Deploy BitDSMServiceManager
//         BitDSMServiceManager serviceManagerImpl = new BitDSMServiceManager(
//             address(avsDirectory),
//             address(bitDSMRegistryProxy),
//             address(rewardsCoordinator),
//             address(delegationManager)
//         );

//         // Deploy BitcoinPodManager
//         BitcoinPodManager bitcoinPodManagerImpl = new BitcoinPodManager();
//         TransparentUpgradeableProxy bitcoinPodManagerProxy = new TransparentUpgradeableProxy(
//             address(bitcoinPodManagerImpl),
//             address(proxyAdmin),
//             abi.encodeCall(BitcoinPodManager.initialize, (address(appRegistry), address(bitDSMRegistry)))
//         );
//         bitcoinPodManager = BitcoinPodManager(address(bitcoinPodManagerProxy));
        
//         TransparentUpgradeableProxy serviceManagerProxy = new TransparentUpgradeableProxy(
//             address(serviceManagerImpl),
//             address(proxyAdmin),
//             abi.encodeWithSelector(BitDSMServiceManager.initialize.selector, deployer)
//         );
//         // Initialize bitDSMRegistry
//         BitDSMRegistry(address(bitDSMRegistryProxy)).initialize(
//             address(serviceManagerProxy),
//             thresholdWeight,
//             quorum
//         );
//         bitDSMRegistry = BitDSMRegistry(address(bitDSMRegistryProxy));

//         serviceManager = BitDSMServiceManager(address(serviceManagerProxy));
       
//        // check the owner of the contracts
//        require(
//             bitDSMRegistry.owner() == address(deployer),
//             "Owner of ECDSAStakeRegistry is not the deployer"
//         );
//         require(
//             serviceManager.owner() == address(deployer),
//             "Owner of BitDSMServiceManager is not the deployer"
//         );
       
       
//        serviceManager.updateAVSMetadataURI(metadataUri);

//         vm.stopBroadcast();

//         console.log("ProxyAdmin: ", address(proxyAdmin));
//         console.log("AppRegistry Proxy: ", address(appRegistry));
//         console.log("BitDSMRegistry Proxy: ", address(bitDSMRegistry));
//         console.log("BitcoinPodManager Proxy: ", address(bitcoinPodManager));
//        // console.log("ECDSAStakeRegistry Proxy: ", address(stakeRegistryProxy));
//         console.log("BitDSMServiceManager Proxy: ", address(serviceManagerProxy));
        
//         // verify deployment
//         _verifyDeployment();
//         // write Deployment contract addresses to file 
//         _writeAddressesToFile();
//     }

//     function _verifyDeployment() internal view {
//       //  require(
//         //    address(stakeRegistry)!= address(0), "StakeRegistry address cannot be zero"
//        // );
//         require(
//             address(serviceManager) != address(0),
//             "BitDSMServiceManager address cannot be zero"
//         );
//         require(address(appRegistry)!=address(0), "AppRegistry address cannot be zero");
//         require(address(bitDSMRegistry) !=address(0), "BitDSMregistry address cannot be zero");
//         require(address(bitcoinPodManager) !=address(0), " BitcoinPodManager address cannot be zero");
//         require(address(proxyAdmin) != address(0), "ProxyAdmin address cannot be zero");
//         require(
//             address(delegationManager) != address(0),
//             "DelegationManager address cannot be zero");
//         require(address(avsDirectory) != address(0), "AVSDirectory address cannot be zero");
//     }

//     function _writeAddressesToFile() internal {
//         string memory root = vm.projectRoot();
//         string memory path = string.concat(root, "/script/bitdsm_addresses.json");

//         string memory json = string.concat(
//             "{",
//             "\"ProxyAdmin\": \"",
//             address(proxyAdmin).toHexString(),
//             "\",",
//             "\"AppRegistryProxy\": \"",
//             address(appRegistry).toHexString(),
//             "\",",
//             "\"BitDSMRegistryProxy\": \"",
//             address(bitDSMRegistry).toHexString(),
//             "\",",
//             "\"BitcoinPodManagerProxy\": \"",
//             address(bitcoinPodManager).toHexString(),
//             "\",",
//            // "\"ECDSAStakeRegistryProxy\": \"",
//            // address(stakeRegistry).toHexString(),
//            // "\",",
//             "\"BitDSMServiceManagerProxy\": \"",
//             address(serviceManager).toHexString(),
//             "\"",
//             "}"
//         );

//         vm.writeFile(path, json);
//     }
// }
