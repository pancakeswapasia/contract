// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./LockTokenPool.sol";


interface ILockPool {
    function renounceOwnership() external;
}

contract LockPoolFactory is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{

   event CreateLockPoolLog(
        address indexed user,
        address lockAddress
    );

   address public lockFactory;

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    function setLockFactory(address _lockFactory) external onlyOwner {
        lockFactory = _lockFactory;
    }

    modifier onlyLockFactory() {
        require(msg.sender == lockFactory, "is not lockFactory");
        _;
    }

    function createLockPool(
        address memeToken,
        address pairAddress,
        uint256 rate,
        uint256 lockTime,
        uint256 limitUsersToSupport,
        address owner
    ) external onlyLockFactory nonReentrant returns (address) {
   
        LockTokenPool lockTokenPool = new LockTokenPool(
            memeToken,
            pairAddress,
            rate,
            lockTime,
            limitUsersToSupport
        );
        ILockPool(address(lockTokenPool)).renounceOwnership();
        emit CreateLockPoolLog(
            owner,
            address(lockTokenPool)
        );
        return address(lockTokenPool);
    }
}
