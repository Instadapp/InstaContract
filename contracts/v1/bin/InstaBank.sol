pragma solidity 0.5.0;


library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "Assertion Failed");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "Assertion Failed");
        uint256 c = a / b;
        return c;
    }

}

interface IERC20 {
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface AddressRegistry {
    function getAddr(string calldata name) external view returns (address);
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
    function per() external view returns (uint ray);
    function lad(bytes32 cup) external view returns (address);
}

interface Resolver {
    function transferCDPInternal(uint cdpNum, address nextOwner) external;
}

interface PriceInterface {
    function peek() external view returns (bytes32, bool);
}

interface WETHFace {
    function balanceOf(address who) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint wad) external;
}

interface InstaKyber {
    function executeTrade(
        address src,
        address dest,
        uint srcAmt,
        uint minConversionRate,
        uint maxDestAmt
	)
	external
	payable
	returns (uint destAmt);

    function getExpectedPrice(address src, address dest, uint srcAmt) external view returns (uint, uint);
}


contract Registry {
    address public addressRegistry;
    modifier onlyAdmin() {
        require(msg.sender == getAddress("admin"), "Permission Denied");
        _;
    }

    function getAddress(string memory name) internal view returns (address) {
        AddressRegistry addrReg = AddressRegistry(addressRegistry);
        return addrReg.getAddr(name);
    }
}


contract GlobalVar is Registry {
    using SafeMath for uint;
    using SafeMath for uint256;

    address cdpAddr; // SaiTub
    mapping(uint => address) cdps; // CDP Number >>> Borrower
    mapping(address => bool) resolvers;
    bool public freezed;

    modifier isFreezed() {
        require(!freezed, "Operation Denied.");
        _;
    }

    modifier isCupOwner(uint cdpNum) {
        require(cdps[cdpNum] == msg.sender || cdps[cdpNum] == address(0x0) || cdpNum == 0, "Permission Denied");
        _;
    }

    function pethPEReth(uint ethNum) public view returns (uint rPETH) {
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        rPETH = (ethNum.mul(10 ** 27)).div(loanMaster.per());
    }
}


contract BorrowLoan is GlobalVar {
    // uint cdpNum
    event LockedETH(uint cdpNum, address borrower, uint lockETH, uint lockPETH);
    event LoanedDAI(uint cdpNum, address borrower, uint loanDAI, address payTo);
    event NewCDP(uint cdpNum, address borrower);

    function borrow(uint cdpUint, uint daiDraw, address beneficiary) public payable isFreezed isCupOwner(cdpUint) {
        require(!freezed, "Operation Disabled.");
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        bytes32 cup = bytes32(cdpUint);

        // creating new CDP
        if (cdpUint == 0) {
            cup = loanMaster.open();
            cdps[uint(cup)] = msg.sender;
            emit NewCDP(uint(cup), msg.sender);
        }

        // locking ETH
        if (msg.value > 0) {
            WETHFace wethTkn = WETHFace(getAddress("weth"));
            wethTkn.deposit.value(msg.value)(); // ETH to WETH
            uint pethToLock = pethPEReth(msg.value);
            loanMaster.join(pethToLock); // WETH to PETH
            loanMaster.lock(cup, pethToLock); // PETH to CDP
            emit LockedETH(
                uint(cup),
                msg.sender,
                msg.value,
                pethToLock
            );
        }

        // minting DAI
        if (daiDraw > 0) {
            loanMaster.draw(cup, daiDraw);
            IERC20 daiTkn = IERC20(getAddress("dai"));
            address payTo = beneficiary;
            if (beneficiary == address(0)) {
                payTo = msg.sender;
            }
            daiTkn.transfer(payTo, daiDraw);

            emit LoanedDAI(
                uint(cup),
                msg.sender,
                daiDraw,
                payTo
            );
        }
    }
}


contract RepayLoan is BorrowLoan {
    event WipedDAI(uint cdpNum, address borrower, uint daiWipe, uint mkrCharged);
    event FreedETH(uint cdpNum, address borrower, uint ethFree);
    event ShutCDP(uint cdpNum, address borrower, uint daiWipe, uint ethFree);

    function wipeDAI(uint cdpNum, uint daiWipe) public payable {
        address dai = getAddress("dai");
        address mkr = getAddress("mkr");
        IERC20 daiTkn = IERC20(dai);
        IERC20 mkrTkn = IERC20(mkr);
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        bytes32 cup = bytes32(cdpNum);

        uint contractMKR = mkrTkn.balanceOf(address(this)); // contract MKR balance before wiping
        daiTkn.transferFrom(msg.sender, address(this), daiWipe); // get DAI to pay the debt
        loanMaster.wipe(cup, daiWipe); // wipe DAI
        uint mkrCharged = contractMKR - mkrTkn.balanceOf(address(this)); // MKR fee = before wiping bal - after wiping bal

        // Interacting with UniSwap to swap ETH with MKR
        if (msg.value > 0) {
            // [UniSwap] claiming paid MKR back ETH <> DAI
            return;
        } else {
            // take MKR directly from address
            mkrTkn.transferFrom(msg.sender, address(this), mkrCharged); // user paying MKR fees
        }

        emit WipedDAI(
            cdpNum,
            msg.sender,
            daiWipe,
            mkrCharged
        );
    }

    // TODO => send pethFree from frontend instead of ethFree
    function unlockETH(uint cdpNum, uint ethFree) public isFreezed isCupOwner(cdpNum) {
        require(!freezed, "Operation Disabled");
        bytes32 cup = bytes32(cdpNum);
        uint pethToUnlock = pethPEReth(ethFree);
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        loanMaster.free(cup, pethToUnlock); // CDP to PETH
        loanMaster.exit(pethToUnlock); // PETH to WETH
        WETHFace wethTkn = WETHFace(getAddress("weth"));
        wethTkn.withdraw(ethFree); // WETH to ETH
        msg.sender.transfer(ethFree);
        emit FreedETH(cdpNum, msg.sender, ethFree);
    }

    function shut(uint cdpNum, uint daiDebt) public payable isFreezed isCupOwner(cdpNum) {
        if (daiDebt > 0) {
            wipeDAI(cdpNum, daiDebt);
        }
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        loanMaster.shut(bytes32(cdpNum));

        IERC20 pethTkn = IERC20(getAddress("peth"));
        uint pethBal = pethTkn.balanceOf(address(this));
        loanMaster.exit(pethBal); // PETH to WETH

        WETHFace wethTkn = WETHFace(getAddress("weth"));
        uint wethBal = wethTkn.balanceOf(address(this));
        wethTkn.withdraw(wethBal); // WETH to ETH
        msg.sender.transfer(wethBal); // ETH to borrower

        cdps[cdpNum] = address(0x0);

        emit ShutCDP(
            cdpNum,
            msg.sender,
            daiDebt,
            wethBal
        );
    }
}


