pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


interface AddressRegistry {
    function getAddr(string name) external view returns(address);
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
    function per() external view returns (uint ray);
}

interface PriceInterface {
    function peek() external view returns (bytes32, bool);
}

interface WETHFace {
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
    ) external payable returns (uint destAmt);

    function getExpectedPrice(
        address src,
        address dest,
        uint srcAmt
    ) external view returns (uint, uint);
}


contract Registry {

    address public addressRegistry;
    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
            "Permission Denied"
        );
        _;
    }
    
    function getAddress(string name) internal view returns(address) {
        AddressRegistry addrReg = AddressRegistry(addressRegistry);
        return addrReg.getAddr(name);
    }

}


contract GlobalVar is Registry {

    using SafeMath for uint;
    using SafeMath for uint256;

    // kovan network
    // address public weth = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;
    // address public peth = 0xf4d791139cE033Ad35DB2B2201435fAd668B1b64;
    // address public mkr = 0xAaF64BFCC32d0F15873a02163e7E500671a4ffcD;
    // address public dai = 0xC4375B7De8af5a38a93548eb8453a498222C4fF2;
    // address public eth = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;
    // address public cdpAddr = 0xa71937147b55Deb8a530C7229C442Fd3F31b7db2;

    // address public ethfeed = 0x729D19f657BD0614b4985Cf1D82531c67569197B // pip
    // address public mkrfeed = 0x99041F808D598B782D5a3e498681C2452A31da08 // pep

    MakerCDP loanMaster = MakerCDP(getAddress("cdp"));

    bytes32 public blankCDP = 0x0000000000000000000000000000000000000000000000000000000000000000;
    mapping (address => bytes32) public cdps; // borrower >>> CDP Bytes
    bool public freezed;
}


contract IssueLoan is GlobalVar {

    event LockedETH(address borrower, uint lockETH, uint lockPETH);
    event LoanedDAI(address borrower, uint loanDAI);
    event OpenedNewCDP(address borrower, bytes32 cdpBytes);

    function pethPEReth(uint ethNum) public view returns (uint rPETH) {
        rPETH = (ethNum.mul(10 ** 27)).div(loanMaster.per());
    }

    function borrow(uint daiDraw) public payable {
        if (cdps[msg.sender] == blankCDP) {
            cdps[msg.sender] = loanMaster.open();
            emit OpenedNewCDP(msg.sender, cdps[msg.sender]);
        }
        if (msg.value > 0) {lockETH();}
        if (daiDraw > 0) {drawDAI(daiDraw);}
    }

    function lockETH() public payable {
        WETHFace wethTkn = WETHFace(getAddress("weth"));
        wethTkn.deposit.value(msg.value)(); // ETH to WETH
        uint pethToLock = pethPEReth(msg.value);
        loanMaster.join(pethToLock); // WETH to PETH
        loanMaster.lock(cdps[msg.sender], pethToLock); // PETH to CDP
        emit LockedETH(msg.sender, msg.value, pethToLock);
    }

    function drawDAI(uint daiDraw) public {
        require(!freezed, "Operation Disabled");
        loanMaster.draw(cdps[msg.sender], daiDraw);
        IERC20 daiTkn = IERC20(getAddress("dai"));
        daiTkn.transfer(msg.sender, daiDraw);
        emit LoanedDAI(msg.sender, daiDraw);
    }

}


contract RepayLoan is IssueLoan {

    event WipedDAI(address borrower, uint daiWipe, uint mkrCharged);
    event UnlockedETH(address borrower, uint ethFree);

    function repay(
        uint daiWipe,
        uint ethFree
        // bool mkrFees, // either this...
        // uint feeMinConRate // or this is 0
    ) public payable
    {
        if (daiWipe > 0) {wipeDAI(daiWipe);}
        if (ethFree > 0) {unlockETH(ethFree);}
    }

    function wipeDAI(uint daiWipe) public payable {
        address dai = getAddress("dai");
        address mkr = getAddress("mkr");
        address eth = getAddress("eth");

        IERC20 daiTkn = IERC20(dai);
        IERC20 mkrTkn = IERC20(mkr);

        // contract MKR balance before wiping
        uint contractMKR = mkrTkn.balanceOf(address(this));
        // get DAI
        daiTkn.transferFrom(msg.sender, address(this), daiWipe); // DAI to pay the debt
        // wipe DAI
        loanMaster.wipe(cdps[msg.sender], daiWipe);
        // MKR fee = before wiping bal - after wiping bal
        uint mkrCharged = contractMKR - mkrTkn.balanceOf(address(this));

        // claiming paid MKR back
        if (msg.value > 0) {
            // Interacting with Kyber to swap ETH with MKR
            InstaKyber instak = InstaKyber(getAddress("InstaKyber"));
            uint minRate;
            (, minRate) = instak.getExpectedPrice(eth, mkr, msg.value);
            uint mkrBought = instak.executeTrade.value(msg.value)(
                eth,
                mkr,
                msg.value,
                minRate,
                mkrCharged
            );

            require(mkrCharged == mkrBought, "ETH not sufficient to cover the MKR fees.");

            // the ether will always belong to sender as there's no way contract can accept ether 
            if (address(this).balance > 0) {
                msg.sender.transfer(address(this).balance);
            }

        } else {
            // take MKR directly from address
            mkrTkn.transferFrom(msg.sender, address(this), mkrCharged); // user paying MKR fees
        }

        emit WipedDAI(msg.sender, daiWipe, mkrCharged);
    }

    function unlockETH(uint ethFree) public {
        require(!freezed, "Operation Disabled");
        uint pethToUnlock = pethPEReth(ethFree);
        loanMaster.free(cdps[msg.sender], pethToUnlock); // CDP to PETH
        loanMaster.exit(pethToUnlock); // PETH to WETH
        WETHFace wethTkn = WETHFace(getAddress("weth"));
        wethTkn.withdraw(ethFree); // WETH to ETH
        msg.sender.transfer(ethFree);
        emit UnlockedETH(msg.sender, ethFree);
    }

}


contract BorrowTasks is RepayLoan {

    event TranferCDP(bytes32 cdp, address owner, address nextOwner);

    function transferCDP(address nextOwner) public {
        require(nextOwner != 0, "Invalid Address.");
        loanMaster.give(cdps[msg.sender], nextOwner);
        emit TranferCDP(cdps[msg.sender], msg.sender, nextOwner);
        cdps[msg.sender] = blankCDP;
    }

    function getETHRate() public view returns (uint) {
        PriceInterface ethRate = PriceInterface(getAddress("ethfeed"));
        bytes32 ethrate;
        (ethrate, ) = ethRate.peek();
        return uint(ethrate).div(10**18);
    }

    function getCDPID(address borrower) public view returns (uint) {
        return uint(cdps[borrower]);
    }

    function approveERC20() public {
        address cdpAddr = getAddress("cdp");
        IERC20 wethTkn = IERC20(getAddress("weth"));
        wethTkn.approve(cdpAddr, 2**256 - 1);
        IERC20 pethTkn = IERC20(getAddress("peth"));
        pethTkn.approve(cdpAddr, 2**256 - 1);
        IERC20 mkrTkn = IERC20(getAddress("mkr"));
        mkrTkn.approve(cdpAddr, 2**256 - 1);
        IERC20 daiTkn = IERC20(getAddress("dai"));
        daiTkn.approve(cdpAddr, 2**256 - 1);
    }

}


contract MoatMaker is BorrowTasks {

    constructor(address rAddr) public {
        addressRegistry = rAddr;
        approveERC20();
    }

    function freeze(bool stop) public onlyAdmin {
        freezed = stop;
    }

}
