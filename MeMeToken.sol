// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IMemeSwapRouter {
  function factory() external pure returns(address);
}

interface IMemeSwapFactory {
  function createPair(address tokenA, address tokenB) external returns(address pair);
}

interface ILock {
  function transfer(address user, uint256 amount)  external;
}

contract MeMeToken is ERC20, Ownable {

  using SafeERC20
  for IERC20;
  using EnumerableSet
  for EnumerableSet.AddressSet;
  
  EnumerableSet.AddressSet private _list;

  IMemeSwapRouter public MemeSwapRouter;

  address public pairAddress;
  address public USDT;
  address public lockAddress;
  address public receiveAddress;

  constructor(address _router, address _usdt, string memory _name, string memory _symbol, uint256 _initialAmount, address _receiveAddress) ERC20(_name, _symbol) { 
    USDT = address(_usdt);
    receiveAddress = address(_receiveAddress);
    MemeSwapRouter = IMemeSwapRouter(_router);
    pairAddress = IMemeSwapFactory(MemeSwapRouter.factory())
      .createPair(address(this), USDT);
     _mint(receiveAddress, _initialAmount);
  }

   function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
     
      if(from != pairAddress && lockAddress != address(0)) {
        ILock(lockAddress).transfer(from, amount);
      }
    }
   function mintToken (uint256 _amount, address _user) external {
     require(isList(msg.sender), 'msgsender is not List');
     _mint(_user, _amount);
   }
  function addList(address account) external onlyOwner returns(bool) {
    require(account != address(0), "token: account is the zero address");
    _list.add(account);
    return true;
  }
  function delList(address account) external onlyOwner returns(bool) {
    require(account != address(0), "token: account is the zero address");
    _list.remove(account);
    return true;
  }
  

   function setLockAddress(address _lockAddress) external onlyOwner{
     lockAddress = _lockAddress;
     _list.add(lockAddress);
   }
  function getListLength() public view returns(uint256) {
    return _list.length();
  }

  function isList(address account) public view returns(bool) {
    return _list.contains(account);
  }
  
  function getList(uint256 _index) public view onlyOwner returns(address) {
    require(_index <= getListLength() - 1, "token: index out of bounds");
    return _list.at(_index);
  }
}