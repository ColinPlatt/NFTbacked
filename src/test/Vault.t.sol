// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "./CheatCodes.sol";

import {mockUSDC} from "../mockUSDC.sol";
import {mockERC721} from "../mockERC721.sol";
import {lendToken} from "../lendToken.sol";

import {Vault} from "../Vault.sol";

contract VaultTest is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

    mockUSDC usdc;
    lendToken lToken;
    Vault vault;
    mockERC721 nftCollection;

    function setUp() public {
        usdc = new mockUSDC();
        usdc.mint(1000**6);

        nftCollection = new mockERC721("expensive JPEGs", "JPEG");

        lToken = new lendToken();

        vault = new Vault(address(usdc), address(lToken), address(nftCollection));
        lToken.transferOwnership(address(vault));
    }

    function testInvariantMetaData() public {
        assertEq(usdc.name(), "mockUSDC");
        assertEq(usdc.symbol(), "mUSDC");
        assertEq(usdc.decimals(), 6);
        assertEq(usdc.balanceOf(address(this)), 1000**6);

        assertEq(lToken.name(), "lendToken");
        assertEq(lToken.symbol(), "lToken");
        assertEq(lToken.decimals(), 18);

        assertEq(nftCollection.name(), "expensive JPEGs");
        assertEq(nftCollection.symbol(), "JPEG");
    }

    function testVaultDeposit() public {
        usdc.approve(address(vault), 1000**18);

        vault.lenderDeposit(10**6);

        assertEq(vault.lenderPrincipal(), 10**6);

        vault.lenderWithdraw(10**6);

        assertEq(vault.lenderPrincipal(), 0);
        assertEq(usdc.balanceOf(address(this)), 1000**6);

    }

    function testPendingDeposit() public {
        usdc.approve(address(vault), 1000**18);

        cheats.warp(block.timestamp + 1);
        vault.lenderDeposit(10**6);

        cheats.warp(block.timestamp + 86400 * 365);

        assertEq(vault.lenderLastUpdate(address(this)),1);
        assertEq(vault.lenderInterest(address(this)),78_840_000_000_000_000_000);

        vault.lenderDeposit(0);

        assertEq(lToken.totalSupply(),78_840_000_000_000_000_000);

    }

    function testDepositNFT() public {
        usdc.approve(address(vault), 1000**18);
        vault.lenderDeposit(1000**6);

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(0);
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(this), address(vault), 0);

        assertEq(nftCollection.ownerOf(0), address(vault));


        (address _depositor, uint256 _borrowed, uint256 _lastPayment) = vault.nftInventory(0);
        assertEq(_depositor, address(this));
        assertEq(_borrowed, 0);
        assertEq(_lastPayment, 0);

    }

    function testBorrowAgainstNFT() public {
        usdc.approve(address(vault), 1000**18);
        vault.lenderDeposit(1000**6);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 1000**6);


        

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20**6);

        assertEq(usdc.balanceOf(address(0xBEEF)), 20**6);

    }



}