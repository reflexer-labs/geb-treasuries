/// NoRebalanceStabilityFeeTreasury.t.sol

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
import "geb/single/SAFEEngine.sol";
import {CoinJoin} from 'geb/shared/BasicTokenAdapters.sol';

import "../../single/NoRebalanceStabilityFeeTreasury.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Usr {
    function approveSAFEModification(address safeEngine, address lad) external {
        SAFEEngine(safeEngine).approveSAFEModification(lad);
    }
    function giveFunds(address stabilityFeeTreasury, address lad, uint rad) external {
        NoRebalanceStabilityFeeTreasury(stabilityFeeTreasury).giveFunds(lad, rad);
    }
    function takeFunds(address stabilityFeeTreasury, address lad, uint rad) external {
        NoRebalanceStabilityFeeTreasury(stabilityFeeTreasury).takeFunds(lad, rad);
    }
    function pullFunds(address stabilityFeeTreasury, address gal, address tkn, uint wad) external {
        return NoRebalanceStabilityFeeTreasury(stabilityFeeTreasury).pullFunds(gal, tkn, wad);
    }
    function approve(address systemCoin, address gal) external {
        Coin(systemCoin).approve(gal, uint(-1));
    }
}

contract NoRebalanceStabilityFeeTreasuryTest is DSTest {
    Hevm hevm;

    SAFEEngine safeEngine;
    NoRebalanceStabilityFeeTreasury stabilityFeeTreasury;

    Coin systemCoin;
    CoinJoin systemCoinA;

    Usr usr;

    address alice = address(0x1);
    address bob = address(0x2);

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

        safeEngine  = new SAFEEngine();
        systemCoin = new Coin("Coin", "COIN", 99);
        systemCoinA = new CoinJoin(address(safeEngine), address(systemCoin));
        stabilityFeeTreasury = new NoRebalanceStabilityFeeTreasury(address(safeEngine), address(systemCoinA));

        systemCoin.addAuthorization(address(systemCoinA));
        stabilityFeeTreasury.addAuthorization(address(systemCoinA));

        safeEngine.createUnbackedDebt(bob, address(stabilityFeeTreasury), rad(200 ether));
        safeEngine.createUnbackedDebt(bob, address(this), rad(100 ether));

        safeEngine.approveSAFEModification(address(systemCoinA));
        systemCoinA.exit(address(this), 100 ether);

        usr.approveSAFEModification(address(safeEngine), address(stabilityFeeTreasury));
    }

    function test_setup() public {
        assertEq(address(stabilityFeeTreasury.safeEngine()), address(safeEngine));
        assertEq(systemCoin.balanceOf(address(this)), 100 ether);
        assertEq(safeEngine.coinBalance(address(alice)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
    }
    function test_setTotalAllowance() public {
        stabilityFeeTreasury.setTotalAllowance(alice, 10 ether);
        (uint total, uint perBlock) = stabilityFeeTreasury.getAllowance(alice);
        assertEq(total, 10 ether);
        assertEq(perBlock, 0);
    }
    function test_setPerBlockAllowance() public {
        stabilityFeeTreasury.setPerBlockAllowance(alice, 1 ether);
        (uint total, uint perBlock) = stabilityFeeTreasury.getAllowance(alice);
        assertEq(total, 0);
        assertEq(perBlock, 1 ether);
    }
    function testFail_give_non_relied() public {
        usr.giveFunds(address(stabilityFeeTreasury), address(usr), rad(5 ether));
    }
    function testFail_take_non_relied() public {
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
        usr.takeFunds(address(stabilityFeeTreasury), address(usr), rad(2 ether));
    }
    function test_give_take() public {
        assertEq(safeEngine.coinBalance(address(usr)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
        assertEq(safeEngine.coinBalance(address(usr)), rad(5 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(195 ether));
        stabilityFeeTreasury.takeFunds(address(usr), rad(2 ether));
        assertEq(safeEngine.coinBalance(address(usr)), rad(3 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(197 ether));
    }
    function testFail_give_more_debt_than_coin() public {
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + 1);

        assertEq(safeEngine.coinBalance(address(usr)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
    }
    function testFail_give_more_debt_than_coin_after_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + rad(100 ether) + 1);

        assertEq(safeEngine.coinBalance(address(usr)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
    }
    function testFail_pull_above_setTotalAllowance() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), rad(11 ether));
    }
    function testFail_pull_null_tkn_amount() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(
          address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0
        );
    }
    function testFail_pull_null_account() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(
          address(stabilityFeeTreasury), address(0), address(stabilityFeeTreasury.systemCoin()), rad(1 ether)
        );
    }
    function testFail_pull_random_token() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(0x3), rad(1 ether));
    }
    function test_pull_funds_no_block_limit() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 1 ether);
        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(1 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(199 ether));
    }
    function test_pull_funds_to_treasury_no_block_limit() public {
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(stabilityFeeTreasury), address(stabilityFeeTreasury.systemCoin()), 1 ether);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
    }
    function test_pull_funds_under_block_limit() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);
        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9.1 ether));
        assertEq(stabilityFeeTreasury.pulledPerBlock(address(usr), block.number), rad(0.9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(0.9 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(199.1 ether));
    }
    function testFail_pull_funds_more_debt_than_coin() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + 1);
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);
    }
    function testFail_pull_funds_more_debt_than_coin_post_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + rad(100 ether) + 1);
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);
    }
    function test_pull_funds_less_debt_than_coin() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) - rad(1 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);

        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9.1 ether));
        assertEq(stabilityFeeTreasury.pulledPerBlock(address(usr), block.number), rad(0.9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(0.9 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(0.1 ether));
    }
    function test_less_debt_than_coin_post_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) - rad(1 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);

        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9.1 ether));
        assertEq(stabilityFeeTreasury.pulledPerBlock(address(usr), block.number), rad(0.9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(0.9 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(100.1 ether));
    }
    function testFail_pull_funds_above_block_limit() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 10 ether);
    }
}
