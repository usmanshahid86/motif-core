// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import {BitDSMServiceManager} from "../src/core/BitDSMServiceManager.sol";
import "./mocks/MockBitcoinPod.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ISignatureUtils} from "@eigenlayer/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MockBitcoinPodManager} from "./mocks/MockBitcoinPodManager.sol";
import {BitcoinUtils} from "../src/libraries/BitcoinUtils.sol";
contract MockAVSDirectory is IAVSDirectory {
    function registerOperatorToAVS(address, ISignatureUtils.SignatureWithSaltAndExpiry memory) external pure {}
    function deregisterOperatorFromAVS(address) external pure {}
    function updateAVSMetadataURI(string memory) external pure {}
    function OPERATOR_AVS_REGISTRATION_TYPEHASH() external pure returns (bytes32) {
        return bytes32(0);
    }
    function calculateOperatorAVSRegistrationDigestHash(
        address /*_operator*/,
        address /*avs*/,
        bytes32 /*salt*/,
        uint256 /*expiry*/
    ) external pure returns (bytes32) {
        return bytes32(0);
    }
    function operatorSaltIsSpent(address /*_operator*/, bytes32 /*salt*/ ) external pure returns (bool) {
        return false;
    }
}

contract MockECDSAStakeRegistry {
    function operatorRegistered(address) external pure returns (bool) {
        return true;
    }
}

