// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function burn(uint256 amt) external;
}

interface ILendingVault {
    function withdrawLendAmount(address user, uint256 amt) external;

    function returnLendAmount(uint256 amt) external;

    function reducePrincipal(address _user, uint256 amt) external;
}

contract NFTVault is ERC721TokenReceiver, Ownable {

    IERC20 public lToken;
    ILendingVault public lendingVault;

    IERC721 public nftCollection;

    uint256 public MAX_LTV;
    uint256 public FLOOR_PRICE;

    uint256 constant INTEREST_RATE = 3_500_000;

    uint256 constant MIN_BID_DURATION = 1 days;

    struct BidInfo {
        address user;
        uint256 bidPrice;
        uint256 bidAccepted;
    }

    mapping(uint256 => BidInfo) public highestBids;

    struct NFTInfo {
        address depositor;
        uint256 borrowAmt;
        uint256 lastPaid;
    }

    mapping(uint256 => NFTInfo) public nftInfo;

    struct DefaultInfo {
        uint256 excessUSDCDue;
        uint256 outstandingLTokens;
    }

    mapping(address => DefaultInfo) public defaultInfo;

    constructor(
        address _lToken,
        address _nftCollection
        ){
            lToken = IERC20(_lToken);
            nftCollection = IERC721(_nftCollection);
        }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        NFTInfo storage idInfo = nftInfo[_id];
        idInfo.depositor = _from;

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function setLendingVault(address _lendingVault) public onlyOwner {
        lendingVault = ILendingVault(_lendingVault);
    }

    // Move to voting by LendingVault
    function setBorrowParameters(uint256 _newLtv, uint256 _floor) public onlyOwner {
        if( _newLtv != 0) {
            require(_newLtv > 0 && _newLtv < 50, "NFTVault: INVALID_LTV");
            MAX_LTV = _newLtv;
        }
        if( _floor != 0) {
            FLOOR_PRICE = _floor;
        }
    }

    function viewBorrowCapacity(uint256 id) public view returns (uint256) {
        NFTInfo storage idInfo = nftInfo[id];

        uint256 maxBorrow = FLOOR_PRICE * MAX_LTV / 100;

        require(idInfo.borrowAmt <= maxBorrow, "NFTVault: No borrow capacity");

        return maxBorrow - idInfo.borrowAmt;
    }

    function interestDue(uint256 id) public view returns (uint256) {
        NFTInfo storage idInfo = nftInfo[id];
        if(idInfo.borrowAmt != 0 && block.timestamp > idInfo.lastPaid) {
            uint256 time = block.timestamp - idInfo.lastPaid;
            uint256 lDue = time * INTEREST_RATE * idInfo.borrowAmt;
            return lDue;
        }
        return 0;
    }

    function payLTokenDebt(uint256 id) internal {
        NFTInfo storage idInfo = nftInfo[id];

        uint256 _lTokenOwed = interestDue(id);
        lToken.transferFrom(address(msg.sender), address(this), _lTokenOwed);
        lToken.burn(_lTokenOwed);
        
        idInfo.lastPaid = block.timestamp;
    }


    // borrowing requires that the debtor repays outstanding lToken debt
    function borrow(uint256 id, uint256 amt) public {
        require(address(lendingVault) != address(0), "NFTVault: lending vault unset");
        require(viewBorrowCapacity(id) >= amt, "NFTVault: insufficient borrow capacity");
        NFTInfo storage idInfo = nftInfo[id];
        require(idInfo.depositor == msg.sender, "NFTVault: not NFT owner");

        payLTokenDebt(id);
        
        idInfo.borrowAmt += amt;
        lendingVault.withdrawLendAmount(idInfo.depositor, amt);

    }

    function repayPrincipal(uint256 id, bool withdrawNFT) public {
        require(address(lendingVault) != address(0), "NFTVault: lending vault unset");
        NFTInfo storage idInfo = nftInfo[id];
        require(idInfo.depositor == msg.sender, "NFTVault: not NFT owner");

        payLTokenDebt(id);

        //no idea if this part works
        lendingVault.returnLendAmount(idInfo.borrowAmt);

        if(withdrawNFT) {
            nftCollection.safeTransferFrom(address(this), idInfo.depositor, id);
            // might be able to leave this to reduce gas if a new depositor takes the NFT, but this is probably safer
            idInfo.depositor = address(0);
        }
        
        idInfo.borrowAmt = 0;
    }


    // we define solvency as a loan where the lToken owed + principal does not exceed 50% of the FLOOR_PRICE.
    // For simplicity 1 lToken = 1 USDC
    function isSolvent(uint256 id) public view returns (bool) {
        NFTInfo storage idInfo = nftInfo[id];

        uint256 _lTokenOwed = interestDue(id);

        uint256 totalDebt = idInfo.borrowAmt + (_lTokenOwed / 10^12); // need to adjust lToken to calculate with 6 decimals

        return totalDebt > FLOOR_PRICE/2 ? true : false;
    }

    function declareDefault(uint256 id) public {
        require(!isSolvent(id), "NFTVault: Borrower is Solvent");

        // find highest bid
        BidInfo storage bestBid = highestBids[id];

        // reduce bidder's USDC principal
        lendingVault.reducePrincipal(bestBid.user, bestBid.bidPrice);

        // transfer NFT to highest bidder
        nftCollection.safeTransferFrom(address(this), bestBid.user, id);

        // log default against the borrower (handle if they have other outstanding)
        NFTInfo storage loanInfo = nftInfo[id];
        DefaultInfo storage debtorInfo = defaultInfo[loanInfo.depositor];

        // once a default happens we book a default event against the borrower, if there are already outstanding unpaid lToken debts, we add this to it 
        if(bestBid.bidPrice >= loanInfo.borrowAmt) {
            debtorInfo.excessUSDCDue += bestBid.bidPrice - loanInfo.borrowAmt;
            debtorInfo.outstandingLTokens += interestDue(id);
        } else {
            debtorInfo.outstandingLTokens += interestDue(id);
        }

        // reset the bid to zero
        nftInfo[id] = NFTInfo({
            depositor: address(0),
            borrowAmt: 0,
            lastPaid: 0
        });

    }


    // @TODO: Need to include the logic to look at the LendingVault for the size of bid a user can place

    // If a new bid is the highest bid then we replace the existing highest bid with this bid
    function enterNewBid(uint256 id, uint256 _bidPrice) public {
        BidInfo storage idBid = highestBids[id];
        require(_bidPrice > idBid.bidPrice, "NFTVault: Not highest bid");

        highestBids[id] = BidInfo({
            user: msg.sender,
            bidPrice: _bidPrice,
            bidAccepted: block.timestamp
        });

    }

    // If the bid has passed a minum time then we allow for the bidder to modify
    function modifyBid(uint256 id, uint256 newBidPrice) public {
        BidInfo storage idBid = highestBids[id];
        require(idBid.user == msg.sender, "NFTVault: Unauthorised bid modifier");
        require(block.timestamp > idBid.bidAccepted + MIN_BID_DURATION, "NFTVault: Cannot modify bid yet");

        highestBids[id] = BidInfo({
            user: msg.sender,
            bidPrice: newBidPrice,
            bidAccepted: block.timestamp
        });
    }

}