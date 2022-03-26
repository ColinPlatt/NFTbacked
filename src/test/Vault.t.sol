// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "./CheatCodes.sol";

import {mockUSDC} from "../mockUSDC.sol";
import {mockHopper} from "../mockHopper.sol";
import {lendToken} from "../lendToken.sol";

import {Vault} from "../Vault.sol";

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

contract VaultTest is DSTest, ERC721TokenReceiver {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

    uint256 constant DECIMALS = 10**18;

    mockUSDC usdc;
    lendToken lToken;
    Vault vault;
    mockHopper nftCollection;

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        abi.encodePacked(_operator, _from, _id, _data);

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function setUp() public {
        usdc = new mockUSDC();
        usdc.mint(1000*DECIMALS);

        nftCollection = new mockHopper();

        lToken = new lendToken();

        // mint enough tokens for the borrowers to repay in the tests
        lToken.mint(address(0xBEEF), 100*DECIMALS);

        vault = new Vault(address(usdc), address(lToken), address(nftCollection));
        lToken.transferOwnership(address(vault));
    }

    function testInvariantMetaData() public {
        assertEq(usdc.name(), "mockUSDC");
        assertEq(usdc.symbol(), "mUSDC");
        assertEq(usdc.decimals(), 18);
        assertEq(usdc.balanceOf(address(this)), 1000*DECIMALS);

        assertEq(lToken.name(), "lendToken");
        assertEq(lToken.symbol(), "lToken");
        assertEq(lToken.decimals(), 18);

        assertEq(nftCollection.name(), "mock Hoppers");
        assertEq(nftCollection.symbol(), "mHOP");
        assertEq(nftCollection.tokenURI(0), "https://hoppersgame.io/api/uri/hopper/0");
    }

    function testVaultDeposit() public {
        usdc.approve(address(vault), 100_000*DECIMALS);

        vault.lenderDeposit(10*DECIMALS);

        assertEq(vault.lenderPrincipal(), 10*DECIMALS);

        vault.lenderWithdraw(10*DECIMALS);

        assertEq(vault.lenderPrincipal(), 0);
        assertEq(usdc.balanceOf(address(this)), 1000*DECIMALS);

    }

    function testPendingDeposit() public {
        usdc.approve(address(vault), 1000*DECIMALS);

        cheats.warp(block.timestamp + 1);
        vault.lenderDeposit(10*DECIMALS);

        cheats.warp(block.timestamp + 365 days);

        assertEq(vault.lenderLastUpdate(address(this)),1);
        assertEq(vault.lenderInterest(address(this)),78_840_000_000_000_000_000);

        vault.lenderDeposit(0);

        assertEq(lToken.totalSupply(),178_840_000_000_000_000_000);

    }

    function testDepositNFT() public {
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

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
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 100*DECIMALS);

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20*DECIMALS);

        assertEq(usdc.balanceOf(address(0xBEEF)), 20*DECIMALS);

        cheats.warp(block.timestamp + 365 days);

        emit log("after one year:");
        emit log_uint(vault.interestDue(0));
        assertTrue(vault.isSolvent(0));

        cheats.warp(block.timestamp + 3285 days);
        
        emit log("after 10 years:");
        emit log_uint(vault.interestDue(0));
        assertTrue(!vault.isSolvent(0));

    }

    function testBorrowAndRepay() public {
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 100*DECIMALS);       

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20*DECIMALS);

        assertEq(usdc.balanceOf(address(0xBEEF)), 20*DECIMALS);

        cheats.warp(block.timestamp + 365 days);

        emit log("after one year:");
        emit log_uint(vault.interestDue(0));
        assertTrue(vault.isSolvent(0));

        lToken.approve(address(vault), 1000*DECIMALS);
        vault.payLTokenDebt(0);
        assertEq(vault.interestDue(0), 0);

        cheats.warp(block.timestamp + 365 days);
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.repayPrincipal(0, true);

    }

    function testBorrowAndDefaultNoBid() public {
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 100*DECIMALS);

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20*DECIMALS);

        assertEq(usdc.balanceOf(address(0xBEEF)), 20*DECIMALS);

        cheats.warp(block.timestamp + 3650 days);
        
        emit log("after 10 years:");
        emit log_uint(vault.interestDue(0));
        assertTrue(!vault.isSolvent(0));

        cheats.stopPrank();

        // come back to the lender
        vault.declareDefault(0);

        vault.enterNewBid(0, 21*DECIMALS);
        assertEq(nftCollection.ownerOf(0), address(this));
    }

    function testBorrowAndDefaultWithBid() public {
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 100*DECIMALS);

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20*DECIMALS);

        assertEq(usdc.balanceOf(address(0xBEEF)), 20*DECIMALS);

        cheats.warp(block.timestamp + 3650 days);
        
        emit log("after 10 years:");
        emit log_uint(vault.interestDue(0));
        assertTrue(!vault.isSolvent(0));

        cheats.stopPrank();

        vault.enterNewBid(0, 21*DECIMALS);

        // come back to the lender
        vault.declareDefault(0);

        assertEq(nftCollection.ownerOf(0), address(this));
    }

    function testNewBid() public {
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 100*DECIMALS);

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20*DECIMALS);

        cheats.stopPrank();

        vault.enterNewBid(0, 21*DECIMALS);

        cheats.warp(block.timestamp + 1 hours);

        vault.enterNewBid(0, 22*DECIMALS);

    }

    function testBidChangeFail() public {
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 100*DECIMALS);

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20*DECIMALS);

        cheats.stopPrank();

        vault.enterNewBid(0, 21*DECIMALS);

        cheats.warp(block.timestamp + 1 hours);

        cheats.expectRevert(bytes("NFTVault: Not highest bid"));
        vault.enterNewBid(0, 20*DECIMALS);

        cheats.expectRevert(bytes("NFTVault: Cannot modify bid yet"));
        vault.modifyBid(0, 20*DECIMALS);

        cheats.warp(block.timestamp + 24 hours);
        vault.modifyBid(0, 20*DECIMALS);

        cheats.warp(block.timestamp + 25 hours);
        vault.modifyBid(0, 27*DECIMALS);

        // this is allowed as we've not implemented the logic to check a minimum bid price
        cheats.warp(block.timestamp + 25 hours);
        vault.modifyBid(0, 19*DECIMALS);

        cheats.warp(block.timestamp + 25 hours);
        cheats.expectRevert(bytes("insufficient free bid capacity"));
        vault.modifyBid(0, 1001*DECIMALS);

    }

    function testBidAndWithdrawRevert() public {
        usdc.approve(address(vault), 1000*DECIMALS);
        vault.lenderDeposit(1000*DECIMALS);

        // value floor NFT at 1000, and allow 20% LTV max 
        vault.setBorrowParameters(20, 100*DECIMALS);

        // mint NFT ID 0, approve and transfer to the vault
        nftCollection.mint(address(0xBEEF),0);

        //change to a new address to deposit NFT and borrow
        cheats.startPrank(address(0xBEEF));
        nftCollection.setApprovalForAll(address(vault), true);
        nftCollection.safeTransferFrom(address(0xBEEF), address(vault), 0);

        vault.borrowerStartBorrowing(0, 20*DECIMALS);

        cheats.stopPrank();

        vault.enterNewBid(0, 21*DECIMALS);

        cheats.warp(block.timestamp + 1 hours);

        // this will pass
        vault.lenderWithdraw(800*DECIMALS);

        // this should revert
        cheats.warp(block.timestamp + 1 hours);
        cheats.expectRevert(bytes("LendingVault: WITHDRAW_FAILED"));
        vault.lenderWithdraw(190*DECIMALS);

    }

}
