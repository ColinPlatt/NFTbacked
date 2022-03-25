// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "./CheatCodes.sol";

import {mockUSDC} from "../mockUSDC.sol";
import {lendToken} from "../lendToken.sol";
import {LendingVault} from "../LendingVault.sol";

contract LendingVaultTest is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

    mockUSDC usdc;
    lendToken lToken;
    LendingVault vault;

    function setUp() public {
        usdc = new mockUSDC();
        usdc.mint(1000**6);

        lToken = new lendToken();

        vault = new LendingVault(address(usdc), address(lToken));
        lToken.transferOwnership(address(vault));
    }

    function _testInvariantMetaData() public {
        assertEq(usdc.name(), "mockUSDC");
        assertEq(usdc.symbol(), "mUSDC");
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.balanceOf(address(this)), 1000**6);

        assertEq(lToken.name(), "lendToken");
        assertEq(lToken.symbol(), "lToken");
        assertEq(lToken.decimals(), 18);
    }

    function _testVaultDeposit() public {
        usdc.approve(address(vault), 1000**18);

        vault.deposit(10**6);

        assertEq(vault.userPrincipal(), 10**6);

        vault.withdraw(10**6);

        assertEq(vault.userPrincipal(), 0);
        assertEq(usdc.balanceOf(address(this)), 1000**6);

    }

    function _testMint() public {
        vault.testMinting();
        assertEq(lToken.totalSupply(),10);
    }

    function testPendingDeposit() public {
        usdc.approve(address(vault), 1000**18);

        cheats.warp(block.timestamp + 1);
        vault.deposit(10**6);

        cheats.warp(block.timestamp + 86400 * 365);

        assertEq(vault.userLastUpdate(address(this)),1);
        assertEq(vault.userInterest(address(this)),78_840_000_000_000_000_000);

        vault.deposit(0);

        assertEq(lToken.totalSupply(),78_840_000_000_000_000_000);

    }



}