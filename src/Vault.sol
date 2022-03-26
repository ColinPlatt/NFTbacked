// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/utils/SafeCastLib.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function mint(uint256 amt) external;

    function mint(address to, uint256 amt) external;

    function burn(uint256 amt) external;
}

/*
  PLEASE FOR THE LOVE OF GOD DON'T PUT ANY REAL MONEY IN THIS. IT'S HIGHLY INSECURE.
*/

contract Vault is ERC721TokenReceiver, Ownable {
    using SafeCastLib for uint256;
    using safeSigned for int256;

    IERC20 public usdc;
    IERC20 public lToken;
    IERC721 public nftCollection;

    uint256 public MAX_LTV;
    uint256 public FLOOR_PRICE;

    uint256 constant BASE_REWARD_RATE = 25;
    uint256 constant INTEREST_RATE = 30;
    uint256 constant PRECISION = 10**8;

    uint256 constant MIN_BID_DURATION = 1 days;

    struct LenderInfo {
        uint256 principal;
        uint256 rewardDebt;
        uint256 bidAmount;
        uint64 lastRewardTime;
    }

    mapping(address => LenderInfo) public lendersInfo;


    // TODO: Merge this into the NFTInfo struct, probably more gas efficient
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

    uint256 public totalUSDCinLoans;

    struct DefaultInfo {
        uint256 excessUSDCDue;
        uint256 outstandingLTokens;
    }

    mapping(address => DefaultInfo) public defaultInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 idCollateral, uint256 borrowedAmount);
    event Repayed(address indexed user, uint256 idCollateral, uint256 borrowedAmount);
    event Defaulted(address indexed user, uint256 idCollateral, uint256 borrowedAmount, uint256 shortFall);
    event Auctioned(address indexed buyer, uint256 id, uint256 amount);

    // TODO: temp for testing, remove
    event log(string output);
    event log_uint(uint output);
    event log_address(address output);
    event log_bytes(bytes output);

    constructor(
        address _usdc,
        address _lToken,
        address _nftCollection
        ) {
            usdc = IERC20(_usdc);
            lToken = IERC20(_lToken);
            nftCollection = IERC721(_nftCollection);
        }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        require(_operator == _from, "Vault: operator is not from");
        emit log_bytes(_data); // maybe add a safe check that requires user to input something in data
        NFTInfo storage idInfo = nftInfo[_id];
        idInfo.depositor = _from;
        

        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function lenderLastUpdate() public view returns (uint256 lastUpdate) {
        return lendersInfo[msg.sender].lastRewardTime;
    }

    function lenderLastUpdate(address _user) public view returns (uint256 lastUpdate) {
        return lendersInfo[_user].lastRewardTime;
    }

    function lenderInterest(address _user) public view returns (uint256 pending) {
        LenderInfo storage user = lendersInfo[_user];

        uint256 lReward;
        if (block.timestamp > user.lastRewardTime && usdc.balanceOf(address(this)) != 0) {
            uint256 time = block.timestamp - user.lastRewardTime;
            lReward = time * BASE_REWARD_RATE;
        }
        pending = int256(((user.principal * lReward) / PRECISION) - user.rewardDebt).toUInt256();
    }

    function lenderPrincipal() public view returns (uint256 balance) {
        LenderInfo storage user = lendersInfo[msg.sender];

        return user.principal;
    }

    function lenderPrincipal(address _user) public view returns (uint256 balance) {
        LenderInfo storage user = lendersInfo[_user];

        return user.principal;
    }

    function lenderDeposit(uint256 amt) public {

        LenderInfo storage user = lendersInfo[msg.sender];

        if (user.principal > 0 || user.lastRewardTime == 0) {
            uint256 pendingLToken =  lenderInterest(msg.sender);
            user.lastRewardTime = block.timestamp.safeCastTo64();
            if(pendingLToken > 0) {
                user.rewardDebt += pendingLToken;
                //emit log_uint(pendingLToken);
                lToken.mint(msg.sender, pendingLToken);
            }
        }
        usdc.transferFrom(
            address(msg.sender),
            address(this),
            amt
        );
        user.principal += amt;
        emit Deposit(msg.sender, amt);

    }

    function lenderWithdraw(uint256 amt) public {
        LenderInfo storage user = lendersInfo[msg.sender];
        require((user.principal - user.bidAmount) >= amt, "LendingVault: WITHDRAW_FAILED");

        uint256 pendingLToken =  lenderInterest(msg.sender);
        user.lastRewardTime = block.timestamp.safeCastTo64();
        if(pendingLToken > 0) {
            user.rewardDebt += pendingLToken;
            lToken.mint(msg.sender, pendingLToken);
        }

        user.principal -= amt;
        usdc.transfer(
            address(msg.sender),
            amt
        );
        emit Withdraw(msg.sender, amt);

    }

    function nftInventory(uint256 id) public view returns (address depositor, uint256 borrowed, uint256 lastPayment) {
       
        depositor = nftInfo[id].depositor;
        borrowed = nftInfo[id].borrowAmt;
        lastPayment = nftInfo[id].lastPaid;

    }

    function borrowerWithdrawLoan(address borrower, uint256 amt) internal  {
        usdc.transfer(borrower, amt);
    }

    function borrowerReturnLoan(uint256 amt) public {
        usdc.transferFrom(msg.sender, address(this), amt);
    }

    function lenderReducePrincipal(address _user, uint256 amt) internal {
        LenderInfo storage user = lendersInfo[_user];
        require(user.principal >= amt, "LendingVault: PRINCIPAL_REDUCE_FAILED");

        user.principal -= amt;
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
            uint256 lDue = ((time * INTEREST_RATE) * idInfo.borrowAmt) / (PRECISION*100);
            return lDue;
        }
        return 0;
    }

    function payLTokenDebt(uint256 id) public {
        NFTInfo storage idInfo = nftInfo[id];

        uint256 _lTokenOwed = interestDue(id);
        lToken.transferFrom(address(msg.sender), address(this), _lTokenOwed);
        lToken.burn(_lTokenOwed);
        
        idInfo.lastPaid = block.timestamp;
    }


    // borrowing requires that the debtor repays outstanding lToken debt
    function borrowerStartBorrowing(uint256 id, uint256 amt) public {
        require(viewBorrowCapacity(id) >= amt, "NFTVault: insufficient borrow capacity");
        NFTInfo storage idInfo = nftInfo[id];
        require(idInfo.depositor == msg.sender, "NFTVault: not NFT owner");

        payLTokenDebt(id);
        
        idInfo.borrowAmt += amt;
        borrowerWithdrawLoan(idInfo.depositor, amt);

    }

    function repayPrincipal(uint256 id, bool withdrawNFT) public {
        NFTInfo storage idInfo = nftInfo[id];
        require(idInfo.depositor == msg.sender, "NFTVault: not NFT owner");

        payLTokenDebt(id);

        //no idea if this part works
        borrowerReturnLoan(idInfo.borrowAmt);

        if(withdrawNFT) {
            nftCollection.safeTransferFrom(address(this), idInfo.depositor, id);
            // might be able to leave this to reduce gas if a new lenderDepositor takes the NFT, but this is probably safer
            idInfo.depositor = address(0);
        }
        
        idInfo.borrowAmt = 0;
    }


    // we define solvency as a loan where the lToken owed + principal does not exceed 33% of the FLOOR_PRICE.
    // For simplicity 1 lToken = 1 USDC
    function isSolvent(uint256 id) public view returns (bool) {
        NFTInfo storage idInfo = nftInfo[id];

        uint256 _lTokenOwed = interestDue(id);

        uint256 totalDebt = idInfo.borrowAmt + _lTokenOwed; // need to adjust lToken to calculate with 6 decimals

        return totalDebt > FLOOR_PRICE/3 ? false : true;
    }

    function declareDefault(uint256 id) public {
        require(!isSolvent(id), "NFTVault: Borrower is Solvent");

        // find highest bid
        BidInfo storage bestBid = highestBids[id];
        NFTInfo storage loanInfo = nftInfo[id];

        // log default against the borrower (handle if they have other outstanding)
        DefaultInfo storage debtorInfo = defaultInfo[loanInfo.depositor];

        // once a default happens we book a default event against the borrower, if there are already outstanding unpaid lToken debts, we add this to it 
        if(bestBid.bidPrice >= loanInfo.borrowAmt) {
            debtorInfo.excessUSDCDue += bestBid.bidPrice - loanInfo.borrowAmt;
            debtorInfo.outstandingLTokens += interestDue(id);
        } else {
            debtorInfo.outstandingLTokens += interestDue(id);
        }

        // check if there is a bidder, and if not retain NFT
        if (bestBid.bidPrice != 0) {
            // reduce bidder's USDC principal
            lenderReducePrincipal(bestBid.user, bestBid.bidPrice);

            // transfer NFT to highest bidder
            nftCollection.safeTransferFrom(address(this), bestBid.user, id);

            // reset the loan to zero
            nftInfo[id] = NFTInfo({
                depositor: address(0),
                borrowAmt: 0,
                lastPaid: 0
            });

            // reset the bid to zero
            highestBids[id] = BidInfo({
                user : address(0),
                bidPrice : 0,
                bidAccepted : 0
            });


        } else {
            // set the bid to the loan amount and make depositor this contract
            highestBids[id] = BidInfo({
                user : address(this),
                bidPrice : nftInfo[id].borrowAmt,
                bidAccepted : 0
            });
            
            // if no bidder active, swap the details to this contract
            nftInfo[id] = NFTInfo({
                depositor: address(this),
                borrowAmt: 0,
                lastPaid: 0
            });

        }

    }

    // TODO: Implement logic to enforce bidding should be above outstanding loan size

    // If a new bid is the highest bid then we replace the existing highest bid with this bid
    function enterNewBid(uint256 id, uint256 _bidPrice) public {
        BidInfo storage idBid = highestBids[id];
        require(_bidPrice > idBid.bidPrice, "NFTVault: Not highest bid");

        // need to check the user's free USDC balance
        LenderInfo storage bidder = lendersInfo[msg.sender];
        require((bidder.principal - bidder.bidAmount) >= _bidPrice, "insufficient free bid capacity");
        
        // add this bid to their bid amount
        bidder.bidAmount += _bidPrice;

        // check if this is a defaulted NFT owned by the Vault, if so transfer to the bidder and reduce their principal
        if(idBid.user == address(this)) {
            lenderReducePrincipal(msg.sender, _bidPrice);

            // transfer NFT to bidder
            nftCollection.safeTransferFrom(address(this), msg.sender, id);

            // reset the loan to zero
            nftInfo[id] = NFTInfo({
                depositor: address(0),
                borrowAmt: 0,
                lastPaid: 0
            });

            // reset the bid to zero
            highestBids[id] = BidInfo({
                user : address(0),
                bidPrice : 0,
                bidAccepted : 0
            });

            return;
        }

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

        // need to check the user's free USDC balance
        LenderInfo storage bidder = lendersInfo[msg.sender];

        // check if the new bid is higher or lower than the existing bid and adjust bid tracker in lender profile
        if(newBidPrice > idBid.bidPrice) {
            require((bidder.principal - bidder.bidAmount) >= newBidPrice, "insufficient free bid capacity");
        
            // add this bid to their bid amount
            bidder.bidAmount += newBidPrice;
        } else {
            bidder.bidAmount -= idBid.bidPrice-newBidPrice;
        }

        highestBids[id] = BidInfo({
            user: msg.sender,
            bidPrice: newBidPrice,
            bidAccepted: block.timestamp
        });
    }

}

library safeSigned {
    function toUInt256(int256 a) internal pure returns (uint256) {
        require(a >= 0, "Integer < 0");
        return uint256(a);
    }
}