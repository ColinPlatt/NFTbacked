// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "solmate/utils/SafeCastLib.sol";

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

    function burn(address from, uint256 amt) external;
}

contract LendingVault {
    using SafeCastLib for uint256;
    using safeSigned for int256;

    IERC20 public usdc;
    IERC20 public lToken;
    address public nftVault;

    uint128 public accLTokenPerShare;
    uint64 public lastRewardTime;       

    uint256 constant BASE_REWARD_RATE = 5;
    uint256 constant ACC_PRECISION = 1e12;
    //uint256 constant ACTIVE_REWARD_RATE = 2;

    struct LenderInfo {
        uint256 principal;
        uint256 rewardDebt;
        uint256 bidAmount;
    }

    mapping(address => LenderInfo) public lendersInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    constructor(
        address _usdc,
        address _lToken
        //address _nftVault
        ) {
            usdc = IERC20(_usdc);
            lToken = IERC20(_lToken);
            //nftVault = _nftVault;
        }

    modifier onlyNftVault() {
        require(msg.sender == nftVault, "LendingVault: NOT_AUTHORIZED");
        _;
    }

    function userInterest(address _user) public view returns (uint256 pending) {
        LenderInfo storage user = lendersInfo[_user];

        uint256 vaultBalance = usdc.balanceOf(address(this));
        uint128 _accLTokenPerShare;

        if (block.timestamp > lastRewardTime && vaultBalance != 0) {
            uint256 time = block.timestamp - lastRewardTime;
            uint256 lReward = time * BASE_REWARD_RATE;
            _accLTokenPerShare += ((lReward * ACC_PRECISION) / vaultBalance).safeCastTo128();
        }
        pending = int256(user.principal * (_accLTokenPerShare / ACC_PRECISION) - user.rewardDebt).toUInt256();


    }

    function userPrincipal() public view returns (uint256 balance) {
        LenderInfo storage user = lendersInfo[msg.sender];

        return user.principal;
    }

    function userPrincipal(address _user) public view returns (uint256 balance) {
        LenderInfo storage user = lendersInfo[_user];

        return user.principal;
    }

    function deposit(uint256 amt) public {
        // for the first depositor we can start the reward counter
        if(lastRewardTime == 0){
            block.timestamp.safeCastTo64();
        }

        LenderInfo storage user = lendersInfo[msg.sender];

        // implement logic for holdings of accrued interest
        if (user.principal > 0) {

        }
        usdc.transferFrom(
            address(msg.sender),
            address(this),
            amt
        );
        user.principal += amt;
        //user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        emit Deposit(msg.sender, amt);

    }

    function withdraw(uint256 amt) public {
        LenderInfo storage user = lendersInfo[msg.sender];
        require(user.principal >= amt, "LendingVault: WITHDRAW_FAILED");

        user.principal -= amt;
        usdc.transfer(
            address(msg.sender),
            amt
        );
        //user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
        emit Withdraw(msg.sender, amt);

    }

    /*
    function receiveInterest(uint256 amt) public onlyNftVault {
        usdc.transferFrom(nftVault, address(this), amt);
        accruedInterest += amt;
    }
    */

    function reducePrincipal(address _user, uint256 amt) public onlyNftVault {
        LenderInfo storage user = lendersInfo[_user];
        require(user.principal >= amt, "LendingVault: PRINCIPAL_REDUCE_FAILED");

        user.principal -= amt;
    }


}

library safeSigned {
    function toUInt256(int256 a) internal pure returns (uint256) {
        require(a >= 0, "Integer < 0");
        return uint256(a);
    }
}
