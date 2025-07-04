// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenMintErc20 is ERC20, Ownable {
  
  uint8 private tokenDecimals;
  constructor(string memory _name,string memory _symbol, uint8 _decimals ,uint256 _amount, address _receive) ERC20(_name, _symbol){
     tokenDecimals = _decimals;
     _mint(_receive, _amount);
  }
  function decimals() public view override returns (uint8) {
    return tokenDecimals;
  }
  
  function mint(address to, uint256 amount) external onlyOwner {
    _mint(to, amount);
  }

  function batchMint(address[] memory to, uint256[] memory amount) external onlyOwner {
    require(to.length == amount.length, "Invalid input");
    for (uint256 i = 0; i < to.length; i++) {
      _mint(to[i], amount[i]);
    }
  }
  function batchTransfer(address[] memory to, uint256[] memory amount) external {
    require(to.length == amount.length, "Invalid input");
    for (uint256 i = 0; i < to.length; i++) {
      _transfer(msg.sender, to[i], amount[i]);
    }
  }
}
