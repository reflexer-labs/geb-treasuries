/// MultiSecondaryStabilityFeeTreasury.t.sol

// Copyright (C) 2015-2020  DappHub, LLC
// Copyright (C) 2020       Reflexer Labs, INC

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

import "ds-test/test.sol";

import {Coin} from 'geb/shared/Coin.sol';
import "geb/multi/MultiSAFEEngine.sol";
import {MultiCoinJoin} from 'geb/shared/BasicTokenAdapters.sol';

import "../../multi/MultiSecondaryStabilityFeeTreasury.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Usr {
    function approveSAFEModification(bytes32 coinName, address safeEngine, address lad) external {
        MultiSAFEEngine(safeEngine).approveSAFEModification(coinName, lad);
    }
    function giveFunds(bytes32 coinName, address stabilityFeeTreasury, address lad, uint rad) external {
        MultiSecondaryStabilityFeeTreasury(stabilityFeeTreasury).giveFunds(coinName, lad, rad);
    }
    function takeFunds(bytes32 coinName, address stabilityFeeTreasury, address lad, uint rad) external {
        MultiSecondaryStabilityFeeTreasury(stabilityFeeTreasury).takeFunds(coinName, lad, rad);
    }
    function approve(address systemCoin, address gal) external {
        Coin(systemCoin).approve(gal, uint(-1));
    }
}

contract MultiSecondaryStabilityFeeTreasuryTest is DSTest {
    Hevm hevm;

    MultiSAFEEngine safeEngine;
    MultiSecondaryStabilityFeeTreasury stabilityFeeTreasury;

    Coin systemCoin;
    MultiCoinJoin systemMultiCoinJoinA;

    Usr usr;

    address bob = address(0x1);

    bytes32 coinName = "MAI";

    uint constant HUNDRED = 10 ** 2;
    uint constant RAY     = 10 ** 27;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        usr = new Usr();

        safeEngine  = new MultiSAFEEngine();
        safeEngine.initializeCoin(coinName, uint(-1));

        systemCoin  = new Coin("Coin", "COIN", 99);

        systemMultiCoinJoinA = new MultiCoinJoin(coinName, address(safeEngine), address(systemCoin));

        stabilityFeeTreasury = new MultiSecondaryStabilityFeeTreasury(address(safeEngine));
        stabilityFeeTreasury.initializeCoin(
          coinName,
          address(systemMultiCoinJoinA)
        );

        systemCoin.addAuthorization(address(systemMultiCoinJoinA));
        stabilityFeeTreasury.addAuthorization(coinName, address(systemMultiCoinJoinA));

        safeEngine.createUnbackedDebt(coinName, bob, address(stabilityFeeTreasury), rad(200 ether));
        safeEngine.createUnbackedDebt(coinName, bob, address(this), rad(100 ether));

        safeEngine.approveSAFEModification(coinName, address(systemMultiCoinJoinA));

        systemMultiCoinJoinA.exit(address(this), 100 ether);

        usr.approveSAFEModification(coinName, address(safeEngine), address(stabilityFeeTreasury));
    }

    function test_setup() public {
        assertEq(address(stabilityFeeTreasury.safeEngine()), address(safeEngine));
        assertEq(systemCoin.balanceOf(address(this)), 100 ether);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
    }




    function testFail_give_non_authed() public {
        usr.giveFunds(coinName, address(stabilityFeeTreasury), address(usr), rad(5 ether));
    }
    function testFail_take_non_authed() public {
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        usr.takeFunds(coinName, address(stabilityFeeTreasury), address(usr), rad(2 ether));
    }
    function testFail_give_to_treasury_itself() public {
        stabilityFeeTreasury.giveFunds(coinName, address(stabilityFeeTreasury), rad(5 ether));
    }
    function testFail_take_from_treasury_itself() public {
        stabilityFeeTreasury.takeFunds(coinName, address(stabilityFeeTreasury), rad(5 ether));
    }
    function test_give_take() public {
        assertEq(safeEngine.coinBalance(coinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(195 ether));
        stabilityFeeTreasury.takeFunds(coinName, address(usr), rad(2 ether));
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(3 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(197 ether));
    }
    function test_join_big_from_erc20_give() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 1 ether);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 1 ether);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(196 ether));
    }
    function test_join_little_from_erc20_give() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 1);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 1);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(195 ether) + RAY);
    }
    function testFail_more_debt_than_coin_post_settle_give() public {
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), rad(1000 ether));
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), rad(1000 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
    }
    function test_no_debt_post_settle_give() public {
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), rad(100 ether));
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), rad(100 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(95 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(5 ether));
    }
    function test_manually_settle_give() public {
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), rad(100 ether));
        stabilityFeeTreasury.settleDebt(coinName);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(100 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), 0);
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(95 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(5 ether));
    }
    function test_more_debt_than_coin_take() public {
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), rad(1000 ether));
        stabilityFeeTreasury.takeFunds(coinName, address(usr), rad(2 ether));
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(3 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(197 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), rad(1000 ether));
    }
    function test_more_coin_than_debt_post_join_give() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 100 ether);
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), rad(90 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), rad(90 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(205 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(5 ether));
    }
    function testFail_less_coin_than_debt_post_join_give() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 100 ether);
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), rad(101 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(100 ether));
        assertEq(safeEngine.debtBalance(coinName, address(stabilityFeeTreasury)), rad(101 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
    }
}
