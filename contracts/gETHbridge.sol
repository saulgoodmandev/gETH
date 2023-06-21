// File: contracts/crosschain/avalanceassetbridge.sol

//SPDX-License-Identifier: MIT

import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ITOKEN is IERC20 {
    function mint(address recipient, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external ;
}

pragma solidity 0.8.17;

contract RBridge is Ownable, NonblockingLzApp{
    using SafeERC20 for IERC20;
    // Structs
    struct MintMessage {
        address to;
        uint amount;
        uint id;
    }

    ITOKEN[] public assets;
    uint256 public fee = 100;

    bool open = true;
    // Events
    event MintMessageReceived(uint16 indexed srcChainId, address indexed to, uint amount, uint id);
    event BridgingInitiated(uint16 indexed targetChainId, address indexed to, uint amount, uint id);

    constructor(
        address _lzEndpoint,
        ITOKEN _asset
   
    ) NonblockingLzApp(_lzEndpoint)  {
       assets.push( _asset);
    }

    function setOpen(bool _open) external onlyOwner {
        open = _open;
    }

    
    function addAsset(ITOKEN _asset) external onlyOwner {
        assets.push(_asset);
    }

    function updateFee(uint256 _fee) external onlyOwner  {
        require(_fee <= 1000, "over 1%");
        fee = _fee;

    }


    // @dev Helper to build MintMessage
    function buildBridgeMessage(address to, uint amount, uint id) private pure returns (bytes memory) {
        return abi.encode(
            MintMessage({
                to: to,
                amount: amount,
                id: id
            })
        );
    }

    // @notice Mints asset bridged from the other side, can only be invoked by a trusted remote
    // @param payload message sent from the other side
    function _nonblockingLzReceive(
        uint16 srcChainId,
        bytes memory /* srcAddress */,
        uint64 /* nonce */,
        bytes memory payload
    ) internal override {
        MintMessage memory message = abi.decode(payload, (MintMessage)); 
        assets[message.id].mint(message.to, message.amount);
        emit MintMessageReceived(srcChainId, message.to, message.amount, message.id);
    }

    // @notice Burns asset from caller, then sends a cross-chain message to the destination chain.
    // @param dstChainId The **LayerZero** destination chain ID.
    function bridgeTokens(uint16 dstChainId, uint amount, uint id, address receiver) external payable {
        require(msg.value != 0, "!fee");
        require(amount > 0, "!amount");
        require(id <2, " wrong id");
        require(open, "bridge is paused");

        uint256 feeAmount = amount*fee/100000;
        amount -= feeAmount;
        address sender = _msgSender();

        _lzSend(
            dstChainId,
            buildBridgeMessage(receiver, amount, id),
            payable(sender),  // refund address (LayerZero will refund any extra gas back to caller)
            address(0x0),     // unused
            bytes(""),        // unused
            msg.value         // native fee amount
        );
  
        assets[id].transferFrom(sender, owner(), feeAmount);
        assets[id].burn(sender, amount);
      
     
        emit BridgingInitiated(dstChainId, sender, amount, id);
    }

    // @notice Used by the frontend to estimate how much native token should be sent with bridgeTokens() for LayerZero fees.
    // @param dstChainId The **LayerZero** destination chain ID.
    function estimateNativeFee(
        uint16 dstChainId,
        address to,
        uint amount,
        uint id
    ) external view returns (uint nativeFee) {
        (nativeFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            address(this),
            buildBridgeMessage(to, amount, id),
            false,
            bytes("")
        );
    }
}