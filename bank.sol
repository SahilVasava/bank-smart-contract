// SPDX-License-Identifier: Unlicencse
pragma solidity >=0.7.0 <0.9.0;


interface cETH {
    
    // define functions of COMPOUND we'll be using
    
    function mint() external payable; // to deposit to compound
    function redeem(uint redeemTokens) external returns (uint); // to withdraw from compound
    function redeemUnderlying(uint redeemAmount) external returns (uint); 
    //following 2 functions to determine how much you'll be able to withdraw
    function exchangeRateStored() external view returns (uint); 
    function balanceOf(address owner) external view returns (uint256 balance);
}

interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

}

interface UniswapRouter {
    function WETH() external pure returns (address);
    
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    
    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    )  external  payable  returns (uint[] memory amounts);

    function getAmountsIn(uint amountOut, address[] memory path)
        view
        external
        returns (uint[] memory amounts);

}


contract SmartBankAccount {
    uint totalContractBalance = 0;
    
    address COMPOUND_CETH_ADDRESS = 0x859e9d8a4edadfEDb5A2fF311243af80F85A91b8;
    cETH ceth = cETH(COMPOUND_CETH_ADDRESS);
    
    address UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    UniswapRouter uniswap = UniswapRouter(UNISWAP_ROUTER_ADDRESS);
    
    function getContractBalanceInEth() public view returns(uint){
        return totalContractBalance * ceth.exchangeRateStored() / 1e18;
    }
    
    mapping(address => uint) balances;
    mapping(address => uint) test;
    mapping(address => uint) test2;
    
    receive() external payable{}
    
    function addBalance() public payable {
        _mint(msg.value);
    }
    
    function addBalanceERC20(address erc20TokenSmartContractAddress) public {
        
        uint ethAfterSwap = _swapTokensForEth(erc20TokenSmartContractAddress);
        
        // test[msg.sender] = ethAfterSwap;
        
        _mint(ethAfterSwap);
    }
    
    function _swapTokensForEth(address erc20TokenSmartContractAddress) internal returns(uint256) {
        
        uint256 approvedAmountOfERC20Tokens = _approveApprovedTokensToUniswap(erc20TokenSmartContractAddress);
        
        uint amountETHMin = 0; 
        address to = address(this);
        uint deadline = block.timestamp + (24 * 60 * 60);
        
        address[] memory path = new address[](2);
        path[0] = erc20TokenSmartContractAddress;
        path[1] = uniswap.WETH();
        
        uint contractEthBalance = address(this).balance;
        test[msg.sender] = uniswap.swapExactTokensForETH(approvedAmountOfERC20Tokens, amountETHMin, path, to, deadline)[1];
        uint ethAfterSwap = address(this).balance - contractEthBalance;
        
        return ethAfterSwap;
    }
    
    function _approveApprovedTokensToUniswap(address erc20TokenSmartContractAddress) internal returns(uint256) {
        IERC20 erc20 = IERC20(erc20TokenSmartContractAddress);
        
        
        uint approvedAmountOfERC20Tokens = erc20.allowance(msg.sender, address(this));
        
        erc20.transferFrom(msg.sender, address(this), approvedAmountOfERC20Tokens);
        
        erc20.approve(UNISWAP_ROUTER_ADDRESS, approvedAmountOfERC20Tokens);
        
        return approvedAmountOfERC20Tokens;
    }
    
    function _mint(uint amountOfEth) internal {
        uint256 cEthOfContractBeforeMinting = ceth.balanceOf(address(this)); //this refers to the current contract
        
        // // send ethers to mint()
        ceth.mint{value: amountOfEth}();
        
        uint256 cEthOfContractAfterMinting = ceth.balanceOf(address(this)); // updated balance after minting
        
        uint cEthOfUser = cEthOfContractAfterMinting - cEthOfContractBeforeMinting; // the difference is the amount that has been created by the mint() function
        totalContractBalance += cEthOfUser;
        balances[msg.sender] += cEthOfUser;
    }
    
    function getAllowanceERC20(address erc20TokenSmartContractAddress) public view returns(uint){
        IERC20 erc20 = IERC20(erc20TokenSmartContractAddress);
        return erc20.allowance(msg.sender, address(this));
    }
    
    function getBalance(address userAddress) public view returns(uint256) {
        return balances[userAddress] * ceth.exchangeRateStored() / 1e18;
    }
    
    function getCethBalance(address userAddress) public view returns(uint256) {
        return balances[userAddress];
    }
    
    function getEthBalance(address userAddress) public view returns(uint256) {
        return test[userAddress];
    }
    
    function getERC20Balance(address userAddress) public view returns(uint256) {
        return test2[userAddress];
    }
    
    function getExchangeRate() public view returns(uint256){
        return ceth.exchangeRateStored();
    }
    
    function withdrawMax() public payable {
        address payable tranferTo = payable(msg.sender);
        ceth.redeem(balances[msg.sender]);
        uint256 amountToTransfer = getBalance(msg.sender);
        totalContractBalance -= balances[msg.sender];
        balances[msg.sender] = 0;
        tranferTo.transfer(amountToTransfer);
    }
    
    function withdraw(uint amountOfEthToWithdraw) public payable {
        require(amountOfEthToWithdraw <= getBalance(msg.sender), "You don't have enough balance!");
        address payable tranferTo = payable(msg.sender);
        
        uint256 cEthWithdrawn =  _withdrawEthFromCompound(amountOfEthToWithdraw);
        
        totalContractBalance -= cEthWithdrawn;
        balances[msg.sender] -= cEthWithdrawn;
        tranferTo.transfer(amountOfEthToWithdraw);
    }
    
    function withdrawERC20Max(address erc20TokenSmartContractAddress) public {
        
        ceth.redeem(balances[msg.sender]);
        uint256 amountEthToSwap = getBalance(msg.sender);
        totalContractBalance -= balances[msg.sender];
        balances[msg.sender] = 0;
        
        uint256 erc20TokenAmount = _swapEthForTokens(erc20TokenSmartContractAddress, amountEthToSwap);
        
        test2[msg.sender] = erc20TokenAmount;
    }
    
    function _swapEthForTokens(address erc20TokenSmartContractAddress, uint256 amountEthToSwap) internal returns(uint256) {
        
        uint amountOutMin = 0; 
        address to = address(msg.sender);
        uint deadline = block.timestamp + (24 * 60 * 60);
        
        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = erc20TokenSmartContractAddress;
        
        uint256 erc20TokenAmount = uniswap.swapExactETHForTokens{value: amountEthToSwap}(amountOutMin, path, to, deadline)[1];
        
        return erc20TokenAmount;
    }
    
    function withdrawERC20(address erc20TokenSmartContractAddress, uint256 amountToWithdrawInToken) public {
        
        uint256 amountOfEthToWithdraw = _getEthAmountForERC20Token(erc20TokenSmartContractAddress, amountToWithdrawInToken);
        
        require(amountOfEthToWithdraw <= getBalance(msg.sender), "You don't have enough balance!");
        
        uint256 cEthWithdrawn =  _withdrawEthFromCompound(amountOfEthToWithdraw);
        
        
        totalContractBalance -= cEthWithdrawn;
        balances[msg.sender] -= cEthWithdrawn;
        
        uint256 erc20TokenAmount = _swapEthForTokens(erc20TokenSmartContractAddress, amountOfEthToWithdraw);
        
        test2[msg.sender] = erc20TokenAmount;
    }
    
    function _getEthAmountForERC20Token(address erc20TokenSmartContractAddress, uint256 amountToWithdrawInToken) internal view returns(uint256) {
        
        address[] memory path = new address[](2);
        path[0] = uniswap.WETH();
        path[1] = erc20TokenSmartContractAddress;
        
        
        uint256 amountOfEthToWithdraw = uniswap.getAmountsIn(amountToWithdrawInToken, path)[0];
        return amountOfEthToWithdraw;
    }
    
    function _withdrawEthFromCompound(uint256 _amountOfEthToWithdraw) internal returns (uint256) {
        
        uint256 cEthOfContractBeforeWithdraw = ceth.balanceOf(address(this));
        ceth.redeemUnderlying(_amountOfEthToWithdraw);
        uint256 cEthOfContractAfterWithdraw = ceth.balanceOf(address(this));
        
        uint256 cEthWithdrawn = cEthOfContractBeforeWithdraw - cEthOfContractAfterWithdraw;
        
        return cEthWithdrawn;
        
    }
    
    function addMoneyToContract() public payable {
        totalContractBalance += msg.value;
    }
}

