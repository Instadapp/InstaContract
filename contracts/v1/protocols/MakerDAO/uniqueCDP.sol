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

interface AddressRegistry {
    function getAddr(string calldata name) external view returns (address);
}

interface MakerCDP {
    function open() external returns (bytes32 cup);
    function give(bytes32 cup, address guy) external;
}


contract UniqueCDP {
    address public deployer;
    address public cdpAddr;

    constructor(address saiTub) public {
        deployer = msg.sender;
        cdpAddr = saiTub;
    }

    function registerCDP(uint maxCup) public {
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        for (uint i = 0; i < maxCup; i++) {
            loanMaster.open();
        }
    }

    function transferCDP(address nextOwner, uint cdpNum) public {
        require(msg.sender == deployer, "Invalid Address.");
        MakerCDP loanMaster = MakerCDP(cdpAddr);
        loanMaster.give(bytes32(cdpNum), nextOwner);
    }

}
