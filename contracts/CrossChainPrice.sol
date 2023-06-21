// File: contracts/crosschain/avalanceassetbridge.sol

//SPDX-License-Identifier: MIT

import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IORACLE{
    function setSfrxETHprice(uint256 price) external returns (uint256);
}


interface INativeORACLE{
   function getsfrxEthExchangeRate() external view returns (uint256);
}

pragma solidity 0.8.17;

contract CrossChainPrice is Ownable, NonblockingLzApp{
    using SafeERC20 for IERC20;
    // Structs
    struct PriceMessage {
        uint256 price;
    }

    IORACLE public oracle;
    INativeORACLE public NativeOracle;


    bool open = true;
    // Events
    event PriceMessageReceived(uint256 price);
    event BridgingInitiated(uint256 price);

    constructor(
        address _lzEndpoint
    
   
    ) NonblockingLzApp(_lzEndpoint)  {
       
    }

    function setOpen(bool _open) external onlyOwner {
        open = _open;
    }

    function updateOracle(IORACLE _oracle) external onlyOwner {
        oracle = _oracle;
    }

    
    function updateNativeOracle(INativeORACLE _oracle) external onlyOwner {
        NativeOracle = _oracle;
    }



    

    // @dev Helper to build PriceMessage
    function buildPriceMessage(uint256 _price) private pure returns (bytes memory) {
        return abi.encode(
            PriceMessage({
             
                price: _price
     
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
        PriceMessage memory message = abi.decode(payload, (PriceMessage)); 
        oracle.setSfrxETHprice(message.price);
        emit PriceMessageReceived(message.price);
    }
 function updatePrice(uint16 dstChainId) external payable {
        require(msg.value != 0, "!fee");
        
        require(open, "bridge is paused");

        uint256 price = NativeOracle.getsfrxEthExchangeRate();
        address sender = _msgSender();

        _lzSend(
            dstChainId,
            buildPriceMessage(price),
            payable(sender),  // refund address (LayerZero will refund any extra gas back to caller)
            address(0x0),     // unused
            bytes(""),        // unused
            msg.value         // native fee amount
        );
  
        emit BridgingInitiated(price);
    }


    // @notice Used by the frontend to estimate how much native token should be sent with bridgeTokens() for LayerZero fees.
    // @param dstChainId The **LayerZero** destination chain ID.
    function estimateNativeFee(
        uint16 dstChainId,
        uint256 price
    ) external view returns (uint nativeFee) {
        (nativeFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            address(this),
            buildPriceMessage(price),
            false,
            bytes("")
        );
    }
}