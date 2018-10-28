pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

interface AddressRegistry {
    function getAddr(string name) external returns(address);
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

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry addrReg = AddressRegistry(registryAddress);
        addr = addrReg.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }

}


contract FeeDetail is Registry {

    uint public fees;
    function setFees(uint cut) public onlyAdmin { // 200 means 0.5%
        fees = cut;
    }

}


contract MoatResolver is FeeDetail {

    function () public payable {}

    constructor(address rAddr, uint cut) public { // 200 means 0.5%
        registryAddress = rAddr;
        setFees(cut);
    }

    function collectAsset(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            msg.sender.transfer(amount);
        } else {
            IERC20 tokenFunctions = IERC20(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

}
