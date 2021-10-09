/// MultiSecondaryStabilityFeeTreasury.sol

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

abstract contract SAFEEngineLike {
    function denySAFEModification(bytes32,address) virtual external;
    function transferInternalCoins(bytes32,address,address,uint256) virtual external;
    function settleDebt(bytes32,uint256) virtual external;
    function coinBalance(bytes32,address) virtual public view returns (uint256);
    function debtBalance(bytes32,address) virtual public view returns (uint256);
}
abstract contract SystemCoinLike {
    function balanceOf(address) virtual public view returns (uint256);
    function approve(address, uint256) virtual public returns (uint256);
    function transfer(address,uint256) virtual public returns (bool);
    function transferFrom(address,address,uint256) virtual public returns (bool);
}
abstract contract CoinJoinLike {
    function coinName() virtual public view returns (bytes32);
    function systemCoin() virtual public view returns (address);
    function join(address, uint256) virtual external;
}

contract MultiSecondaryStabilityFeeTreasury {
    // --- Auth ---
    mapping (bytes32 => mapping(address => uint256)) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        authorizedAccounts[coinName][account] = 1;
        emit AddAuthorization(coinName, account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        authorizedAccounts[coinName][account] = 0;
        emit RemoveAuthorization(coinName, account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized(bytes32 coinName) {
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiSecondaryStabilityFeeTreasury/account-not-authorized");
        _;
    }

    /**
     * @notice Checks whether a coin is initialized
     */
    modifier coinIsInitialized(bytes32 coinName) {
        require(coinInitialized[coinName] == 1, "MultiSecondaryStabilityFeeTreasury/coin-not-init");

        _;
    }

    /**
     * @notice Checks that an address is not this contract
     */
    modifier accountNotTreasury(address account) {
        require(account != address(this), "MultiSecondaryStabilityFeeTreasury/account-cannot-be-treasury");
        _;
    }

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event ModifyParameters(bytes32 parameter, address addr);
    event GiveFunds(bytes32 indexed coinName, address indexed account, uint256 rad);
    event TakeFunds(bytes32 indexed coinName, address indexed account, uint256 rad);
    event InitializeCoin(
      bytes32 indexed coinName,
      address coinJoin
    );

    // --- Variables ---
    // Manager address
    address                                                             public manager;
    // Address of the deployer
    address                                                             public deployer;

    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256)                                        public coinInitialized;
    // Mapping of all system coin addresses
    mapping(bytes32 => address)                                         public systemCoin;
    // Coin join contracts
    mapping(bytes32 => address)                                         public coinJoin;

    SAFEEngineLike public safeEngine;

    constructor(
        address safeEngine_
    ) public {
        manager    = msg.sender;
        deployer   = msg.sender;
        safeEngine = SAFEEngineLike(safeEngine_);
    }

    // --- Math ---
    uint256 constant HUNDRED = 10 ** 2;
    uint256 constant RAY     = 10 ** 27;

    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        require(z >= x, "MultiSecondaryStabilityFeeTreasury/add-uint-uint-overflow");
    }
    function addition(int256 x, int256 y) internal pure returns (int256 z) {
        z = x + y;
        if (y <= 0) require(z <= x, "MultiSecondaryStabilityFeeTreasury/add-int-int-underflow");
        if (y  > 0) require(z > x, "MultiSecondaryStabilityFeeTreasury/add-int-int-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiSecondaryStabilityFeeTreasury/sub-uint-uint-underflow");
    }
    function subtract(int256 x, int256 y) internal pure returns (int256 z) {
        z = x - y;
        require(y <= 0 || z <= x, "MultiSecondaryStabilityFeeTreasury/sub-int-int-underflow");
        require(y >= 0 || z >= x, "MultiSecondaryStabilityFeeTreasury/sub-int-int-overflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiSecondaryStabilityFeeTreasury/mul-uint-uint-overflow");
    }
    function divide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "MultiSecondaryStabilityFeeTreasury/div-y-null");
        z = x / y;
        require(z <= x, "MultiSecondaryStabilityFeeTreasury/div-invalid");
    }
    function minimum(uint256 x, uint256 y) internal view returns (uint256 z) {
        z = (x <= y) ? x : y;
    }

    // --- Administration ---
    /**
     * @notice Initialize a new coin
     * @param coinName The name of the coin to initialize
     * @param coinJoin_ The coin join address for the coin
     */
    function initializeCoin(
        bytes32 coinName,
        address coinJoin_
    ) external {
        require(deployer == msg.sender, "MultiSecondaryStabilityFeeTreasury/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiSecondaryStabilityFeeTreasury/already-init");
        require(address(safeEngine) != address(0), "MultiSecondaryStabilityFeeTreasury/null-safe-engine");

        require(address(CoinJoinLike(coinJoin_).systemCoin()) != address(0), "MultiSecondaryStabilityFeeTreasury/null-system-coin");
        require(CoinJoinLike(coinJoin_).coinName() == coinName, "MultiSecondaryStabilityFeeTreasury/invalid-join-coin-name");

        authorizedAccounts[coinName][msg.sender] = 1;

        coinInitialized[coinName]           = 1;

        coinJoin[coinName]                  = coinJoin_;
        systemCoin[coinName]                = CoinJoinLike(coinJoin_).systemCoin();

        SystemCoinLike(systemCoin[coinName]).approve(coinJoin_, uint256(-1));

        emit InitializeCoin(
          coinName,
          coinJoin_
        );
        emit AddAuthorization(coinName, msg.sender);
    }
    /**
     * @notice Set an address param
     * @param parameter The name of the parameter to change
     * @param data The new manager
     */
    function modifyParameters(bytes32 parameter, address data) external {
        require(manager == msg.sender, "MultiSecondaryStabilityFeeTreasury/invalid-manager");
        if (parameter == "manager") {
          manager = data;
        } else if (parameter == "deployer") {
          require(data != address(0), "MultiSecondaryStabilityFeeTreasury/null-deployer");
          deployer = data;
        }
        else revert("MultiSecondaryStabilityFeeTreasury/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    /**
     * @notice Join all ERC20 system coins that the treasury has inside the SAFEEngine
     * @param coinName Name of the coin to join
     */
    function joinAllCoins(bytes32 coinName) internal {
        if (SystemCoinLike(systemCoin[coinName]).balanceOf(address(this)) > 0) {
          CoinJoinLike(coinJoin[coinName]).join(address(this), SystemCoinLike(systemCoin[coinName]).balanceOf(address(this)));
        }
    }
    /*
    * @notice Settle as much bad debt as possible (if this contract has any)
    * @param coinName The name of the coin to settle debt for
    */
    function settleDebt(bytes32 coinName) public {
        uint256 coinBalanceSelf = safeEngine.coinBalance(coinName, address(this));
        uint256 debtBalanceSelf = safeEngine.debtBalance(coinName, address(this));

        if (debtBalanceSelf > 0) {
          safeEngine.settleDebt(coinName, minimum(coinBalanceSelf, debtBalanceSelf));
        }
    }

    // --- Stability Fee Transfer (Governance) ---
    /**
     * @notice Governance transfers SF to an address
     * @param coinName The name of the coin
     * @param account Address to transfer SF to
     * @param rad Amount of internal system coins to transfer (a number with 45 decimals)
     */
    function giveFunds(bytes32 coinName, address account, uint256 rad) external isAuthorized(coinName) accountNotTreasury(account) {
        require(account != address(0), "MultiSecondaryStabilityFeeTreasury/null-account");

        joinAllCoins(coinName);
        settleDebt(coinName);

        require(safeEngine.debtBalance(coinName, address(this)) == 0, "MultiSecondaryStabilityFeeTreasury/outstanding-bad-debt");
        require(safeEngine.coinBalance(coinName, address(this)) >= rad, "MultiSecondaryStabilityFeeTreasury/not-enough-funds");

        safeEngine.transferInternalCoins(coinName, address(this), account, rad);
        emit GiveFunds(coinName, account, rad);
    }
    /**
     * @notice Governance takes funds from an address
     * @param coinName The name of the coin
     * @param account Address to take system coins from
     * @param rad Amount of internal system coins to take from the account (a number with 45 decimals)
     */
    function takeFunds(bytes32 coinName, address account, uint256 rad) external isAuthorized(coinName) accountNotTreasury(account) {
        safeEngine.transferInternalCoins(coinName, account, address(this), rad);
        emit TakeFunds(coinName, account, rad);
    }
}
