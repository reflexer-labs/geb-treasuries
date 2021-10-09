pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import "../../single/ProtocolTokenSubsidyPool.sol";

contract Guy {
    function doApprove(address token, address usr, uint256 amount) public {
        DSDelegateToken(token).approve(usr, amount);
    }

    function doSetTotalAllowance(address subsidyPool, address account, uint256 amount) public {
        ProtocolTokenSubsidyPool(subsidyPool).setTotalAllowance(account, amount);
    }
    function doSetPerBlockAllowance(address subsidyPool, address account, uint256 amount) public {
        ProtocolTokenSubsidyPool(subsidyPool).setPerBlockAllowance(account, amount);
    }
    function doPullFunds(address subsidyPool, address dst, address token, uint256 amount) public {
        ProtocolTokenSubsidyPool(subsidyPool).pullFunds(dst, token, amount);
    }
    function doGiveFunds(address subsidyPool, address account, uint256 amount) public {
        ProtocolTokenSubsidyPool(subsidyPool).giveFunds(account, amount);
    }
    function doTakeFunds(address subsidyPool, address account, uint256 amount) public {
        ProtocolTokenSubsidyPool(subsidyPool).takeFunds(account, amount);
    }
}

contract ProtocolTokenSubsidyPoolTest is DSTest {
    DSDelegateToken protocolToken;
    ProtocolTokenSubsidyPool pool;

    Guy user;

    uint256 amountToMint = 1e27;

    function setUp() public {
        user = new Guy();
        protocolToken = new DSDelegateToken("PROT", "PROT");
        pool = new ProtocolTokenSubsidyPool(address(protocolToken));

        protocolToken.mint(address(pool), amountToMint);
        protocolToken.mint(address(this), amountToMint);
    }

    function test_setup() public {
        assertTrue(address(pool.protocolToken()) == address(protocolToken));
        assertEq(pool.authorizedAccounts(address(this)), 1);
    }
    function test_set_total_allowance() public {
        pool.setTotalAllowance(address(0x123), 123456789);
        (uint totalAllowance, ) = pool.getAllowance(address(0x123));
        assertEq(totalAllowance, 123456789);

        pool.setTotalAllowance(address(0x123), uint(-1));
        (totalAllowance, ) = pool.getAllowance(address(0x123));
        assertEq(totalAllowance, uint(-1));
    }
    function testFail_set_total_allowance_for_null() public {
        pool.setTotalAllowance(address(0), 123456789);
    }
    function testFail_set_total_allowance_for_pool() public {
        pool.setTotalAllowance(address(pool), 123456789);
    }
    function testFail_set_total_allowance_not_authorized() public {
        user.doSetTotalAllowance(address(pool), address(0x123), 123456789);
    }
    function test_set_per_block_allowance() public {
        pool.setPerBlockAllowance(address(0x123), 123456789);
        (, uint perBlockAllowance) = pool.getAllowance(address(0x123));
        assertEq(perBlockAllowance, 123456789);

        pool.setPerBlockAllowance(address(0x123), uint(-1));
        (, perBlockAllowance) = pool.getAllowance(address(0x123));
        assertEq(perBlockAllowance, uint(-1));
    }
    function testFail_set_per_block_allowance_for_pool() public {
        pool.setPerBlockAllowance(address(pool), 123456789);
    }
    function testFail_set_per_block_allowance_for_null() public {
        pool.setPerBlockAllowance(address(0), 123456789);
    }
    function testFail_set_per_block_allowance_not_authorized() public {
        user.doSetPerBlockAllowance(address(pool), address(0x123), 123456789);
    }
    function test_give_funds() public {
        pool.giveFunds(address(0x1234), 1e19);
        assertEq(protocolToken.balanceOf(address(0x1234)), 1e19);
        assertEq(protocolToken.balanceOf(address(pool)), 999999990000000000000000000);
    }
    function test_receive_tokens_give_funds() public {
        protocolToken.move(address(this), address(pool), 1e18);
        pool.giveFunds(address(0x9999), 1e18);
        assertEq(protocolToken.balanceOf(address(0x9999)), 1e18);
        assertEq(protocolToken.balanceOf(address(pool)), 1e27);
    }
    function testFail_give_funds_more_than_balance() public {
        pool.giveFunds(address(0x1234), 1e29);
    }
    function testFail_give_funds_to_pool() public {
        pool.giveFunds(address(pool), 1e29);
    }
    function testFail_give_funds_to_null() public {
        pool.giveFunds(address(0), 1e29);
    }
    function testFail_give_funds_not_authorized() public {
        user.doGiveFunds(address(pool), address(0x1234), 1234);
    }
    function test_take_funds() public {
        protocolToken.transferFrom(address(this), address(user), 1e19);
        user.doApprove(address(protocolToken), address(pool), uint(-1));
        pool.takeFunds(address(user), 1e19);
        assertEq(protocolToken.balanceOf(address(pool)), 1000000010000000000000000000);
    }
    function testFail_take_funds_from_null() public {
        protocolToken.transferFrom(address(this), address(0), 1e19);
        pool.takeFunds(address(0), 1e19);
    }
    function testFail_take_funds_from_pool() public {
        pool.takeFunds(address(pool), 1);
    }
    function testFail_take_funds_not_authorized() public {
        protocolToken.transferFrom(address(this), address(user), 1e19);
        user.doApprove(address(protocolToken), address(pool), uint(-1));
        user.doTakeFunds(address(pool), address(user), 1e19);
    }
    function test_pull_funds() public {
        (uint totalAllowance, uint perBlockAllowance) = pool.getAllowance(address(this));
        assertEq(totalAllowance, perBlockAllowance);
        assertEq(totalAllowance, 0);

        pool.setTotalAllowance(address(this), 123456789);
        pool.setPerBlockAllowance(address(this), 123456789);

        (totalAllowance, perBlockAllowance) = pool.getAllowance(address(this));
        assertEq(totalAllowance, perBlockAllowance);
        assertEq(totalAllowance, 123456789);

        assertEq(protocolToken.balanceOf(address(this)), 1e27);
        assertEq(protocolToken.balanceOf(address(0x123)), 0);

        pool.pullFunds(address(0x123), address(protocolToken), 1);
        pool.pullFunds(address(this), address(protocolToken), 1);

        assertEq(protocolToken.balanceOf(address(this)), 1e27 + 1);
        assertEq(protocolToken.balanceOf(address(0x123)), 1);
    }
    function test_pull_funds_per_block_allowance_higher_than_total() public {
        pool.setTotalAllowance(address(this), 1e9);
        pool.setPerBlockAllowance(address(this), 1e10);

        pool.pullFunds(address(0x123), address(protocolToken), 1);
        pool.pullFunds(address(this), address(protocolToken), 1);

        assertEq(protocolToken.balanceOf(address(this)), 1e27 + 1);
        assertEq(protocolToken.balanceOf(address(0x123)), 1);
    }
    function testFail_pull_funds_per_block_allowance_exceeded() public {
        pool.setTotalAllowance(address(this), 1e9);
        pool.setPerBlockAllowance(address(this), 1e8);

        pool.pullFunds(address(0x123), address(protocolToken), 1e9);
    }
    function testFail_pull_funds_total_allowance_exceeded() public {
        pool.setTotalAllowance(address(this), 1e9);
        pool.setPerBlockAllowance(address(this), 1e18);

        pool.pullFunds(address(0x123), address(protocolToken), 1e10);
    }
    function testFail_take_funds_give_to_pool() public {
        pool.setTotalAllowance(address(this), 1e9);
        pool.setPerBlockAllowance(address(this), 1e8);

        pool.pullFunds(address(pool), address(protocolToken), 1);
    }
    function testFail_take_funds_give_to_null() public {
        pool.setTotalAllowance(address(this), 1e9);
        pool.setPerBlockAllowance(address(this), 1e8);

        pool.pullFunds(address(0), address(protocolToken), 1);
    }
    function testFail_take_funds_zero() public {
        pool.setTotalAllowance(address(this), 1e9);
        pool.setPerBlockAllowance(address(this), 1e8);

        pool.pullFunds(address(0x123), address(protocolToken), 0);
    }
    function testFail_take_funds_invalid_token() public {
        pool.setTotalAllowance(address(this), 1e9);
        pool.setPerBlockAllowance(address(this), 1e8);

        pool.pullFunds(address(0x123), address(0x1), 1);
    }
    function testFail_take_funds_more_than_pool_balance() public {
        pool.setTotalAllowance(address(this), uint(-1));
        pool.setPerBlockAllowance(address(this), uint(-1));

        pool.pullFunds(address(0x123), address(protocolToken), protocolToken.balanceOf(address(pool)) + 1);
    }
}