contract BitDSMServiceManagerTest is Test {
    using ECDSA for bytes32;
    BitDSMServiceManager public serviceManager;
    address public podAddress;
    MockBitcoinPodManager public podManager;

    MockAVSDirectory public mockAVSDirectory;
    MockECDSAStakeRegistry public mockStakeRegistry;
    
    address public owner;
    address public operator;
    address public manager;
    address public operator2;
    uint256 private _operatorPrivateKey;
    bytes public operatorBtcPubKey;
    bytes public bitcoinAddress;
    
    event BitcoinWithdrawalTransactionSigned(address indexed pod, address indexed operator, uint256 amount);
    event BTCAddressVerified(address indexed operator, string indexed btcAddress);
    function _deployProxiedServiceManager() internal returns (BitDSMServiceManager) {
    // Deploy ProxyAdmin if not already deployed
    ProxyAdmin proxyAdmin = new ProxyAdmin();
    
    // Deploy implementation
    BitDSMServiceManager impl = new BitDSMServiceManager(
        address(mockAVSDirectory),
        address(mockStakeRegistry),
        address(0), // rewards coordinator
        address(0)  // delegation manager
    );

    // Deploy and initialize proxy in one step
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
        address(impl),
        address(proxyAdmin),
        abi.encodeWithSelector(
            BitDSMServiceManager.initialize.selector,
            owner,
            address(0), // middleware utils
            address(podManager)
        )
    );

    return BitDSMServiceManager(address(proxy));
}

    
    function setUp() public {
        owner = address(this);
        _operatorPrivateKey = 0x1; // This is the private key for operator1
        operator = vm.addr(_operatorPrivateKey);
        operator2 = address(0x2);

        // Mock Bitcoin-related data
        operatorBtcPubKey = hex"02abc123"; // Example public key
        bitcoinAddress = hex"1234567890"; // Example Bitcoin address

        mockAVSDirectory = new MockAVSDirectory();
        mockStakeRegistry = new MockECDSAStakeRegistry();

        // First create the pod manager with a temporary address
        podManager = new MockBitcoinPodManager(address(1)); // temporary address

        
       
        serviceManager = _deployProxiedServiceManager();
        
        podManager.updateServiceManager(address(serviceManager));

        // Create pod
        vm.prank(owner);
        podAddress = podManager.createPod(operator, bitcoinAddress);
    }

    function testConfirmDeposit() public {
        // 1. Create a deposit request
        bytes32 txId = bytes32("example_tx_id");
        uint256 amount = 1;
        
        // Add verification that operator is registered
        assertTrue(mockStakeRegistry.operatorRegistered(operator), "Operator not registered");
        
        // Create deposit request through pod manager
        vm.prank(owner);
        podManager.verifyBitcoinDepositRequest(
            podAddress,
            txId,
            amount
        );

        // Verify deposit request was created successfully
       bool requestPending = podManager.getBitcoinDepositRequest(podAddress).isPending;
        assertTrue(requestPending, "Deposit request not pending");

        // Create deposit confirmation message
        bytes32 messageHash = keccak256(abi.encodePacked(
            podAddress,
            operator,
            amount,
            txId,
            true
        ));
         bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // // Sign message with operator's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_operatorPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // // Verify signature is valid
        address recoveredSigner = ethSignedMessageHash.recover(signature);
        assertEq(recoveredSigner, operator, "Invalid signature recovery");

        // // Confirm deposit as operator
        vm.prank(operator);
        serviceManager.confirmDeposit(podAddress, signature);
        
        // // Assert pod state changes
        assertEq(IBitcoinPod(podAddress).getBitcoinBalance(), amount);
    }

    function testWithdrawBitcoinPSBT() public {
        uint256 amount = 1;
        string memory withdrawAddress = hex"0200000001"; // Example withdraw address
        bytes memory psbtTx = hex"0200000003"; // Example psbt transaction
        
        // client send the psbt to the BitcoinPodManager to create a withdrawal request
        vm.prank(owner);
        podManager.withdrawBitcoinPSBTRequest(podAddress, withdrawAddress);

        // Create PSBT signature message
        bytes32 messageHash = keccak256(abi.encodePacked(
            podAddress,
            amount,
            psbtTx,
            withdrawAddress
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Sign message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_operatorPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Submit PSBT as operator
        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit BitcoinWithdrawalTransactionSigned(podAddress, operator, amount);

        serviceManager.withdrawBitcoinPSBT(podAddress, amount, psbtTx, signature);
       
    }
    
    function testWithdrawBitcoinCompleteTx() public {
        uint256 amount = 1;
        string memory withdrawAddress = hex"0200000001"; // Example withdraw address
        bytes memory completeTx = hex"0200000003"; // Example complete transaction
        
        // client send the request to the BitcoinPodManager to create a withdrawal request
        vm.prank(owner);
        podManager.withdrawBitcoinCompleteTxRequest(podAddress, completeTx, withdrawAddress);
        
        // Create complete tx signature message
        bytes32 messageHash = keccak256(abi.encodePacked(
            podAddress,
            amount,
            completeTx,
            withdrawAddress
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Sign message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_operatorPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Submit complete transaction as operator
        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit BitcoinWithdrawalTransactionSigned(podAddress, operator, amount);
        serviceManager.withdrawBitcoinCompleteTx(podAddress, amount, completeTx, signature);
    }

    function testConfirmWithdrawal() public {
        bytes memory transaction = hex"0200000001"; // Example Bitcoin transaction
        // create mock withdrawal address
        string memory withdrawAddress = hex"0200000001"; // Example withdraw address
        // create a withdrawal request through pod manager
        vm.prank(owner);
        podManager.withdrawBitcoinCompleteTxRequest(podAddress, transaction, withdrawAddress);
        // Create withdrawal confirmation message
        bytes32 messageHash = keccak256(abi.encodePacked(
            podAddress,
            transaction,
            withdrawAddress
        ));
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        // Sign message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_operatorPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Confirm withdrawal as operator
        vm.prank(operator);
        serviceManager.confirmWithdrawal(podAddress, transaction, signature);

        // Assert pod state changes
        assertEq(IBitcoinPod(podAddress).getBitcoinBalance(), 0);
    }


    function testFailConfirmDepositUnauthorized() public {
        bytes memory signature = new bytes(65);
        
        // Try to confirm deposit from unauthorized address
        vm.prank(address(0xbad));
        vm.expectRevert("Unauthorized operator");
        serviceManager.confirmDeposit(podAddress, signature);
    }

    function testFailWithdrawBitcoinPSBTInvalidSignature() public {
        uint256 amount = 1 ether;
        bytes memory psbtTx = hex"0200000001";
        bytes memory invalidSignature = new bytes(65);

        vm.prank(operator);
        vm.expectRevert("Invalid signature");
        serviceManager.withdrawBitcoinPSBT(podAddress, amount, psbtTx, invalidSignature);
    }

    function testFailWithdrawBitcoinCompleteTxUnauthorized() public {
        uint256 amount = 1;
        
        bytes memory completeTx = hex"0200000001";
        bytes memory signature = new bytes(65);

        vm.prank(address(0xbad));
        vm.expectRevert("Unauthorized operator");
        serviceManager.withdrawBitcoinCompleteTx(podAddress, amount, completeTx, signature);
    }

    function testFailConfirmWithdrawalInvalidTransaction() public {
        bytes memory invalidTx = new bytes(0);
        bytes memory signature = new bytes(65);

        vm.prank(operator);
        vm.expectRevert("Invalid transaction");
        serviceManager.confirmWithdrawal(podAddress, invalidTx, signature);
    }
    
    function testVerifyBTCAddress() public {
        // Example P2WSH script with known public keys
        // This is a mock script representing a 2-of-2 multisig witness script
        bytes memory script = hex"522103cb23542f698ed1e617a623429b585d98fb91e44839949db4126b2a0d5a7320b021024589c8c7dbd0a2f341a1349e392834b0ffa7dbdf273f68c3a7e08bec19923a4952ae";
        
        // The corresponding bech32 address for the above script (testnet)
        string memory expectedBtcAddress = "tb1q4vuwn2fwr0dt6kdmgz2ldc9pd70pa9w8rdr5vh5x7jq2srzndqfsrswq4s";
        
        // Mock the operator's BTC public key in the registry
        // First public key from the script above
        bytes memory mockOperatorBtcPubKey = hex"03cb23542f698ed1e617a623429b585d98fb91e44839949db4126b2a0d5a7320b0";
        
        // Mock the registry to return our test operator's BTC public key
        vm.mockCall(
            address(mockStakeRegistry),
            abi.encodeWithSignature("getOperatorBtcPublicKey(address)", operator),
            abi.encode(mockOperatorBtcPubKey)
        );

        // Call verifyBTCAddress as operator
        vm.prank(operator);
        //vm.expectEmit(true, true, false, true);
        //emit BTCAddressVerified(operator, expectedBtcAddress);
       serviceManager.verifyBTCAddress(expectedBtcAddress, script);
       //testing extractpublickeys
       //(bytes memory pubKey1, bytes memory pubKey2) = BitcoinUtils.extractPublicKeys(script);

       // test getScriptPubKey
       //bytes32  scriptPubKey = BitcoinUtils.getScriptPubKey(script);
      //assertEq(scriptPubKey, hex"0020ab38e9a92e1bdabd59bb4095f6e0a16f9e1e95c71b47465e86f480a80c536813", "Invalid scriptPubKey");
       //console.logBytes32(scriptPubKey);
       // test convertScriptPubKeyToBech32Address
       //string memory bech32Address = BitcoinUtils.convertScriptPubKeyToBech32Address(scriptPubKey);
       //assertEq(bech32Address, expectedBtcAddress, "Invalid bech32 address");
       //assertEq(pubKey1, mockOperatorBtcPubKey, "Invalid public key 1");
       //require(pubKey2.length == 33, "Invalid public key 2 length");
    }

    function testFailVerifyBTCAddressInvalidOperator() public {
        bytes memory script = hex"522102c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee521021c1db6e604a4909a6e70f1994e37df6dfdcb19c8ee4c9648f37087e5f36388b352ae";
        string memory btcAddress = "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7";
        
        // Call with non-operator address should fail
        vm.prank(address(0xbad));
        serviceManager.verifyBTCAddress(btcAddress, script);
    }

    function testFailVerifyBTCAddressInvalidScript() public {
        // Invalid script (wrong length)
        bytes memory invalidScript = hex"1234";
        string memory btcAddress = "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7";
        
        vm.prank(operator);
        serviceManager.verifyBTCAddress(btcAddress, invalidScript);
    }
    function testVerifyPSBTOutputs() public {
        bytes memory psbtBytes = hex"70736274ff01005202000000010ae75c05525a16550f06a871ae31b5ecbfc778c0f7fc33e7d15cb956cb2479370000000000f5ffffff017f25000000000000160014bfcca6233013df0aa07a900170f479172eb19076000000000001007d0200000001c70045a2d38337557c4fc9bf65c11dee5c9334328d80bfc040bdc9f57ba1491e0100000000ffffffff021027000000000000220020a816306ea7aa56b85c885244b4b42af2204c2c0b8716734bc7c9e327dc93b2b25e0201000000000016001479f554a3171903aae7a975d7b5de42bf45ee12500000000001012b1027000000000000220020a816306ea7aa56b85c885244b4b42af2204c2c0b8716734bc7c9e327dc93b2b2220203cb23542f698ed1e617a623429b585d98fb91e44839949db4126b2a0d5a7320b047304402206e62db59302da26342fa718b51bf6f7f49c77413dc6ad0954c7f667fe3d48e2a02200b8d4c61ad840563dd08aeaa47d092d4c4733b195a2e20339699237c7475923881010547522103cb23542f698ed1e617a623429b585d98fb91e44839949db4126b2a0d5a7320b02103d00e88ffd1282cc378398d624566e76a1c631858cadfc7dc6c06e517f22fa48d52ae220603cb23542f698ed1e617a623429b585d98fb91e44839949db4126b2a0d5a7320b018aba9403b5400008001000080000000800000000000000000220603d00e88";
        string memory withdrawAddress = "tb1qhlx2vgesz00s4gr6jqqhparezuhtryrkpnd7tm";    
        uint256 withdrawAmount = 9599;
        assert(serviceManager.verifyPSBTOutputs(psbtBytes, withdrawAddress, withdrawAmount));
    }
}





