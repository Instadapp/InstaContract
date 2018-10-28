pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


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
            AddressRegistry addrReg = AddressRegistry(registryAddress);
            require(
                addrReg.isApprovedResolver(user),
                "Resolver Not Approved"
            );
        }
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry addrReg = AddressRegistry(registryAddress);
        addr = addrReg.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }

}


contract GlobalVar is Registry {

    // kovan network
    address public weth = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;
    address public peth = 0xf4d791139cE033Ad35DB2B2201435fAd668B1b64;
    address public mkr = 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD;
    address public dai = 0xC4375B7De8af5a38a93548eb8453a498222C4fF2;
    address public eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public cdpAddr = 0xa71937147b55Deb8a530C7229C442Fd3F31b7db2;
    MakerCDP loanMaster = MakerCDP(cdpAddr);

    mapping (address => bytes32) public cdps; // borrower >>> CDP Bytes

    bool public freezed; // freeze few important tasks

}


contract IssueLoan is GlobalVar {

    event LockedETH(address borrower, uint lockETH, uint lockPETH);
    event LoanedDAI(address borrower, uint loanDAI, uint fees);
    event OpenedNewCDP(address borrower, bytes32 cdpBytes);

    function borrow(
        address borrower,
        uint ethLock,
        uint daiDraw
    ) public payable onlyUserOrResolver(borrower)
    {
        if (cdps[borrower] == 0x0000000000000000000000000000000000000000000000000000000000000000) {
            cdps[borrower] = loanMaster.open();
            emit OpenedNewCDP(borrower, cdps[borrower]);
        }
        if (ethLock > 0) {lockETH(borrower, ethLock);}
        if (daiDraw > 0) {drawDAI(borrower, daiDraw);}
    }

    function lockETH(address borrower, uint ethLock) public payable {
        WETHFace wethFunction = WETHFace(weth);
        wethFunction.deposit.value(ethLock)(); // ETH to WETH
        uint pethToLock = ratioedPETH(ethLock);
        loanMaster.join(pethToLock); // WETH to PETH
        loanMaster.lock(cdps[borrower], pethToLock); // PETH to CDP
        emit LockedETH(borrower, ethLock, pethToLock);
    }

    function drawDAI(address borrower, uint daiDraw) public onlyUserOrResolver(borrower) {
        require(!freezed, "Operation Disabled");
        loanMaster.draw(cdps[borrower], daiDraw);
        uint fees = deductFees(daiDraw);
        IERC20 tokenFunctions = IERC20(dai);
        tokenFunctions.transfer(getAddress("resolver"), daiDraw - fees);
        emit LoanedDAI(borrower, daiDraw, fees);
    }

    function ratioedPETH(uint eth) internal returns (uint rPETH) {
        rPETH = eth * (10 ** 27) / loanMaster.per();
    }

    function deductFees(uint volume) internal returns(uint fees) {
        Resolver moatRes = Resolver(getAddress("resolver"));
        fees = moatRes.fees();
        if (fees > 0) {
            fees = volume / fees;
            IERC20 tokenFunctions = IERC20(dai);
            tokenFunctions.transfer(getAddress("admin"), fees);
        }
    }

}


contract RepayLoan is IssueLoan {

    event WipedDAI(address borrower, uint daiWipe);
    event UnlockedETH(address borrower, uint ethFree);

    function repay(
        address borrower,
        uint daiWipe,
        uint mkrFees,
        uint ethFree
    ) public onlyUserOrResolver(borrower)
    {
        if (daiWipe > 0) {wipeDAI(borrower, daiWipe, mkrFees);}
        if (ethFree > 0) {unlockETH(borrower, ethFree);}
    }

    function wipeDAI(address borrower, uint daiWipe, uint mkrFees) public {

        // MKR tokens to pay the debt fees
        // difference between MKR fees and transferred amount stays with contract
        IERC20 mkrToken = IERC20(mkr);
        mkrToken.transferFrom(borrower, address(this), mkrFees);

        // DAI to pay the debt
        IERC20 daiToken = IERC20(dai);
        daiToken.transferFrom(borrower, address(this), daiWipe);
        loanMaster.wipe(cdps[borrower], daiWipe);

        emit WipedDAI(borrower, daiWipe);
    }

    function unlockETH(address borrower, uint ethFree) public onlyUserOrResolver(borrower) {
        require(!freezed, "Operation Disabled");
        uint pethToUnlock = ratioedPETH(ethFree);
        loanMaster.free(cdps[borrower], pethToUnlock); // CDP to PETH
        loanMaster.exit(pethToUnlock); // PETH to WETH
        WETHFace wethFunction = WETHFace(weth);
        wethFunction.withdraw(ethFree); // WETH to ETH
        borrower.transfer(ethFree);
        emit UnlockedETH(borrower, ethFree);
    }

}


contract BorrowTasks is RepayLoan {

    function freeze(bool stop) public onlyAdmin {
        freezed = stop;
    }

    function claimCDP(address nextOwner) public {
        require(nextOwner != 0, "Invalid Address.");
        loanMaster.give(cdps[msg.sender], nextOwner);
    }

    function approveERC20() public {
        IERC20 wethTkn = IERC20(weth);
        wethTkn.approve(cdpAddr, 2**256 - 1);
        IERC20 pethTkn = IERC20(peth);
        pethTkn.approve(cdpAddr, 2**256 - 1);
        IERC20 mkrTkn = IERC20(mkr);
        mkrTkn.approve(cdpAddr, 2**256 - 1);
        IERC20 daiTkn = IERC20(dai);
        daiTkn.approve(cdpAddr, 2**256 - 1);
    }

}


contract MoatMaker is BorrowTasks {

    constructor(address rAddr) public {
        registryAddress = rAddr;
        approveERC20();
    }

    function () public payable {}

    function collectAsset(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == eth) {
            msg.sender.transfer(amount);
        } else {
            IERC20 tokenFunctions = IERC20(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

}
