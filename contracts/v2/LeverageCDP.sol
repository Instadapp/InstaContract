pragma solidity 0.4.24;

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
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface AddressRegistry {
    function getAddr(string name) external view returns(address);
}

interface MakerCDP {
    function open() external returns (bytes32 cup);
    function join(uint wad) external; // Join PETH
    function give(bytes32 cup, address guy) external;
    function lock(bytes32 cup, uint wad) external;
    function draw(bytes32 cup, uint wad) external;
    function per() external view returns (uint ray);
}

interface PriceInterface {
    function peek() external view returns (bytes32, bool);
}

interface WETHFace {
    function deposit() external payable;
}

interface Swap {
    function dai2eth(uint srcDAI) external payable returns (uint destETH);
    function expectedETH(uint srcDAI) external view returns (uint, uint);
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

    address public cdpAddr; // SaiTub
    bool public freezed;

    function getETHRate() public view returns (uint) {
        PriceInterface ethRate = PriceInterface(getAddress("ethfeed"));
        bytes32 ethrate;
        (ethrate, ) = ethRate.peek();
        return uint(ethrate);
    }

    function approveERC20() public {
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


contract LoopNewCDP is GlobalVar {

    event LevNewCDP(uint cdpNum, uint ethLocked, uint daiMinted);

    function pethPEReth(uint ethNum) public view returns (uint rPETH) {
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        rPETH = (ethNum.mul(10 ** 27)).div(loanMaster.per());
    }

    // useETH = msg.sender + personal ETH used to assist the operation
    function riskNewCDP(uint eth2Lock, uint dai2Mint) public payable {
        require(!freezed, "Operation Disabled");

        uint ethBal = address(this).balance;

        MakerCDP loanMaster = MakerCDP(cdpAddr);
        bytes32 cup = loanMaster.open(); // New CDP

        WETHFace wethTkn = WETHFace(getAddress("weth"));
        wethTkn.deposit.value(eth2Lock)(); // ETH to WETH
        uint pethToLock = pethPEReth(msg.value); // PETH : ETH
        loanMaster.join(pethToLock); // WETH to PETH
        loanMaster.lock(cup, pethToLock); // PETH to CDP

        loanMaster.draw(cup, dai2Mint);
        IERC20 daiTkn = IERC20(getAddress("dai"));

        address dai2eth = getAddress("dai2eth"); // DAI to ETH swapper
        daiTkn.transfer(dai2eth, dai2Mint);
        // SWAP DAI 2 ETH

        uint nowBal = address(this).balance;
        if (ethBal > nowBal) {
            msg.sender.transfer(ethBal - nowBal);
        }
        require(ethBal == nowBal, "No Refund of Contract ETH");

        // transfer CDP to v2 InstaBank

        emit LevNewCDP(uint(cup), eth2Lock, dai2Mint);
    }

}


contract LeverageCDP is LoopNewCDP {

    constructor(address rAddr) public {
        addressRegistry = rAddr;
        cdpAddr = getAddress("cdp");
        approveERC20();
    }

    function () public payable {}

    function freeze(bool stop) public onlyAdmin {
        freezed = stop;
    }

}