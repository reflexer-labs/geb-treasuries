pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebTreasuries.sol";

contract GebTreasuriesTest is DSTest {
    GebTreasuries treasuries;

    function setUp() public {
        treasuries = new GebTreasuries();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
