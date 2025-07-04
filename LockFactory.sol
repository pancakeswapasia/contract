// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "./MeMeToken.sol";

interface IMeme {
    function renounceOwnership() external;

    function addList(address account) external;

    function setLockAddress(address _lockAddress) external;

    function pairAddress() external view returns (address);
}

interface ILockPoolFactory {
    function createLockPool(
        address memeToken,
        address pairAddress,
        uint256 rate,
        uint256 lockTime,
        uint256 limitUsersToSupport,
        address owner
    ) external returns (address);
}

contract LockFactory is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    event CreateMemeLog(
        address indexed user,
        address memeAddress,
        address lockAddress,
        address pairAddress,
        string name,
        string symbol,
        uint256 initialAmount
    );

    struct LockInfo {
        string name;
        string symbol;
        uint256 initialAmount;
        address memeAddress;
        address lockAdderss;
        address pairAddress;
    }
    struct PairInfo {
        address memeAddress;
        address lockAdderss;
        address pairAddress;
    }

    address public lockPoolFactory;
    address public USDT;
    address public router;
    uint256 public lockTime;
    uint256 public rate;
    uint256 public limitUsersToSupport;



    EnumerableSetUpgradeable.AddressSet private _memeList;
    EnumerableSetUpgradeable.AddressSet private _pairList;

    mapping(address => LockInfo) public memeInfo;
    mapping(address => PairInfo) public pairInfo;

    mapping(address => EnumerableSetUpgradeable.AddressSet) private _userMemeList;

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        USDT = address(0x80b5a32E4F032B2a058b4F29EC95EEfEEB87aDcd);
        router = address(0x657E249859695c67124bE7EBf65B10E81f17aecF);
        lockPoolFactory = address(0x5cE245c6a574939B0dd5c9A347a2EE5D379C1843);
        lockTime = 86400;
        rate = 100;
        limitUsersToSupport = 1000;
    }

    function setLockPoolFactory(address _lockPoolFactory) external onlyOwner {
        lockPoolFactory = _lockPoolFactory;
    }

    function setLimitUsersToSupport(uint256 _limitUsersToSupport) external onlyOwner {
        limitUsersToSupport = _limitUsersToSupport;
    }

    function createMeme(
        string memory _name,
        string memory _symbol,
        uint256 _initialAmount,
        uint256 _limitSupport
    ) external nonReentrant {
        require(bytes(_name).length > 0, "name is empty");
        require(bytes(_symbol).length > 0, "symbol is empty");
        require(_initialAmount > 0, "amount is zero");
        require(_limitSupport >= limitUsersToSupport, 'limit Support is less than limitUsersToSupport');
        MeMeToken memeToken = new MeMeToken(
            router,
            USDT,
            _name,
            _symbol,
            _initialAmount,
            msg.sender
        );
        address pairAddress = IMeme(address(memeToken)).pairAddress();
        address lockTokenPool = ILockPoolFactory(lockPoolFactory).createLockPool(
            address(memeToken),
            pairAddress,
            rate,
            lockTime,
            _limitSupport,
            msg.sender
        );
        IMeme(address(memeToken)).addList(lockTokenPool);
        IMeme(address(memeToken)).setLockAddress(lockTokenPool);
        IMeme(address(memeToken)).renounceOwnership();
        memeInfo[address(memeToken)] = LockInfo(
            _name,
            _symbol,
            _initialAmount,
            address(memeToken),
            lockTokenPool,
            pairAddress
        );
        pairInfo[pairAddress] = PairInfo(
            address(memeToken),
            lockTokenPool,
            pairAddress
        );
        _memeList.add(address(memeToken));
        _pairList.add(pairAddress);
        _userMemeList[msg.sender].add(address(memeToken));
        emit CreateMemeLog(
            msg.sender,
            address(memeToken),
            lockTokenPool,
            pairAddress,
            _name,
            _symbol,
            _initialAmount 
        );
    }

    function getIsMeme(address _meme) public view returns (bool) {
        return _memeList.contains(_meme);
    }

    function getIsPair(address _pair) public view returns (bool) {
        return _pairList.contains(_pair);
    }

    function getMemeInfo(
        address _meme
    ) public view returns (address _memeToken, address _lock, address _pair, address _router, address _usdt) {
        return (
            memeInfo[_meme].memeAddress,
            memeInfo[_meme].lockAdderss,
            memeInfo[_meme].pairAddress,
            router,
            USDT
        );
    }

    function searchMemeInfo(address _meme) public view returns (LockInfo memory) {
      return memeInfo[_meme];
    }

    function getPairInfo(
        address _pair
    )
        public
        view
        returns (address _memeToken, address _lock, address _pairToken)
    {
        return (
            pairInfo[_pair].memeAddress,
            pairInfo[_pair].lockAdderss,
            pairInfo[_pair].pairAddress
        );
    }

    function getMemeList(
        uint256 _page,
        uint256 _limit
    ) external view returns (LockInfo[] memory list, uint256 total) {
        uint256 length = _memeList.length();
        list = new LockInfo[](_limit);
        total = length;
        uint256 start = length > (_page - 1) * _limit
            ? length - (_page - 1) * _limit
            : 0;
        uint256 end = _page * _limit >= length ? 0 : length - _page * _limit;
        for (uint256 i = start; i > end; i--) {
            list[start - i] = memeInfo[_memeList.at(i - 1)];
        }
    }

    function getUserMemeList(
        address _user
    ) external view returns (LockInfo[] memory list) {
      uint256 length = _userMemeList[_user].length();
      list = new LockInfo[](length);
      for (uint256 i = 0; i < length; i++) {
        list[i] = memeInfo[_userMemeList[_user].at(i)];
      }
    }
}
