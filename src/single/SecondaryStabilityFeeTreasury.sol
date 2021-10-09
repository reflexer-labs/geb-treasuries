/// SecondaryStabilityFeeTreasury.sol

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
    function approveSAFEModification(address) virtual external;
    function denySAFEModification(address) virtual external;
    function transferInternalCoins(address,address,uint256) virtual external;
    function settleDebt(uint256) virtual external;
    function coinBalance(address) virtual public view returns (uint256);
    function debtBalance(address) virtual public view returns (uint256);
}
abstract contract SystemCoinLike {
    function balanceOf(address) virtual public view returns (uint256);
    function approve(address, uint256) virtual public returns (uint256);
    function transfer(address,uint256) virtual public returns (bool);
    function transferFrom(address,address,uint256) virtual public returns (bool);
}
abstract contract CoinJoinLike {
    function systemCoin() virtual public view returns (address);
    function join(address, uint256) virtual external;
}

contract SecondaryStabilityFeeTreasury {
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
        require(authorizedAccounts[msg.sender] == 1, "SecondaryStabilityFeeTreasury/account-not-authorized");
        _;
    }

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event GiveFunds(address indexed account, uint256 rad);
    event TakeFunds(address indexed account, uint256 rad);

    SAFEEngineLike  public safeEngine;
    SystemCoinLike  public systemCoin;
    CoinJoinLike    public coinJoin;

    modifier accountNotTreasury(address account) {
        require(account != address(this), "SecondaryStabilityFeeTreasury/account-cannot-be-treasury");
        _;
    }

    constructor(
        address safeEngine_,
        address coinJoin_
    ) public {
        require(address(CoinJoinLike(coinJoin_).systemCoin()) != address(0), "SecondaryStabilityFeeTreasury/null-system-coin");
        authorizedAccounts[msg.sender] = 1;
        safeEngine                     = SAFEEngineLike(safeEngine_);
        coinJoin                       = CoinJoinLike(coinJoin_);
        systemCoin                     = SystemCoinLike(coinJoin.systemCoin());
        systemCoin.approve(address(coinJoin), uint256(-1));
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function minimum(uint256 x, uint256 y) internal view returns (uint256 z) {
        z = (x <= y) ? x : y;
    }

    // --- Helpers ---
    /**
     * @notice Join all ERC20 system coins that the treasury has inside SAFEEngine
     */
    function joinAllCoins() internal {
        if (systemCoin.balanceOf(address(this)) > 0) {
          coinJoin.join(address(this), systemCoin.balanceOf(address(this)));
        }
    }
    function settleDebt() public {
        uint256 coinBalanceSelf = safeEngine.coinBalance(address(this));
        uint256 debtBalanceSelf = safeEngine.debtBalance(address(this));

        if (debtBalanceSelf > 0) {
          safeEngine.settleDebt(minimum(coinBalanceSelf, debtBalanceSelf));
        }
    }

    // --- Stability Fee Transfer (Governance) ---
    /**
     * @notice Governance transfers SF to an address
     * @param account Address to transfer SF to
     * @param rad Amount of internal system coins to transfer (a number with 45 decimals)
     */
    function giveFunds(address account, uint256 rad) external isAuthorized accountNotTreasury(account) {
        require(account != address(0), "SecondaryStabilityFeeTreasury/null-account");

        joinAllCoins();
        settleDebt();

        require(safeEngine.debtBalance(address(this)) == 0, "SecondaryStabilityFeeTreasury/outstanding-bad-debt");
        require(safeEngine.coinBalance(address(this)) >= rad, "SecondaryStabilityFeeTreasury/not-enough-funds");

        safeEngine.transferInternalCoins(address(this), account, rad);
        emit GiveFunds(account, rad);
    }
    /**
     * @notice Governance takes funds from an address
     * @param account Address to take system coins from
     * @param rad Amount of internal system coins to take from the account (a number with 45 decimals)
     */
    function takeFunds(address account, uint256 rad) external isAuthorized accountNotTreasury(account) {
        safeEngine.transferInternalCoins(account, address(this), rad);
        emit TakeFunds(account, rad);
    }
}
