// transfer or get back ownership of CDP
// this contract will be the owner of all the CDPs, upgrading this means all the data need to be migrated
// factor the WETH to PETH conversion rate
// run an event after changing the CDP ownership
// implement repay loan function
// implement allowed functionalities like MoatAsset as CDPs are owned by this contract

pragma solidity 0.4.24;

interface token {
    function transfer(address receiver, uint amount) external returns(bool);
    function balanceOf(address who) external returns(uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint amt) external returns (bool);
}

interface AddressRegistry {
    function getAddr(string name) external returns(address);
    function isApprovedResolver(address user) external returns(bool);
}

interface MakerCDP {
    function open() external returns (bytes32 cup);
    function join(uint wad) external; // Join PETH
    function exit(uint wad) external; // Exit PETH
    function give(bytes32 cup, address guy) external;
    function lock(bytes32 cup, uint wad) external;
    function free(bytes32 cup, uint wad) external;
    function draw(bytes32 cup, uint wad) external;
    function wipe(bytes32 cup, uint wad) external;
    function shut(bytes32 cup) external;
    function bite(bytes32 cup) external;
}

interface WETHFace {
    function deposit() external payable;
    function withdraw(uint wad) external;
}


contract Registry {

    address public registryAddress;
    AddressRegistry aRegistry = AddressRegistry(registryAddress);

    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        addr = aRegistry.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }
 
}


contract GlobalVar is Registry {

    address public weth = 0xd0a1e359811322d97991e03f863a0c30c2cf029c;
    address public peth = 0xf4d791139ce033ad35db2b2201435fad668b1b64;
    address public mkr = 0xaaf64bfcc32d0f15873a02163e7e500671a4ffcd;
    address public dai = 0xc4375b7de8af5a38a93548eb8453a498222c4ff2;

    address public cdpAddr = 0xa71937147b55Deb8a530C7229C442Fd3F31b7db2;
    MakerCDP loanMaster = MakerCDP(cdpAddr);

    mapping (address => bytes32) public borrowerCDPs; // borrower >>> CDP Bytes

}


contract BorrowTasks is GlobalVar {

    function openCDP() internal returns (bytes32) {
        return loanMaster.open();
    }

    function convertToWETH(uint weiAmt) internal {
        WETHFace wethFunction = WETHFace(weth);
        wethFunction.deposit.value(weiAmt)();
    }

    function convertToPETH(uint weiAmt) internal {
        loanMaster.join(weiAmt);
    }

    function lockPETH(address borrower, uint weiAmt) internal {
        loanMaster.lock(borrowerCDPs[borrower], weiAmt);
    }

    function transferCDP(address nextOwner) public {
        require(nextOwner != 0, "Invalid Address.");
        loanMaster.give(borrowerCDPs[msg.sender], nextOwner);
    }

    function approveERC20() public {
        token wethTkn = token(weth);
        wethTkn.approve(cdpAddr, 2**256 - 1);
        token pethTkn = token(peth);
        pethTkn.approve(cdpAddr, 2**256 - 1);
        token mkrTkn = token(mkr);
        mkrTkn.approve(cdpAddr, 2**256 - 1);
        token daiTkn = token(dai);
        daiTkn.approve(cdpAddr, 2**256 - 1);
    }

}


contract Borrow is BorrowTasks {

    modifier securedResolver(address borrower) {
        if (borrower != msg.sender) {
            require(
                msg.sender == getAddress("resolver"),
                "Message Sender is not MoatResolver."
            );
            require(
                aRegistry.isApprovedResolver(borrower),
                "MoatResolver is not approved by CDP user."
            );
        }
        _;
    }

    function borrowLoan(
        address borrower,
        uint lockETH,
        uint loanDAI
    ) public securedResolver(borrower) 
    {
        if (borrowerCDPs[borrower] == 0x0000000000000000000000000000000000000000000000000000000000000000) {
            borrowerCDPs[borrower] = openCDP();
        }

        if (lockETH != 0) {
            convertToWETH(lockETH);
            convertToPETH(lockETH - lockETH/1000);
            lockPETH(borrower, lockETH - lockETH/1000);
            // event for locking ETH
        }

        if (loanDAI != 0) {
            loanMaster.draw(borrowerCDPs[borrower], loanDAI);
            token tokenFunctions = token(dai);
            tokenFunctions.transfer(getAddress("asset"), loanDAI);
            // event for drawing DAI
        }

    }

}


contract MoatMaker is Borrow {

    constructor() public {
        approveERC20();
    }

    function () public payable {}

}