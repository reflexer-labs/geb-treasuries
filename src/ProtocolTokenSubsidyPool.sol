/// ProtocolTokenSubsidyPool.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>, 2020 Reflexer Labs, INC

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.7;

abstract contract TokenLike {
    function balanceOf(address) virtual public view returns (uint256);
    function move(address,address,uint256) virtual external;
}

contract ProtocolTokenSubsidyPool {
    // --- Auth ---
    mapping (address => uint256) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "ProtocolTokenSubsidyPool/account-not-authorized");
        _;
    }

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, address addr);
    event ModifyParameters(bytes32 parameter, uint256 val);
    event DisableContract();
    event SetTotalAllowance(address indexed account, uint256 wad);
    event SetPerBlockAllowance(address indexed account, uint256 wad);
    event GiveFunds(address indexed account, uint256 wad);
    event TakeFunds(address indexed account, uint256 wad);
    event PullFunds(address indexed sender, address indexed dstAccount, address token, uint256 wad);

    // --- Structs ---
    struct Allowance {
        uint256 total;
        uint256 perBlock;
    }

    // Allowances to pull protocol tokens
    mapping(address => Allowance)                   private allowance;
    // Amount of protocol tokens pulled per block by every allowed address
    mapping(address => mapping(uint256 => uint256)) public pulledPerBlock;

    TokenLike public protocolToken;

    modifier accountNotPool(address account) {
        require(account != address(this), "ProtocolTokenSubsidyPool/account-cannot-be-pool");
        _;
    }

    constructor(
        address protocolToken_
    ) public {
        require(protocolToken_ != address(0), "ProtocolTokenSubsidyPool/null-protocol-token");
        authorizedAccounts[msg.sender] = 1;
        protocolToken                  = TokenLike(protocolToken_);
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        require(z >= x, "ProtocolTokenSubsidyPool/add-uint-uint-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ProtocolTokenSubsidyPool/sub-uint-uint-underflow");
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Getters ---
    function getAllowance(address account) public view returns (uint256, uint256) {
        return (allowance[account].total, allowance[account].perBlock);
    }

    // --- Protocol Token Transfer Allowance ---
    /**
     * @notice Modify an address' total allowance in order to withdraw tokens from the pool
     * @param account The approved address
     * @param wad The total approved amount of protocol tokens to withdraw
     */
    function setTotalAllowance(address account, uint256 wad) external isAuthorized accountNotPool(account) {
        require(account != address(0), "ProtocolTokenSubsidyPool/null-account");
        allowance[account].total = wad;
        emit SetTotalAllowance(account, wad);
    }
    /**
     * @notice Modify an address' per block allowance in order to withdraw protocol tokens from the treasury
     * @param account The approved address
     * @param wad The per block approved amount of protocol tokens to withdraw
     */
    function setPerBlockAllowance(address account, uint256 wad) external isAuthorized accountNotPool(account) {
        require(account != address(0), "ProtocolTokenSubsidyPool/null-account");
        allowance[account].perBlock = wad;
        emit SetPerBlockAllowance(account, wad);
    }

    // --- Protocol Token Transfer (Governance) ---
    /**
     * @notice Governance transfers protocol tokens to an address
     * @param account Address to transfer tokens to
     * @param wad Amount of protocol tokens to transfer
     */
    function giveFunds(address account, uint256 wad) external isAuthorized accountNotPool(account) {
        require(account != address(0), "ProtocolTokenSubsidyPool/null-account");
        require(protocolToken.balanceOf(address(this)) >= wad, "ProtocolTokenSubsidyPool/not-enough-funds");
        protocolToken.move(address(this), account, wad);
        emit GiveFunds(account, wad);
    }
    /**
     * @notice Governance takes protocol tokens from an address
     * @param account Address to take system coins from
     * @param wad Amount of protocol tokens to take from the account
     */
    function takeFunds(address account, uint256 wad) external isAuthorized accountNotPool(account) {
        protocolToken.move(account, address(this), wad);
        emit TakeFunds(account, wad);
    }

    // --- Protocol Token Transfer (Approved Accounts) ---
    /**
     * @notice Pull protocol tokens from the pool (if your allowance permits)
     * @param dstAccount Address to transfer funds to
     * @param token Address of the token to transfer (in this case it must be the address of the ERC20 protocol token).
     *              Used only to adhere to a standard for automated, on-chain treasuries/pools of fundss
     * @param wad Amount of protocol tokens to transfer
     */
    function pullFunds(address dstAccount, address token, uint256 wad) external accountNotPool(dstAccount) {
	      require(allowance[msg.sender].total >= wad, "ProtocolTokenSubsidyPool/not-allowed");
        require(dstAccount != address(0), "ProtocolTokenSubsidyPool/null-dst");
        require(wad > 0, "ProtocolTokenSubsidyPool/null-transfer-amount");
        require(token == address(protocolToken), "ProtocolTokenSubsidyPool/token-unavailable");
        require(protocolToken.balanceOf(address(this)) >= wad, "ProtocolTokenSubsidyPool/not-enough-funds");

        if (allowance[msg.sender].perBlock > 0) {
          require(addition(pulledPerBlock[msg.sender][block.number], wad) <= allowance[msg.sender].perBlock, "ProtocolTokenSubsidyPool/per-block-limit-exceeded");
        }
        pulledPerBlock[msg.sender][block.number] = addition(pulledPerBlock[msg.sender][block.number], wad);

        // Update total allowance
        allowance[msg.sender].total = subtract(allowance[msg.sender].total, wad);

        // Transfer money
        protocolToken.move(address(this), dstAccount, wad);

        emit PullFunds(msg.sender, dstAccount, token, wad);
    }
}
