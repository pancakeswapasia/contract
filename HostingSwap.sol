// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

interface IMemeRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface ILock {
    function getUserLock(address _user) external view returns (uint256);

    function increaseTrueReward(address _user, uint256 _reward) external;

    function rate() external view returns (uint256);

    function lockTime() external view returns (uint256);
}

interface ILockFactory {
    function getMemeInfo(
        address _meme
    )
        external
        view
        returns (
            address _memeToken,
            address _lock,
            address _pair,
            address _router,
            address _usdt
        );
}

contract HostingSwap is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    event HostSwapLog(address indexed user, uint256 balance, uint256 time);
    event UserLockHostingLog(
        address indexed user,
        uint256 balance,
        uint256 amount,
        uint256 bnbFee,
        uint256 time
    );
    event AddBnbFeeLog(address indexed user, uint256 bnbFee, uint256 time);
    event QuitLog(address indexed user, uint256 time);
    event WithdrawRewardLog(address indexed user, uint256 reward, uint256 time);
    struct User {
        address userAddress;
        uint256 balance;
        uint256 bnbFee;
        uint256 time;
    }

    struct Record {
        uint256 id;
        address user;
        uint256 sellMemeAmount;
        uint256 sellUsdtAmount;
        uint256 buyUsdtAmount;
        uint256 buyMemeAmount;
        uint256 bnbFee;
        uint256 loss;
        uint256 time;
        uint256 reward;
        bool rewardIsGet;
    }

    EnumerableSetUpgradeable.AddressSet private _users;

    address public platformCoin;
    address public lockFactory;
    address public lockAddress;
    address public controller;
    address public USDT;
    uint256 public swapFee;
    uint256 public initGasPrice;

    IMemeRouter public memeRouter;
    mapping(address => User) public userInfo;
    mapping(address => uint256) public recordId;
    mapping(address => mapping(uint256 => Record)) public recordInfo;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        platformCoin = address(0xfe5820511Ee815971dFa96153C6934eBb2f9821e);
        lockFactory = address(0x18FeAE0DFEB8EE89f88d53d1f41d4173A48Df9a2);
        (, address _lock, , address _router, address _usdt) = ILockFactory(
            lockFactory
        ).getMemeInfo(platformCoin);
        USDT = address(_usdt);
        lockAddress = address(_lock);
        controller = address(0x6bd229C33885976E0E1E1c655Eb678e6CbfE1aF9);
        swapFee = 0.001 ether;
        memeRouter = IMemeRouter(_router);
        initGasPrice = 1000000000;
        // set the rest of the contract variables
        _approve();
    }

    function _approve() private {
        IERC20Upgradeable(USDT).approve(address(memeRouter), type(uint256).max);
        IERC20Upgradeable(platformCoin).approve(
            address(memeRouter),
            type(uint256).max
        );
    }

    function setInitGasPrice(uint256 _initGasPrice) external onlyOwner {
        initGasPrice = _initGasPrice;
    }

    function setSwapFee(uint256 _swapFee) external onlyOwner {
        swapFee = _swapFee;
    }

    modifier onlyController() {
        require(msg.sender == controller, "is not controller");
        _;
    }

    function setController(address _controller) external onlyController {
        controller = _controller;
    }

    function _settleReward(address _user) private {
        uint256 lockTime = ILock(lockAddress).lockTime();
        Record memory info = recordInfo[_user][recordId[_user]];
        if (
            info.buyMemeAmount > 0 &&
            !info.rewardIsGet &&
            info.time + lockTime <= block.timestamp
        ) {
            ILock(lockAddress).increaseTrueReward(
                _user,
                recordInfo[_user][recordId[_user]].buyMemeAmount
            );
            uint256 rate = ILock(lockAddress).rate();
            recordInfo[_user][recordId[_user]].reward =
                (info.buyMemeAmount * rate) /
                10000;
            userInfo[_user].balance += (info.buyMemeAmount * rate) / 10000;
        }
        if (recordId[_user] != 0) {
            recordInfo[_user][recordId[_user]].rewardIsGet = true;
        }
    }

    function userLockHosting(uint256 amount) external payable nonReentrant {
        require(amount > 0, "amount is 0");
        uint256 lockAmount = ILock(lockAddress).getUserLock(msg.sender);
        require(lockAmount > 0, "not lock");
        if (!_users.contains(msg.sender)) {
            _users.add(msg.sender);
            userInfo[msg.sender].userAddress = msg.sender;
        }
        if (msg.value > 0) {
            userInfo[msg.sender].bnbFee += msg.value;
        }
        IERC20Upgradeable(USDT).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        _settleReward(msg.sender);
        recordId[msg.sender] += 1;
        userInfo[msg.sender].time = block.timestamp;
        uint256 newAmount = _buy(msg.sender, amount);
        userInfo[msg.sender].balance += newAmount;
        emit UserLockHostingLog(
            msg.sender,
            amount,
            newAmount,
            msg.value,
            block.timestamp
        );
    }

    function _buy(
        address user,
        uint256 amount
    ) private returns (uint256 newAmount) {
        address[] memory buyPath = new address[](2);
        buyPath[0] = USDT;
        buyPath[1] = platformCoin;
        uint256[] memory buyAmounts = memeRouter.swapExactTokensForTokens(
            amount,
            0,
            buyPath,
            address(this),
            block.timestamp
        );
        newAmount = buyAmounts[1];
        recordInfo[user][recordId[user]].id = recordId[user];
        recordInfo[user][recordId[user]].user = user;
        recordInfo[user][recordId[user]].buyUsdtAmount = amount;
        recordInfo[user][recordId[user]].buyMemeAmount = newAmount;
        recordInfo[user][recordId[user]].time = block.timestamp;
    }

    function _sellAndBuy(
        address user,
        uint256 amount
    ) private returns (uint256 newAmount) {
        address[] memory sellPath = new address[](2);
        sellPath[0] = platformCoin;
        sellPath[1] = USDT;
        address[] memory buyPath = new address[](2);
        buyPath[0] = USDT;
        buyPath[1] = platformCoin;
        uint256[] memory sellAmounts = memeRouter.swapExactTokensForTokens(
            amount,
            0,
            sellPath,
            address(this),
            block.timestamp
        );
        uint256[] memory buyAmounts = memeRouter.swapExactTokensForTokens(
            sellAmounts[1],
            (amount * 99) / 100,
            buyPath,
            address(this),
            block.timestamp
        );
        newAmount = buyAmounts[1];
        recordInfo[user][recordId[user]].id = recordId[user];
        recordInfo[user][recordId[user]].user = user;
        recordInfo[user][recordId[user]].sellMemeAmount = amount;
        recordInfo[user][recordId[user]].sellUsdtAmount = sellAmounts[1];
        recordInfo[user][recordId[user]].buyUsdtAmount = sellAmounts[1];
        recordInfo[user][recordId[user]].buyMemeAmount = newAmount;
        recordInfo[user][recordId[user]].loss = amount - newAmount;
        recordInfo[user][recordId[user]].time = block.timestamp;
    }

    function hostSwap(address _user) external nonReentrant onlyController {
        uint256 gas = gasleft();
        uint256 lockTime = ILock(lockAddress).lockTime();
        require(userInfo[_user].bnbFee >= swapFee, "Insufficient expenses");
        require(_users.contains(_user), "user not exist");
        require(
            userInfo[_user].time + lockTime <= block.timestamp,
            "less than time"
        );
        require(userInfo[_user].balance > 0, "not hosting");
        _settleReward(_user);
        userInfo[_user].time = block.timestamp;
        recordId[_user] += 1;
        uint256 newAmount = _sellAndBuy(_user, userInfo[_user].balance);
        userInfo[_user].balance = newAmount;
        userInfo[_user].time = block.timestamp;

        emit HostSwapLog(_user, newAmount, block.timestamp);
        uint256 takeGas = gas - gasleft() + 32000;
        uint256 fee = takeGas * initGasPrice;
        require(userInfo[_user].bnbFee >= fee, "Insufficient BNB fee");
        userInfo[_user].bnbFee -= fee;
        recordInfo[_user][recordId[_user]].bnbFee = fee;
        payable(msg.sender).transfer(fee);
    }

    function addBnbFee() external payable nonReentrant {
        require(msg.value > 0, "value is 0");
        require(
            _users.contains(msg.sender) && userInfo[msg.sender].balance > 0,
            "msgSender not lock"
        );
        userInfo[msg.sender].bnbFee += msg.value;
        emit AddBnbFeeLog(msg.sender, msg.value, block.timestamp);
    }

    function userUnlockHosting(uint256 amount) external nonReentrant {
        require(userInfo[msg.sender].balance > 0, "not hosting");
        require(
            userInfo[msg.sender].balance >= amount,
            "balance is less than amount"
        );
        recordInfo[msg.sender][recordId[msg.sender]].rewardIsGet = true;
        userInfo[msg.sender].balance -= amount;
        IERC20Upgradeable(platformCoin).safeTransfer(msg.sender, amount);
    }

    function getReward(
        address user
    ) public view returns (uint256 reward, uint256 endTime, bool canWithdraw) {
        uint256 lockTime = ILock(lockAddress).lockTime();
        uint256 rate = ILock(lockAddress).rate();
        if (
            recordId[user] == 0 || recordInfo[user][recordId[user]].rewardIsGet
        ) {
            return (0, 0, false);
        }
        if (
            recordInfo[user][recordId[user]].time + lockTime > block.timestamp
        ) {
            return (
                (recordInfo[user][recordId[user]].buyMemeAmount * rate) / 10000,
                recordInfo[user][recordId[user]].time + lockTime,
                false
            );
        } else {
            return (
                (recordInfo[user][recordId[user]].buyMemeAmount * rate) / 10000,
                recordInfo[user][recordId[user]].time + lockTime,
                true
            );
        }
    }

    function withdrawReward() external nonReentrant {
        (uint256 reward, , bool canWithdraw) = getReward(msg.sender);
        require(canWithdraw, "can not withdraw");
        ILock(lockAddress).increaseTrueReward(
            msg.sender,
            recordInfo[msg.sender][recordId[msg.sender]].buyMemeAmount
        );
        userInfo[msg.sender].balance += reward;
        recordInfo[msg.sender][recordId[msg.sender]].reward = reward;
        recordInfo[msg.sender][recordId[msg.sender]].rewardIsGet = true;
        emit WithdrawRewardLog(msg.sender, reward, block.timestamp);
    }

    function quit() external nonReentrant {
        require(_users.contains(msg.sender), "user not exist");
        _settleReward(msg.sender);
        userInfo[msg.sender].time = block.timestamp;
        if (userInfo[msg.sender].balance > 0) {
            IERC20Upgradeable(platformCoin).safeTransfer(
                msg.sender,
                userInfo[msg.sender].balance
            );
            userInfo[msg.sender].balance = 0;
        }
        if (userInfo[msg.sender].bnbFee > 0) {
            payable(msg.sender).transfer(userInfo[msg.sender].bnbFee);
            userInfo[msg.sender].bnbFee = 0;
        }
        emit QuitLog(msg.sender, block.timestamp);
    }

    function getUserRecords(
        address user,
        uint256 _page,
        uint256 _limit
    ) external view returns (Record[] memory recordArr, uint256 total) {
        uint256 length = recordId[user];
        recordArr = new Record[](_limit);
        total = length;
        uint256 start = length > (_page - 1) * _limit
            ? length - (_page - 1) * _limit
            : 0;
        uint256 end = _page * _limit >= length ? 0 : length - _page * _limit;
        for (uint256 i = start; i > end; i--) {
            recordArr[start - i] = recordInfo[user][i];
        }
    }

    function getCurTime() external view returns (uint256) {
        return block.timestamp;
    }
}
