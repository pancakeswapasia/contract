// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "./TokenMint.sol";

contract TokenFactory is Initializable, ReentrancyGuardUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    event CreateTokenLog(
        address indexed user,
        address indexed token,
        uint256 time
    );
    struct Token {
        address tokenAddress;
        uint8 decimals;
        string symbol;
        address creator;
        uint256 amount;
        uint256 time;
    }

    mapping(address => EnumerableSetUpgradeable.AddressSet)
        private userCreateTokens;
    mapping(address => Token) public tokenInfo;

    function initialize() public initializer {
        __ReentrancyGuard_init();
    }

    function createToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 amount
    ) external nonReentrant {
        require(decimals >= 9 && decimals <= 18, "decimals invalid");
        require(bytes(name).length > 0, "name is empty");
        require(bytes(symbol).length > 0, "symbol is empty");
        require(amount > 0, "amount is 0");
        TokenMintErc20 token = new TokenMintErc20(
            name,
            symbol,
            decimals,
            amount,
            msg.sender
        );
        token.transferOwnership(msg.sender);
        address tokenAddress = address(token);
        tokenInfo[tokenAddress] = Token(
            tokenAddress,
            decimals,
            symbol,
            msg.sender,
            amount,
            block.timestamp
        );
        userCreateTokens[msg.sender].add(tokenAddress);
        emit CreateTokenLog(msg.sender, tokenAddress, block.timestamp);
    }

    function getUserCreateTokens(
        address _user
    ) external view returns (Token[] memory tokens) {
        uint256 length = userCreateTokens[_user].length();
        tokens = new Token[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = tokenInfo[userCreateTokens[_user].at(i)];
        }
    }
}
