// IMPORTANT CHECK - how decimal works on tokens with less than 18 decimals and accordingly store in our MoatAsset DB

pragma solidity ^0.4.24;

interface token {
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address receiver, uint amount) external returns (bool);
    function balanceOf(address who) external returns(uint256);
}

interface AddressRegistry {
    function getAddr(string name) external returns(address);
}

interface Kyber {
    function trade(
        address src,
        uint srcAmount,
        address dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId
    ) external payable returns (uint);
}


contract Registry {

    address public registryAddress;
    modifier onlyResolver() {
        require(
            msg.sender == getAddress("resolver"),
            "Permission Denied"
        );
        _;
    }

    function getAddress(string name) internal view returns(address addr) {
        AddressRegistry aRegistry = AddressRegistry(registryAddress);
        addr = aRegistry.getAddr(name);
        require(addr != address(0), "Invalid Address");
    }
 
}


contract KyberSwap is Registry {

    event Swapped(address src, uint srcAmt, address dest, uint destAmt);

    function executeTrade(
        uint weiAmt,
        address src,
        address dest,
        uint srcAmt,
        uint slipRate,
        address walletId
    ) public onlyResolver returns (uint destAmt) 
    {
        Kyber kyberFunctions = Kyber(getAddress("kyber"));
        destAmt = kyberFunctions.trade.value(weiAmt)(
            src,
            srcAmt,
            dest,
            getAddress("asset"),
            2**256 - 1,
            slipRate,
            walletId
        );
        emit Swapped(
            src,
            srcAmt,
            dest,
            destAmt
        );
    }

    function allowKyber(address[] tokenArr) public {
        for (uint i = 0; i < tokenArr.length; i++) {
            token tokenFunctions = token(tokenArr[i]);
            tokenFunctions.approve(getAddress("kyber"), 2**256 - 1);
        }
    }

}


contract KyberInit is KyberSwap {

    constructor(address rAddr) public {
        registryAddress = rAddr;
    }

    function () public payable {}

}