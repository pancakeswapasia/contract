// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IPlatformToken {
  function mintToken (uint256 _amount, address _user) external;
}


contract LockTokenPool is Ownable, ReentrancyGuard{

  using SafeERC20 for IERC20;
      using EnumerableSet
  for EnumerableSet.AddressSet;

   event ApplyToken(address indexed user,address indexed token, address indexed principal, uint256 time);
   event SupportTokenLog(address indexed token, address indexed principal,uint256 time);
   event LockTokenLog(address indexed user, address indexed token, uint256 lockAmount, uint256 platformCoinAmount, uint256 time);
   event UnLockTokenLog(address indexed user, address indexed token, uint256 platformCoinAmount, uint256 unLockAmount, uint256 time);
   event WithdrawRewardLog(address indexed user, address indexed token, address indexed principal,uint256 reward, uint256 tokenReward, uint256 time);
   struct Token {
     address tokenAddress;
     uint8 decimals;
     string symbol;
     address principal;
     bool isSupport;
     uint256 time;
   }

   struct User {
     uint256 reward;
     uint256 trueReward;
     uint256 lastTime;
   }

   struct LockInfo {
     uint256 tokenAmount;
     uint256 lockAmount;
   }

   EnumerableSet.AddressSet private applyTokens;
   EnumerableSet.AddressSet private supportTokens;
   
   address public platformCoin;
   address public pairAddress;
   address public hostingSwapAddress;
   uint256 public lockTime;
   uint256 public rate;
   uint256 public limitUsersToSupport;
   mapping(address => User) public userInfo;
   mapping(address => EnumerableSet.AddressSet) private userLockTokens;
   mapping(address => mapping (address => LockInfo)) private userLockInfos;
   mapping(address => Token) public tokenInfo;
   
   mapping(address => EnumerableSet.AddressSet) private principalAddTokens;
   mapping(address => EnumerableSet.AddressSet) private tokenLockUsers;

   EnumerableSet.AddressSet private joinUsers;
   
    constructor(address _meme, address _pairAddress, uint256 _rate, uint256 _lockTime, uint256 _limitUsersToSupport) {
     platformCoin = address(_meme);
     pairAddress = address(_pairAddress);
     rate = _rate;
     lockTime = _lockTime;
     limitUsersToSupport = _limitUsersToSupport;
   }
  // function setLockTime(uint256 _lockTime) external onlyOwner {
  //    lockTime = _lockTime;
  //  }
  //  function setLimitUsersToSupport(uint256 _limitUsersToSupport) external onlyOwner {
  //    limitUsersToSupport = _limitUsersToSupport;
  //  }
  // function setHostingSwapAddress(address _hostingSwapAddress)  external onlyOwner {
  //   hostingSwapAddress = _hostingSwapAddress;
  // }
  // function setRate(uint256 _rate) external onlyOwner {
  //   rate = _rate;
  // }
  modifier onlyPair() {
        require(msg.sender == pairAddress, "is not pairAddress");
        _;
    }
    modifier onlyPlatformCoin() {
        require(msg.sender == platformCoin, "is not platformCoin");
        _;
    }
    // modifier onlyHostingSwap() {
    //     require(msg.sender == hostingSwapAddress, "is not hostingSwapAddress");
    //     _;
    // }
    function _supportToken(address _token) private {
      if(!supportTokens.contains(_token)) {
        supportTokens.add(_token);
        tokenInfo[_token].isSupport = true;
        emit SupportTokenLog(_token, tokenInfo[_token].principal,block.timestamp);
      }
    }
    function applyToken(address _token, address _principal) external nonReentrant {
      require(!applyTokens.contains(_token), 'apply Token is exist');
      require(!supportTokens.contains(_token), 'support Tokens is exist');
      Token memory info = tokenInfo[_token];
      info.tokenAddress = _token;
      info.decimals = IERC20Metadata(_token).decimals();
      info.symbol = IERC20Metadata(_token).symbol();
      info.principal = _principal;
      info.time = block.timestamp;
      tokenInfo[_token] = info;
      applyTokens.add(_token);
      principalAddTokens[_principal].add(_token);
      emit ApplyToken(msg.sender, _token, _principal, block.timestamp);
    }
    function getSupportTokens () external view returns(Token[] memory tokenArr){
      uint256 length = supportTokens.length();
      tokenArr = new Token[](length);
      for(uint256 i = 0; i < length; i++){
        tokenArr[i] = tokenInfo[supportTokens.at(i)];
      }  
    }
    function getApplyTokens () external view returns(Token[] memory tokenArr){
      uint256 length = applyTokens.length();
      tokenArr = new Token[](length);
      for(uint256 i = 0; i < length; i++){
        tokenArr[i] = tokenInfo[applyTokens.at(i)];
      }  
    }
    function getApplyTokensByPage(uint256 _page, uint256 _limit) external view returns(Token[] memory tokenArr, uint256 total){
       uint256 length = applyTokens.length();
      tokenArr = new Token[](_limit);
      total = length;
      uint256 start = (_page - 1) * _limit;
      uint256 end  = _page * _limit >= length ? length : _page * _limit;
      for(uint256 i = start; i < end; i++){
        tokenArr[i - start] = tokenInfo[applyTokens.at(i)];
      }  
    }
    function getTokenLockNumbers () external view returns(uint256[] memory numbers){
      uint256 length = applyTokens.length();
      numbers = new uint256[](length);
      for(uint256 i = 0; i < length; i++){
        numbers[i] = tokenLockUsers[applyTokens.at(i)].length();
      }  
    }
    function getTokenLockNumbersByPage(uint256 _page, uint256 _limit) external view returns(uint256[] memory numbers ,uint256 total){
      uint256 length = applyTokens.length();
      numbers = new uint256[](_limit);
      total = length;
      uint256 start = (_page - 1) * _limit;
      uint256 end  = _page * _limit >= length ? length : _page * _limit;
      for(uint256 i = start; i < end; i++){
        numbers[i - start] = tokenLockUsers[applyTokens.at(i)].length();
      }  
    }
    function lockToken(address _token,uint256 _amount) external nonReentrant{
     require(applyTokens.contains(_token), 'apply Tokens is no exist');
     require(_amount > 0, '_amount is 0');
     require(IERC20(_token).balanceOf(msg.sender) >= _amount, 'Insufficient token balance');
    
     uint256 amount = getPlatformTokenAmount(_token,_amount);
     IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

     if(!userLockTokens[msg.sender].contains(_token)) {
       userLockTokens[msg.sender].add(_token);
     }
     if(!tokenLockUsers[_token].contains(msg.sender)) {
      tokenLockUsers[_token].add(msg.sender);
     }
     if(!joinUsers.contains(msg.sender)) {
       joinUsers.add(msg.sender);
     }
     userLockInfos[msg.sender][_token].tokenAmount += _amount;
     userLockInfos[msg.sender][_token].lockAmount += amount;
     if(tokenLockUsers[_token].length() >= limitUsersToSupport && !supportTokens.contains(_token)) {
       _supportToken(_token);
     }
     emit LockTokenLog(msg.sender, _token, _amount, amount, block.timestamp);
   }

   function unLockToken(address _token) external nonReentrant{
      require(userLockTokens[msg.sender].contains(_token), 'user is not lock');
      uint256 amount = userLockInfos[msg.sender][_token].lockAmount;
      uint256 tokenAmount = userLockInfos[msg.sender][_token].tokenAmount;
      userLockInfos[msg.sender][_token].lockAmount -= amount;
      userLockInfos[msg.sender][_token].tokenAmount -= tokenAmount;
      IERC20(_token).safeTransfer(msg.sender, tokenAmount);
      if (tokenLockUsers[_token].contains(msg.sender)) {
        tokenLockUsers[_token].remove(msg.sender);
      }
      emit UnLockTokenLog(msg.sender, _token, amount, tokenAmount, block.timestamp);
   }
   function buy(address user, uint256 amount)  external onlyPair{
      uint256 lockAmount = getUserLock(user);
      if (lockAmount > 0) {
        uint256 reward = getReward(user);
        if(reward > 0) {
          userInfo[user].trueReward += reward;
          userInfo[user].reward = 0;
        }
        userInfo[user].reward = userInfo[user].reward + amount;
        userInfo[user].lastTime = block.timestamp;
      }
   }
   function transfer(address user, uint256 amount)  external onlyPlatformCoin{ 
      uint256 lockAmount = getUserLock(user);
      if (lockAmount > 0) {
        uint256 reward = getReward(user);
        if(reward > 0) {
          userInfo[user].trueReward += reward;
          userInfo[user].reward = 0;
          userInfo[user].lastTime = block.timestamp;
        } else {
          userInfo[user].reward = userInfo[user].reward > amount ? userInfo[user].reward - amount : 0;
          userInfo[user].lastTime = block.timestamp;
        }       
      }
   }
   function _withdrawReward(address _user, uint256 reward, uint256 lockAmount) private {
     uint256 length = userLockTokens[_user].length();
     for (uint256 i = 0; i < length; i++) {
       address token = userLockTokens[_user].at(i);
       if(tokenInfo[token].isSupport) {
          uint256 memeAmount = userLockInfos[_user][token].lockAmount * reward / lockAmount;
          userLockInfos[_user][token].lockAmount -= memeAmount;
          userLockInfos[_user][token].tokenAmount -= getTokenPlatformAmount(token, memeAmount);
          emit WithdrawRewardLog(_user, token, tokenInfo[token].principal ,reward, memeAmount,block.timestamp);
       }
       
     }
   }
  //  function increaseTrueReward(address _user, uint256 _reward) external onlyHostingSwap {
  //    uint256 reward = _reward * rate / 10000;
  //    uint256 lockAmount = getUserLock(_user);
  //    require(lockAmount >= reward);
  //    IPlatformToken(platformCoin).mintToken(reward, msg.sender);
  //    _withdrawReward(_user, reward, lockAmount);
  //  }
   function withdrawReward() external nonReentrant {
     uint256 reward = getTotalReward(msg.sender);
     uint256 temReward = getReward(msg.sender);
     uint256 lockAmount = getUserLock(msg.sender);
     require(reward > 0, 'no reward');
     require(reward <= lockAmount, 'user lock is no enough');
      if(temReward > 0) {
        userInfo[msg.sender].reward = 0;
        userInfo[msg.sender].lastTime = block.timestamp;
      }
      userInfo[msg.sender].trueReward = 0;
      IPlatformToken(platformCoin).mintToken(reward, msg.sender);
     _withdrawReward(msg.sender, reward, lockAmount);
   }
   function getPlatformTokenAmount (address _token,uint256 _amount) public view returns(uint256 amount) {
     uint8 tokenDec = IERC20Metadata(_token).decimals();
     uint8 platformCoinDec = IERC20Metadata(platformCoin).decimals();
     amount = _amount * (10 ** platformCoinDec) / 10 ** tokenDec;
   }
   function getTokenPlatformAmount (address _token,uint256 _amount) public view returns(uint256 amount) {
     uint8 tokenDec = IERC20Metadata(_token).decimals();
     uint8 platformCoinDec = IERC20Metadata(platformCoin).decimals();
     amount = _amount * 10 ** tokenDec / (10 ** platformCoinDec);
   }

   function getUserData(address _user) external view returns(User memory info) {
    return userInfo[_user];
   }
   function getReward(address _user) public view returns(uint256 _reward) {
    uint256 reward = userInfo[_user].reward;
    uint256 time = userInfo[_user].lastTime;
    if(block.timestamp >= time + lockTime) {
      _reward = reward * rate / 10000;
    } else {
      _reward = 0;
    }
  }
  function getTotalReward (address _user) public view returns(uint256 total) {
    uint256 reward = getReward(_user);
    total = userInfo[_user].trueReward + reward;
  }
  function getUserLock(address _user) public view returns(uint256 lockAmount){
    uint256 length = userLockTokens[_user].length();
     
     for (uint256 i = 0; i < length; i++) {
       address token = userLockTokens[_user].at(i);
       if(tokenInfo[token].isSupport) {
         lockAmount += userLockInfos[_user][token].lockAmount;
       }
     }
  }
  function getUserLockInfos (address _user) external view returns(LockInfo[] memory lockInfos){
      uint256 length = userLockTokens[_user].length();
      lockInfos = new LockInfo[](length);
      for(uint256 i = 0; i < length; i++){
        lockInfos[i] = userLockInfos[_user][userLockTokens[_user].at(i)];
      }  
    }
    function getUserLockTokens (address _user) external view returns(Token[] memory tokens){
      uint256 length = userLockTokens[_user].length();
      tokens = new Token[](length);
      for(uint256 i = 0; i < length; i++){
        tokens[i] = tokenInfo[userLockTokens[_user].at(i)];
      }  
    }
  function getPrincipalAddTokens(address _principal) external view returns(Token[] memory tokens) {
    uint256 length = principalAddTokens[_principal].length();
    tokens = new Token[](length);
    for (uint256 i = 0; i < length; i++) {
      tokens[i] = tokenInfo[principalAddTokens[_principal].at(i)];
    }
  }
   function getPrincipalTokenLockNumbers (address _principal) external view returns(uint256[] memory numbers){
     uint256 length = principalAddTokens[_principal].length();
      numbers = new uint256[](length);
      for(uint256 i = 0; i < length; i++){
        numbers[i] = tokenLockUsers[principalAddTokens[_principal].at(i)].length();
      }  
    }
   function getJoinUserLength() external view returns(uint256) {
     return joinUsers.length();
   }
}