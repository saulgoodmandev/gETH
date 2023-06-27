pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract sGETHToken is ERC20, Ownable {
    ERC20 public _gethToken;
    
    constructor(address gethTokenAddress) ERC20("sGETH Token", "sGETH") {
        _gethToken = ERC20(gethTokenAddress);
    }
    
    function mint(uint256 gethAmount) external {
        require(gethAmount > 0, "Invalid amount");
        require(_gethToken.allowance(msg.sender, address(this)) >= gethAmount, "Insufficient allowance");
        
        uint256 sgethAmount = (gethAmount*1e18/getCurrentConversionRate());
        _gethToken.transferFrom(msg.sender, address(this), gethAmount);
        _mint(msg.sender, sgethAmount);
    }
    
    function redeem(uint256 sgethAmount) external {
        require(balanceOf(msg.sender) >= sgethAmount, "Insufficient balance");
        
        uint256 gethAmount = (sgethAmount * getCurrentConversionRate()/1e18);
        _burn(msg.sender, sgethAmount);
        _gethToken.transfer(msg.sender, gethAmount);
    }
    
    function getGethBalance() external view returns (uint256) {
        return _gethToken.balanceOf(address(this));
    }
    
    
    function getCurrentConversionRate() public view returns (uint256) {
        uint256 gethBalance = _gethToken.balanceOf(address(this));
        if (gethBalance == 0 || totalSupply() == 0) {
            return 1e18;
        }
        
        return gethBalance*1e18 / totalSupply();
    }
}
