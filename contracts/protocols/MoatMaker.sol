// get back the ownership of CDP
// mechanism to transfer an existing CDP (2 txn process)
// factor the WETH to PETH conversion rate - https://chat.makerdao.com/direct/Sean
// implement repay loan function

pragma solidity 0.4.24;

interface token {
    function transfer(address receiver, uint amount) external returns(bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface AddressRegistry {
    function getAddr(string name) external returns(address);
    function isApprovedResolver(address user) external returns(bool);
}

interface Resolver {
    function fees() external returns(uint);
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
    function per() external returns (uint ray);
}

interface WETHFace {
    function deposit() external payable;
    function withdraw(uint wad) external;
}


contract Registry {

    address public registryAddress;

    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }

    modifier onlyUserOrResolver(address user) {
        if (msg.sender != user) {
            require(
                msg.sender == getAddress("resolver"),
                "Permission Denied"
            );
            AddressRegistry aRegistry = AddressRegistry(registryAddress);
            require(
                aRegistry.isApprovedResolver(user),
                "Resolver Not Approved"
            );
        }
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry aRegistry = AddressRegistry(registryAddress);
        addr = aRegistry.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }
 
}


contract GlobalVar is Registry {

    // kovan network
    address public weth = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;
    address public peth = 0xf4d791139cE033Ad35DB2B2201435fAd668B1b64;
    address public mkr = 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD;
    address public dai = 0xC4375B7De8af5a38a93548eb8453a498222C4fF2;

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

    event LockedETH(address borrower, uint lockETH, uint lockPETH);
    event LoanedDAI(address borrower, uint loanDAI, uint fees);

    function getLoan(
        address borrower,
        uint lockETH,
        uint loanDAI
    ) public payable onlyUserOrResolver(borrower) returns (uint daiMinted)
    {
        if (borrowerCDPs[borrower] == 0x0000000000000000000000000000000000000000000000000000000000000000) {
            borrowerCDPs[borrower] = openCDP();
        }

        if (lockETH != 0) {
            convertToWETH(lockETH);
            convertToPETH(lockETH - ratioedETH(lockETH));
            lockPETH(borrower, lockETH - ratioedETH(lockETH));
            emit LockedETH(borrower, lockETH, ratioedETH(lockETH));
        }

        if (loanDAI != 0) {
            loanMaster.draw(borrowerCDPs[borrower], loanDAI);
            uint fees = deductFees(loanDAI);
            token tokenFunctions = token(dai);
            tokenFunctions.transfer(getAddress("resolver"), loanDAI - fees);
            daiMinted = loanDAI;
            emit LoanedDAI(borrower, loanDAI, fees);
        }

    }

    function ratioedETH(uint eth) internal returns (uint rETH) {
        rETH = (eth * loanMaster.per()) / 10 ** 27;
    }

    function deductFees(uint volume) internal returns(uint fees) {
        Resolver moatRes = Resolver(getAddress("resolver"));
        fees = moatRes.fees();
        if (fees > 0) {
            fees = volume / fees;
            token tokenFunctions = token(dai);
            tokenFunctions.transfer(getAddress("admin"), fees);
        }
    }

}


contract MoatMaker is Borrow {

    constructor() public {
        approveERC20();
    }

    function () public payable {}

}