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
    // address public pricefeed = 0xA944bd4b25C9F186A846fd5668941AA3d3B8425F;
    // address public cdpAddr = 0xa71937147b55Deb8a530C7229C442Fd3F31b7db2;

    MakerCDP loanMaster = MakerCDP(getAddress("cdp"));

    bytes32 public blankCDP = 0x0000000000000000000000000000000000000000000000000000000000000000;
    mapping (address => bytes32) public cdps; // borrower >>> CDP Bytes
    bool public freezed;
    uint public fees;
}


contract IssueLoan is GlobalVar {

    event LockedETH(address borrower, uint lockETH, uint lockPETH);
    event LoanedDAI(address borrower, uint loanDAI, uint fees);
    event OpenedNewCDP(address borrower, bytes32 cdpBytes);

    function pethPEReth(uint ethNum) public view returns (uint rPETH) {
        rPETH = div(mul(ethNum, 10 ** 27), loanMaster.per());
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
        uint feecut = deductFees(daiDraw);
        IERC20 daiTkn = IERC20(getAddress("dai"));
        daiTkn.transfer(msg.sender, sub(daiDraw, feecut));
        emit LoanedDAI(msg.sender, daiDraw, feecut);
    }

    function deductFees(uint volume) internal returns(uint brokerage) {
        if (fees > 0) {
            brokerage = div(volume, fees);
            IERC20 daiTkn = IERC20(getAddress("dai"));
            daiTkn.transfer(getAddress("admin"), brokerage);
        }
    }

}


contract RepayLoan is IssueLoan {

    event WipedDAI(address borrower, uint daiWipe);
    event UnlockedETH(address borrower, uint ethFree);

    function repay(
        uint daiWipe,
        uint mkrFees,
        uint ethFree
    ) public 
    {
        if (daiWipe > 0) {wipeDAI(daiWipe, mkrFees);}
        if (ethFree > 0) {unlockETH(ethFree);}
    }

    function wipeDAI(uint daiWipe, uint mkrFees) public {
        IERC20 mkrTkn = IERC20(getAddress("mkr"));
        IERC20 daiTkn = IERC20(getAddress("dai"));
        mkrTkn.transferFrom(msg.sender, address(this), mkrFees); // MKR tokens to pay the debt fees
        daiTkn.transferFrom(msg.sender, address(this), daiWipe); // DAI to pay the debt
        loanMaster.wipe(cdps[msg.sender], daiWipe);
        mkrTkn.transfer(msg.sender, mkrTkn.balanceOf(address(this))); // pay back balanced MKR tokens
        emit WipedDAI(msg.sender, daiWipe);
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
        PriceInterface ethRate = PriceInterface(getAddress("price"));
        bytes32 ethrate;
        (ethrate, ) = ethRate.peek();
        return div(uint(ethrate), 10**18);
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

    function () public payable {}

    function collectAsset(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == getAddress("eth")) {
            msg.sender.transfer(amount);
        } else {
            IERC20 tokenFunctions = IERC20(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

    function freeze(bool stop) public onlyAdmin {
        freezed = stop;
    }

    function setFees(uint cut) public onlyAdmin { // 200 means 0.5%
        fees = cut;
    }

}
