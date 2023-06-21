// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

interface IBridge {
    function bridgeTokens(uint16 dstChainId, uint amount, uint id, address receiver) external payable;
}
interface oracle {

    function getPrice(uint id) external view returns (uint256);
}


contract gETH is ERC20("gETH", "gETH"), Ownable , ReentrancyGuard{ 
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public bridge;
    address public Treasury;
    address public Staking;
    uint256 public TreasuryRate = 500;
  

    function burn(address _from, uint256 _amount) external{
        require(msg.sender == bridge);
        _burn(_from, _amount);
    }

    function selfburn(uint256 _amount) external{
        
        _burn(msg.sender, _amount);
    }


    function mint(address recipient, uint256 _amount) external  {
        require(msg.sender == bridge);
        _mint(recipient, _amount);

    }


    struct CollateralProperties {
        oracle priceFeed;
        uint id;
        uint256 fee;
        uint256 maxWeight;
        uint256 TargetWeight;
        uint256 MinTargetWeight;
    }

    mapping(address => CollateralProperties) public CollateralMap;
    mapping(address => bool) public isCollateral;
    address[] public collaterals;

    constructor(address _bridge, address _treasury) {
        bridge = _bridge;
        Treasury = _treasury;
        
    }
    function calWeight(address _collateral, uint256 addAmount) public view returns (uint256) {
        if (totalSupply() <= 20e18) {
            return 0;
        }
        uint256 amount = IERC20(_collateral).balanceOf(address(this)).add(addAmount);
        CollateralProperties memory token = CollateralMap[address(_collateral)];
        oracle Oracle = token.priceFeed;
        uint id = token.id;
        uint256 amountOut = amount.mul(Oracle.getPrice(id)).div(1e18);
        return amountOut.mul(1e18).div(totalSupply());
    }
    function addCollateral(address _collateral, oracle _oracle, uint _id, uint256 _fee, uint256 _targetWeight) external onlyOwner{
        require(!isCollateral[_collateral], "added collaterals");
        require(_fee <= 1000);
        collaterals.push(_collateral);
        isCollateral[_collateral] = true;
        CollateralMap[_collateral].priceFeed = _oracle;
        CollateralMap[_collateral].id = _id;
        CollateralMap[_collateral].fee = _fee;
        CollateralMap[_collateral].maxWeight = 5e17;
        CollateralMap[_collateral].TargetWeight = _targetWeight;
        CollateralMap[_collateral].MinTargetWeight = 1e17;
    }

    function setCollateral(address _collateral, oracle _oracle, uint _id, uint256 _fee, uint256 _maxweight) external onlyOwner{
        require(isCollateral[_collateral], "not added collaterals");
        require(_fee <= 1000);
        require(_maxweight <= 1e18, " over 100%");
        CollateralMap[_collateral].priceFeed = _oracle;
        CollateralMap[_collateral].id = _id;
        CollateralMap[_collateral].fee = _fee;
        CollateralMap[_collateral].maxWeight = _maxweight;
    }

    function setCollateralMaxWeight(address _collateral, uint256 _maxweight) external onlyOwner{
        require(isCollateral[_collateral], "not added collaterals");
        require(_maxweight <= 1e18, " over 100%");
        CollateralMap[_collateral].maxWeight = _maxweight;
    }

    function setCollateralMinTargetWeight(address _collateral, uint256 _weight) external onlyOwner{
        require(isCollateral[_collateral], "not added collaterals");
        require(_weight <= 1e18, " over 100%");
        CollateralMap[_collateral].MinTargetWeight = _weight;
    }

    function setCollateralTargetWeight(address _collateral, uint256 _weight) external onlyOwner{
        require(isCollateral[_collateral], "not added collaterals");
        require(_weight <= 1e18, " over 100%");
        CollateralMap[_collateral].TargetWeight = _weight;
    }

    function updateBridge(address _bridge) external onlyOwner  {
        bridge = _bridge;

    }

    function updateTreasury(address _treasury) external onlyOwner  {
        Treasury = _treasury;

    }

    function updateStaking(address _staking) external onlyOwner  {
        Staking = _staking;

    }

    function updateTreasuryRate(uint256 rate) external onlyOwner  {
        require(rate <= 1000, "over 100%");
        TreasuryRate = rate;

    }


    function claimYield() public {
        if (totalSupply() > 0) {
            if (ViewUnclaimedYield() >= 1e14){
                uint256 unclaimed = ViewUnclaimedYield();
                uint256 TreasuryAmount = unclaimed.mul(TreasuryRate).div(1000);
                uint256 StakingAmount = unclaimed.sub(TreasuryAmount);
                _mint(Treasury, TreasuryAmount);
                _mint(Staking, StakingAmount);
            }
        }
    }
  
    function ViewUnclaimedYield() public view returns(uint256)   {

        return currentSupplyAfterYield().sub(totalSupply());
    }

    function currentSupplyAfterYield() public view returns(uint256)   {

        uint256 current = 0;
        for (uint256 i=0 ;i < collaterals.length; i++) {
            address _token = collaterals[i];
            CollateralProperties memory token = CollateralMap[address(_token)];
            uint256 tokensupply = IERC20(_token).balanceOf(address(this));
            oracle Oracle = token.priceFeed;
            uint id = token.id;
            uint256 gETHsupply = tokensupply.mul(Oracle.getPrice(id)).div(1e18);
            current = current.add(gETHsupply);
        }
        return current;

    }

    function estimateMintFee(IERC20 _token) public view returns(uint256) {
        require(isCollateral[address(_token)], "not collateral");
        CollateralProperties memory token = CollateralMap[address(_token)];
        uint256 fee = 0;
        if (calWeight(address(_token), 0) >= token.TargetWeight) {
            fee = 100;
        }
        return fee;
    }

    function estimateRedeemFee(IERC20 _token) public view returns(uint256) {
        require(isCollateral[address(_token)], "not collateral");
        CollateralProperties memory token = CollateralMap[address(_token)];
        uint256 addFee = 0;
        if (calWeight(address(_token), 0) <= token.MinTargetWeight) {
            addFee = 100;
        }

        return token.fee.add(addFee);
    }

    function estimateMintWithCollaterals(uint256 _amount, IERC20 _token) public view returns(uint256) {
        require(isCollateral[address(_token)], "not collateral");
        require(_token.balanceOf(msg.sender) >= _amount, "token balance too low");
        CollateralProperties memory token = CollateralMap[address(_token)];
        uint256 fee = 0;
        require(calWeight(address(_token), _amount) <= token.maxWeight, "tokens reached max weight");
        if (calWeight(address(_token), _amount) >= token.TargetWeight) {
            fee = 100;
        }
        oracle Oracle = token.priceFeed;
        uint id = token.id;
        uint256 amountOut = _amount.mul(Oracle.getPrice(id)).div(1e18);
        uint256 feeAmount = amountOut.mul(fee).div(100000);
        amountOut -= feeAmount;
        return amountOut;
    }

    
    function estimateRedeemWithCollaterals(uint256 _amount, IERC20 _token, bool isSwap) public view returns(uint256) {
        require(isCollateral[address(_token)], "not collateral");
        require(balanceOf(msg.sender) >= _amount, "token balance too low");
        CollateralProperties memory token = CollateralMap[address(_token)];
        uint256 addFee = 0;
        if (calWeight(address(_token), 0) <= token.MinTargetWeight) {
            addFee = 100;
        }
        oracle Oracle = token.priceFeed;
        uint id = token.id;
        uint256 amountOut = _amount.mul(1e18).div(Oracle.getPrice(id));
        uint256 feeAmount = amountOut.mul(token.fee.add(addFee)).div(100000);
        if (isSwap) {
            feeAmount = 0;
        }
        amountOut = amountOut.sub(feeAmount);

        return amountOut;
    }


    function mintWithCollaterals(uint256 _amount, IERC20 _token) public  nonReentrant returns(uint256) {
       return _mintWithCollaterals(_amount, _token);
    }

    function _mintWithCollaterals(uint256 _amount, IERC20 _token) private  returns(uint256) {
        require(isCollateral[address(_token)], "not collateral");
        require(_token.balanceOf(msg.sender) >= _amount, "token balance too low");
        CollateralProperties memory token = CollateralMap[address(_token)];
        uint256 fee = 0;
        require(calWeight(address(_token), _amount) <= token.maxWeight, "tokens reached max weight");
        if (calWeight(address(_token), _amount) >= token.TargetWeight) {
            fee = 50;
        }
        oracle Oracle = token.priceFeed;
        uint id = token.id;
        uint256 amountOut = _amount.mul(Oracle.getPrice(id)).div(1e18);
        uint256 feeAmount = amountOut.mul(fee).div(100000);
        amountOut -= feeAmount;
        _mint(msg.sender, amountOut);
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        _token.safeTransferFrom(msg.sender, address(this), feeAmount);
        claimYield();
        return amountOut;
    }

    function crosschainMint(uint256 _amount, IERC20 _token, uint16 dstChainId ) public nonReentrant{
       uint256 bridgeAmount = _mintWithCollaterals(_amount, _token);
       IBridge(bridge).bridgeTokens(dstChainId, bridgeAmount, 0, msg.sender);
    }

    function redeem(uint256 _amount, IERC20 _token) public nonReentrant returns(uint256) {
        return _redeem(_amount, _token, false);
    }

    function _redeem(uint256 _amount, IERC20 _token, bool isSwap) private returns(uint256) {
        require(isCollateral[address(_token)], "not collateral");
        require(balanceOf(msg.sender) >= _amount, "token balance too low");
        CollateralProperties memory token = CollateralMap[address(_token)];
        uint256 addFee = 0;
        if (calWeight(address(_token), 0) <= token.MinTargetWeight) {
            addFee = 100;
        }
        oracle Oracle = token.priceFeed;
        uint id = token.id;
        uint256 amountOut = _amount.mul(1e18).div(Oracle.getPrice(id));
        uint256 feeAmount = amountOut.mul(token.fee.add(addFee)).div(100000);
        if (isSwap) {
            feeAmount = 0;
        }
        amountOut = amountOut.sub(feeAmount);
        _burn(msg.sender, _amount);
        _token.safeTransfer(msg.sender, amountOut);
        _token.safeTransfer(owner(), feeAmount);
        claimYield();
        return amountOut;
    }

    function swap(uint256 _amount, IERC20 _from, IERC20 _to) public nonReentrant returns (uint256) {

       uint256 swapAmount = _mintWithCollaterals(_amount, _from);
       uint256 amountOut = _redeem(swapAmount, _to, true);
  
       return amountOut;
       
    }

    function estimateSwap(uint256 _amount, IERC20 _from, IERC20 _to) public view returns (uint256) {

       uint256 swapAmount = estimateMintWithCollaterals(_amount, _from);
       uint256 amountOut = estimateRedeemWithCollaterals(swapAmount, _to, true);
       return amountOut;
       
    }




}