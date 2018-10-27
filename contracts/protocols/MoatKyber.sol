// error with OMG fee collection

pragma solidity ^0.4.24;

interface token {
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address receiver, uint amount) external returns (bool);
    function balanceOf(address who) external returns(uint256);
    function transferFrom(address from, address to, uint amount) external returns (bool);
}

interface AddressRegistry {
    function getAddr(string name) external returns(address);
}

interface Resolver {
    function fees() external returns(uint);
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

    modifier onlyUserOrResolver(address trader) {
        if (msg.sender != trader) {
            require(
                msg.sender == getAddress("resolver"),
                "Permission Denied"
            );
        }
        _;
    }

    modifier onlyAdmin() {
        require(
            msg.sender == getAddress("admin"),
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


contract Trade is Registry {

    event KyberTrade(
        address src,
        uint srcAmt,
        address dest,
        uint destAmt,
        address beneficiary,
        uint fees,
        uint slipRate,
        address affiliate
    );

    address eth = 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;

    function executeTrade(
        address trader,
        address src,
        address dest,
        uint srcAmt,
        uint slipRate
    ) public payable onlyUserOrResolver(trader) returns (uint destAmt)
    {

        if (src != eth) {
            token tokenFunctions = token(src);
            tokenFunctions.transferFrom(msg.sender, address(this), srcAmt);
        }

        uint fees = deductFees(src, srcAmt);

        Kyber kyberFunctions = Kyber(getAddress("kyber"));
        destAmt = kyberFunctions.trade.value(msg.value)(
            src,
            srcAmt - fees,
            dest,
            msg.sender,
            2**256 - 1,
            slipRate,
            getAddress("admin")
        );

        emit KyberTrade(
            src,
            srcAmt,
            dest,
            destAmt,
            msg.sender,
            fees,
            slipRate,
            getAddress("admin")
        );

    }

    function deductFees(address src, uint volume) public returns(uint fees) {
        Resolver moatRes = Resolver(getAddress("kyber"));
        fees = volume/moatRes.fees();
        if (fees > 0) {
            if (src == eth) {
                getAddress("admin").transfer(fees);
            } else {
                token tokenFunctions = token(src);
                tokenFunctions.transfer(getAddress("admin"), fees);
            }
        }
    }

    function allowKyber(address[] tokenArr) public {
        for (uint i = 0; i < tokenArr.length; i++) {
            token tokenFunctions = token(tokenArr[i]);
            tokenFunctions.approve(getAddress("kyber"), 2**256 - 1);
        }
    }

}


contract MoatKyber is Trade {

    constructor(address rAddr) public {
        registryAddress = rAddr;
    }

    function () public payable {}

    function collectFees(address tokenAddress, uint amount) public onlyAdmin {
        if (tokenAddress == eth) {
            msg.sender.transfer(amount);
        } else {
            token tokenFunctions = token(tokenAddress);
            tokenFunctions.transfer(msg.sender, amount);
        }
    }

}