contract MiscTask is RepayLoan {
    event TranferInternal(uint cdpNum, address owner, address nextOwner);
    event TranferExternal(uint cdpNum, address owner, address nextOwner);
    event CDPClaimed(uint cdpNum, address owner);
    event ResolverOneWay(uint cdpNum, address owner, address resolverAddress);
    event ResolverTwoWay(uint cdpNum, address owner, address resolverAddress);

    function transferCDPInternal(uint cdpNum, address nextOwner) public isCupOwner(cdpNum) {
        require(nextOwner != address(0x0), "Invalid Address.");
        cdps[cdpNum] = nextOwner;
        emit TranferInternal(cdpNum, msg.sender, nextOwner);
    }

    function transferCDPExternal(uint cdpNum, address nextOwner) public isCupOwner(cdpNum) {
        require(freezed, "Operation Denied.");
        require(nextOwner != address(0x0), "Invalid Address.");
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        loanMaster.give(bytes32(cdpNum), nextOwner);
        cdps[cdpNum] = address(0x0);
        emit TranferExternal(cdpNum, msg.sender, nextOwner);
    }

    // transfering CDP to resolver contract
    function changeResolverOneWay(uint cdpNum, address resolverAddress) public isCupOwner(cdpNum) {
        Resolver resolverAct = Resolver(resolverAddress);
        resolverAct.claimCDP(cdpNum);
        resolverAct.transferCDPInternal(cdpNum, resolverAddress);
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        loanMaster.give(bytes32(cdpNum), resolverAddress);
        emit ResolverOneWay(cdpNum, msg.sender, resolverAddress);
    }

    // transfering CDP to resolver contract
    // resolver contract will transfer back CDP
    function changeResolverTwoWay(uint cdpNum, address resolverAddress) public payable isCupOwner(cdpNum) {
        Resolver resolverAct = Resolver(resolverAddress);
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        loanMaster.give(bytes32(cdpNum), resolverAddress);
        resolverAct.initAct(cdpNum);
        emit ResolverTwoWay(cdpNum, msg.sender, resolverAddress);
    }

    function claimCDP(uint cdpNum) public {
        bytes32 cup = bytes32(cdpNum);
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        address cdpOwner = loanMaster.lad(cup);
        cdps[cdpNum] = cdpOwner;
        emit CDPClaimed(cdpNum, msg.sender);
    }

    function getETHRate() public view returns (uint) {
        PriceInterface ethRate = PriceInterface(getAddress("ethfeed"));
        bytes32 ethrate;
        (ethrate, ) = ethRate.peek();
        return uint(ethrate);
    }

    function getCDP(uint cdpNum) public view returns (address, bytes32) {
        return (cdps[cdpNum], bytes32(cdpNum));
    }

    function approveERC20() public {
        IERC20 wethTkn = IERC20(getAddress("weth"));
        wethTkn.approve(cdpAddr, 2 ** 256 - 1);
        IERC20 pethTkn = IERC20(getAddress("peth"));
        pethTkn.approve(cdpAddr, 2 ** 256 - 1);
        IERC20 mkrTkn = IERC20(getAddress("mkr"));
        mkrTkn.approve(cdpAddr, 2 ** 256 - 1);
        IERC20 daiTkn = IERC20(getAddress("dai"));
        daiTkn.approve(cdpAddr, 2 ** 256 - 1);
    }
}


contract InstaBank is MiscTask {
    event MKRCollected(uint amount);

    constructor(address rAddr) public {
        addressRegistry = rAddr;
        cdpAddr = getAddress("cdp");
        approveERC20();
    }

    function() external payable {}

    function freeze(bool stop) public onlyAdmin {
        freezed = stop;
    }

    function manageResolver(address resolverAddress, bool isAllowed) public onlyAdmin {
        resolvers[resolverAddress] = isAllowed;
    }

    // collecting MKR token kept as balance to pay fees
    function collectMKR(uint amount) public onlyAdmin {
        IERC20 mkrTkn = IERC20(getAddress("mkr"));
        mkrTkn.transfer(msg.sender, amount);
        emit MKRCollected(amount);
    }
}